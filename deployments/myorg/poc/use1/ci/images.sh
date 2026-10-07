#!/usr/bin/env bash
set -euo pipefail

location_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${location_dir}/../../../.." && pwd)"
registry="${location_dir}/ci/images.yml"
operation="${1:-validate}"
selected="${2:-all}"

image_names() {
  ruby -e 'require "yaml"; YAML.load_file(ARGV[0]).fetch("images").keys.each { |k| puts k }' "$registry"
}

image_field() {
  ruby -e 'require "yaml"; puts YAML.load_file(ARGV[0]).fetch("images").fetch(ARGV[1]).fetch(ARGV[2])' "$registry" "$1" "$2"
}

config_field() {
  ruby -e 'require "yaml"; puts YAML.load_file(ARGV[0]).fetch(ARGV[1])' "$1" "$2"
}

run_one() {
  local name="$1" rel_path path param cfg region instance owner source_name prefix manifest ami
  rel_path="$(image_field "$name" path)"
  param="$(image_field "$name" ssm_parameter)"
  path="${repo_root}/${rel_path}"
  cfg="${path}/config/image.yml"
  region="$(config_field "$cfg" region)"
  instance="$(config_field "$cfg" instance_type)"
  owner="$(config_field "$cfg" source_ami_owner)"
  source_name="$(config_field "$cfg" source_ami_name)"
  prefix="$(config_field "$cfg" ami_name_prefix)"

  (
    cd "$path"
    packer init .
    packer fmt -check .
    packer validate \
      -var "region=${region}" \
      -var "instance_type=${instance}" \
      -var "source_ami_owner=${owner}" \
      -var "source_ami_name=${source_name}" \
      -var "ami_name_prefix=${prefix}" \
      .

    if [[ "$operation" == "build" ]]; then
      rm -f manifest.json
      packer build \
        -var "region=${region}" \
        -var "instance_type=${instance}" \
        -var "source_ami_owner=${owner}" \
        -var "source_ami_name=${source_name}" \
        -var "ami_name_prefix=${prefix}" \
        .
    fi
  )

  if [[ "$operation" == "build" ]]; then
    manifest="${path}/manifest.json"
    ami="$(ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); puts j.fetch("builds").last.fetch("artifact_id").split(":").last' "$manifest")"
    aws ssm put-parameter --region "$region" --name "$param" --type String --value "$ami" --overwrite >/dev/null
    echo "published ${name} AMI ${ami} to ${param}"
  fi
}

if [[ "$selected" == "all" ]]; then
  while IFS= read -r name; do
    run_one "$name"
  done < <(image_names)
else
  image_names | grep -Fx -- "$selected" >/dev/null || { echo "unknown image: $selected" >&2; exit 2; }
  run_one "$selected"
fi
