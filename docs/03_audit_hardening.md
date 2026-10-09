# Audit-hardening: RDS migration, GuardDuty and WAF

This branch extends the existing `myorg/poc/use1` Terraform location. It does
not introduce another Terraform state root. The EC2 MySQL instance and its DLM
snapshot policy remain managed until a separately approved retirement.

## Terraform resources and ordering

1. Apply `deployments/myorg/poc/use1/vpc` to add the private `database-b`
   subnet (`us-east-1b`, `10.42.21.0/24`). Existing `database-a` remains in
   `us-east-1a`. RDS requires a DB subnet group spanning at least two AZs.
2. Apply `deployments/myorg/poc/use1/logging` for regional GuardDuty.
3. Apply `deployments/myorg/poc/use1/ec2` for a private MySQL 8.4 RDS instance
   with Multi-AZ standby, AWS-managed KMS encryption, seven-day automated
   backups and deletion protection; plus an ALB-associated regional WAF ACL.

Use the existing plan/review/apply workflow for these roots. The EC2 root still
manages the old MySQL EC2 instance, which is required as the migration source.
The RDS master password is managed in AWS Secrets Manager, not stored in
Terraform configuration or outputs.

### GuardDuty adoption

GuardDuty supports exactly one detector per AWS account and Region. Check the
account before the first Terraform apply:

```bash
aws guardduty list-detectors --region us-east-1 --output json
```

If a detector already exists, import its ID into the existing logging root
before running the apply:

```bash
terraform -chdir=deployments/myorg/poc/use1/logging import \
  module.logging.aws_guardduty_detector.regional DETECTOR_ID
```

If no detector exists, the logging Terraform root creates it. Never enable a
second detector via another Terraform state root in the same account/Region.

## Planned MySQL cutover (requires downtime)

The database cutover is **not** triggered by Terraform apply. The customer
application artifact is still a placeholder, so its handling of the existing
`MYORG_DATABASE_SECRET` name and the secret's `host`/`port` fields must be
confirmed before traffic is resumed.

1. Confirm RDS is available. Record the EC2 Terraform outputs
   `database_instance_id`, `database_rds_endpoint`,
   `database_rds_master_secret_arn` and `database_secret_arn`.
2. Stop application writes, stop application workers and preserve a recoverable
   source snapshot/backup. Do not resume writes during the dump and restore.
3. Open an SSM session on the **existing database EC2 instance**. This is the
   migration source and has a VPC security-group path to the private RDS
   instance. Copy `scripts/migrate-mysql-ec2-to-rds.sh` there.
4. Obtain the RDS master password using the master secret ARN and an authorized
   operator identity. Supply it through the interactive SSM shell without
   placing credentials in a script, Terraform variable or shell history:

```bash
export AWS_DEFAULT_REGION=us-east-1
export DATABASE_SECRET_ID=myorg-poc-use1/database
export RDS_HOST=RDS_ENDPOINT_FROM_TERRAFORM_OUTPUT
export RDS_MASTER_USER=myorg_admin
read -r -s -p 'RDS master password: ' RDS_MASTER_PASSWORD
export RDS_MASTER_PASSWORD
bash scripts/migrate-mysql-ec2-to-rds.sh
unset RDS_MASTER_PASSWORD
```

The script streams a transactional MySQL dump directly into RDS using TLS,
creates/updates the database application principal with the existing secret's
password, and only then adds the RDS `host` and `port` to the same application
Secrets Manager secret. It does **not** delete or stop the EC2 database,
start the application, or issue a Terraform apply.

5. Ensure the application reads the updated endpoint from Secrets Manager,
   restart/roll it under operator control, verify its DB connection and data,
   then release the write freeze.

### Failure and rollback

If any import or connectivity step fails, keep application writes stopped and
continue using the existing EC2 database only after confirming its data is
intact. If the secret was switched, restore the previous secret version (or its
original fields) before restarting the application. Once writes have resumed
against RDS, switching back requires data reconciliation; no automatic
rollback is provided.

The old EC2 instance and DLM policy remain active until a **separate approved
decommission**. RDS deletion protection intentionally blocks direct deletion
on Terraform destroy. Multi-AZ RDS, GuardDuty and WAF introduce recurring AWS
charges. WAF uses the AWS-managed IP Reputation and Common Rule groups with
their blocking actions, so false positives can reject legitimate requests.

The branch does not enable AWS Config or Security Hub and does not change
GitHub Actions permissions or deployment workflow behavior.
