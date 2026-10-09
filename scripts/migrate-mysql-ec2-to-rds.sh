#!/usr/bin/env bash
# Run on the existing MySQL EC2 instance, after stopping all application writes.
# The instance role can read/update the existing application database secret.
# Supply the RDS master credentials out of band; they are never written to disk.
set -euo pipefail

: "${RDS_HOST:?RDS_HOST is required}"
: "${RDS_MASTER_USER:?RDS_MASTER_USER is required}"
: "${RDS_MASTER_PASSWORD:?RDS_MASTER_PASSWORD is required}"
: "${DATABASE_SECRET_ID:?DATABASE_SECRET_ID is required}"

region="${AWS_DEFAULT_REGION:-us-east-1}"
secret_json="$(aws secretsmanager get-secret-value \
  --region "$region" \
  --secret-id "$DATABASE_SECRET_ID" \
  --query SecretString \
  --output text)"

database="$(jq -er '.database' <<<"$secret_json")"
app_username="$(jq -er '.username' <<<"$secret_json")"
app_password="$(jq -er '.password' <<<"$secret_json")"

# These identifiers are rendered into MySQL statements and must be simple names.
if [[ ! "$database" =~ ^[a-zA-Z0-9_]+$ || ! "$app_username" =~ ^[a-zA-Z0-9_]+$ ]]; then
  printf '%s\n' 'Database or application username contains unsupported characters' >&2
  exit 1
fi

# Escape the application password as a MySQL single-quoted string literal.
sql_password="${app_password//\\/\\\\}"
sql_password="${sql_password//\'/\'\'}"

# Source: local MySQL Unix socket (root via sudo). Target: private RDS over TLS.
# No temporary dump or password file is created.
sudo mysqldump \
  --single-transaction \
  --routines \
  --events \
  --triggers \
  --databases "$database" \
  | MYSQL_PWD="$RDS_MASTER_PASSWORD" mysql \
      --host="$RDS_HOST" \
      --port=3306 \
      --user="$RDS_MASTER_USER" \
      --ssl-mode=REQUIRED

MYSQL_PWD="$RDS_MASTER_PASSWORD" mysql \
  --host="$RDS_HOST" \
  --port=3306 \
  --user="$RDS_MASTER_USER" \
  --ssl-mode=REQUIRED <<SQL
CREATE USER IF NOT EXISTS '$app_username'@'10.%' IDENTIFIED BY '$sql_password';
ALTER USER '$app_username'@'10.%' IDENTIFIED BY '$sql_password';
GRANT ALL PRIVILEGES ON \`$database\`.* TO '$app_username'@'10.%';
SQL

# Switch the existing application secret only after the import and grants work.
# The application bootstrap already refers to this secret by name.
updated_secret="$(jq -c --arg host "$RDS_HOST" \
  '. + {host: $host, port: 3306}' <<<"$secret_json")"
printf '%s' "$updated_secret" | aws secretsmanager put-secret-value \
  --region "$region" \
  --secret-id "$DATABASE_SECRET_ID" \
  --secret-string file:///dev/stdin >/dev/null

printf '%s\n' 'Import complete; application database secret now points to RDS.'
