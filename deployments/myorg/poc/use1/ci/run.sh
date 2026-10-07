\
#!/usr/bin/env bash
set -euo pipefail

location_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${location_dir}/../../../.." && pwd)"
ci_config="${location_dir}/ci/config.yml"
operation="${1:-validate}"
stack="${2:-}"

stack_names() {
  ruby -e 'require "yaml"; YAML.load_file(ARGV[0]).fetch("stacks").each { |name| puts name }' "$ci_config"
}

state_bucket_prefix() {
  ruby -e 'require "yaml"; puts YAML.load_file(ARGV[0]).fetch("state_bucket_prefix")' "$ci_config"
}

state_bucket() {
  local account_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  printf '%s-%s\n' "$(state_bucket_prefix)" "$account_id"
}

assert_stack() {
  stack_names | grep -Fx -- "$1" >/dev/null || {
    echo "unknown stack: $1" >&2
    exit 2
  }
}

init_remote_stack() {
  local name="$1"
  terraform -chdir="${location_dir}/${name}" init \
    -input=false \
    -backend-config="bucket=$(state_bucket)"
}

bootstrap_state_stack() {
  local dir="${location_dir}/terraform-state"
  local bucket

  # The bucket cannot back the state that creates it. Bootstrap locally once,
  # then immediately migrate this stack to its own S3 state object.
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" apply -input=false -auto-approve

  bucket="$(terraform -chdir="$dir" output -raw bucket_name)"

  terraform -chdir="$dir" init \
    -input=false \
    -migrate-state \
    -force-copy \
    -backend-config="bucket=${bucket}"
}

validate_all() {
  ruby "${repo_root}/scripts/validate-config.rb" "$location_dir"
  terraform -chdir="$repo_root" fmt -check -recursive

  while IFS= read -r name; do
    echo "==> terraform validate: ${name}"
    terraform -chdir="${location_dir}/${name}" init -backend=false -input=false >/dev/null
    terraform -chdir="${location_dir}/${name}" validate
  done < <(stack_names)
}

plan_stack() {
  local name="$1"
  assert_stack "$name"

  if [[ "$name" == "terraform-state" ]] && \
     ! aws s3api head-bucket --bucket "$(state_bucket)" >/dev/null 2>&1; then
    terraform -chdir="${location_dir}/${name}" init -backend=false -input=false
  else
    init_remote_stack "$name"
  fi

  terraform -chdir="${location_dir}/${name}" plan -input=false
}

apply_stack() {
  local name="$1"
  assert_stack "$name"

  if [[ "$name" == "terraform-state" ]]; then
    if aws s3api head-bucket --bucket "$(state_bucket)" >/dev/null 2>&1; then
      init_remote_stack "$name"
      terraform -chdir="${location_dir}/${name}" plan -input=false -out=tfplan
      terraform -chdir="${location_dir}/${name}" apply -input=false tfplan
      rm -f "${location_dir}/${name}/tfplan"
    else
      bootstrap_state_stack
    fi
    return
  fi

  init_remote_stack "$name"
  terraform -chdir="${location_dir}/${name}" plan -input=false -out=tfplan
  terraform -chdir="${location_dir}/${name}" apply -input=false tfplan
  rm -f "${location_dir}/${name}/tfplan"
}

case "$operation" in
  validate)
    validate_all
    ;;
  plan)
    [[ -n "$stack" ]] || { echo "usage: $0 plan <stack>" >&2; exit 2; }
    plan_stack "$stack"
    ;;
  apply)
    [[ -n "$stack" ]] || { echo "usage: $0 apply <stack>" >&2; exit 2; }
    apply_stack "$stack"
    ;;
  *)
    echo "unknown operation: $operation" >&2
    exit 2
    ;;
esac
