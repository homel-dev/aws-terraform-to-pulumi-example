#!/usr/bin/env bash
set -euo pipefail

# Intentionally insecure baseline in a dedicated POC VPC, for an isolated test account only.
# AWS_PROFILE=sandbox ./scripts/aws-brownfield-seed.sh deploy|destroy

[[ $# -eq 1 && ( "$1" == deploy || "$1" == destroy ) ]] || {
  printf 'Usage: AWS_PROFILE=<profile> %s deploy|destroy\n' "$0" >&2
  exit 2
}
action="$1"
: "${AWS_PROFILE:?Set AWS_PROFILE to an authenticated isolated AWS CLI profile}"

for dependency in aws jq openssl base64 mktemp; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf 'Missing dependency: %s\n' "$dependency" >&2
    exit 1
  }
done

region="${SEED_REGION:-us-east-1}"
[[ "$region" == us-east-1 ]] || {
  printf 'ERROR: This POC VPC layout is defined only for us-east-1\n' >&2
  exit 1
}
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
state_file="${SEED_STATE_FILE:-${repo_root}/.terraform/seed/brownfield-use1.json}"
aws_cmd=(aws --profile "$AWS_PROFILE" --region "$region" --no-cli-pager)
umask 077

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
state_get() { jq -r --arg key "$1" '.resources[$key] // empty' "$state_file"; }
state_put() {
  local tmp
  tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
  jq --arg key "$1" --arg value "$2" '.resources[$key] = $value' "$state_file" > "$tmp"
  mv -f -- "$tmp" "$state_file"
}

account_id="$("${aws_cmd[@]}" sts get-caller-identity --query Account --output text)"
caller_arn="$("${aws_cmd[@]}" sts get-caller-identity --query Arn --output text)"
printf 'AWS account=%s region=%s principal=%s\n' "$account_id" "$region" "$caller_arn"

if [[ "$action" == destroy ]]; then
  [[ -f "$state_file" ]] || die "No seed manifest: $state_file"
  jq -e '.schema_version == 1 and (.resources | type == "object")' "$state_file" >/dev/null \
    || die "Invalid seed manifest: $state_file"
  [[ "$(jq -r '.account_id' "$state_file")" == "$account_id" ]] \
    || die 'AWS account differs from seed manifest; nothing deleted'
  [[ "$(jq -r '.region' "$state_file")" == "$region" ]] \
    || die 'AWS region differs from seed manifest; nothing deleted'

  # Clear each resource ID only after deletion completes. A partial teardown
  # can be resumed; only VPC resources recorded in the manifest are deleted.
  asg="$(state_get asg_name)"
  if [[ -n "$asg" ]]; then
    printf 'Deleting ASG %s and its application instance\n' "$asg"
    app_instances_json="$("${aws_cmd[@]}" autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg" --query 'AutoScalingGroups[0].Instances[].InstanceId' \
      --output json)"
    mapfile -t app_instance_ids < <(jq -r '.[]' <<< "$app_instances_json")
    "${aws_cmd[@]}" autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "$asg" --min-size 0 --max-size 0 --desired-capacity 0
    "${aws_cmd[@]}" autoscaling delete-auto-scaling-group \
      --auto-scaling-group-name "$asg" --force-delete
    # Auto Scaling has no AWS CLI waiter for deleted groups. Poll its real
    # state, then wait for its EC2 instances before removing shared SGs.
    for ((attempt=1; attempt<=60; attempt++)); do
      remaining="$("${aws_cmd[@]}" autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg" --query 'length(AutoScalingGroups)' --output text)"
      [[ "$remaining" == 0 ]] && break
      sleep 5
    done
    [[ "$remaining" == 0 ]] || die "Timed out deleting ASG $asg; manifest preserved"
    if (( ${#app_instance_ids[@]} > 0 )); then
      "${aws_cmd[@]}" ec2 wait instance-terminated --instance-ids "${app_instance_ids[@]}"
    fi
    state_put asg_name ''
  fi

  db_id="$(state_get database_instance_id)"
  if [[ -n "$db_id" ]]; then
    "${aws_cmd[@]}" ec2 terminate-instances --instance-ids "$db_id" >/dev/null
    "${aws_cmd[@]}" ec2 wait instance-terminated --instance-ids "$db_id"
    state_put database_instance_id ''
  fi

  for key in listener_https_arn listener_http_arn; do
    arn="$(state_get "$key")"
    if [[ -n "$arn" ]]; then
      "${aws_cmd[@]}" elbv2 delete-listener --listener-arn "$arn"
      state_put "$key" ''
    fi
  done

  alb="$(state_get alb_arn)"
  if [[ -n "$alb" ]]; then
    "${aws_cmd[@]}" elbv2 delete-load-balancer --load-balancer-arn "$alb"
    "${aws_cmd[@]}" elbv2 wait load-balancers-deleted --load-balancer-arns "$alb"
    state_put alb_arn ''
  fi

  arn="$(state_get target_group_arn)"
  if [[ -n "$arn" ]]; then
    "${aws_cmd[@]}" elbv2 delete-target-group --target-group-arn "$arn"
    state_put target_group_arn ''
  fi

  template_id="$(state_get launch_template_id)"
  if [[ -n "$template_id" ]]; then
    "${aws_cmd[@]}" ec2 delete-launch-template --launch-template-id "$template_id" >/dev/null
    state_put launch_template_id ''
  fi

  arn="$(state_get owned_certificate_arn)"
  if [[ -n "$arn" ]]; then
    "${aws_cmd[@]}" acm delete-certificate --certificate-arn "$arn"
    state_put owned_certificate_arn ''
  fi
  cert_key="$(state_get private_key_path)"
  cert_pem="$(state_get certificate_path)"
  if [[ "$cert_key" == "${state_file%.json}.key" ]]; then
    rm -f -- "$cert_key"
    state_put private_key_path ''
  fi
  if [[ "$cert_pem" == "${state_file%.json}.crt" ]]; then
    rm -f -- "$cert_pem"
    state_put certificate_path ''
  fi

  for key in security_group_db security_group_app security_group_alb; do
    group="$(state_get "$key")"
    if [[ -n "$group" ]]; then
      "${aws_cmd[@]}" ec2 delete-security-group --group-id "$group"
      state_put "$key" ''
    fi
  done

  # Release all seed-created networking after its workloads and SGs.
  for name in public-a public-b; do
    table="$(state_get "route_table_${name}")"
    route="$(state_get "public_route_${name}")"
    if [[ -n "$table" && -n "$route" ]]; then
      "${aws_cmd[@]}" ec2 delete-route --route-table-id "$table" --destination-cidr-block 0.0.0.0/0
      state_put "public_route_${name}" ''
    fi
  done
  for name in public-a public-b app-a database-a firewall-a; do
    association="$(state_get "route_association_${name}")"
    if [[ -n "$association" ]]; then
      "${aws_cmd[@]}" ec2 disassociate-route-table --association-id "$association"
      state_put "route_association_${name}" ''
    fi
  done
  for name in public-a public-b app-a database-a firewall-a; do
    table="$(state_get "route_table_${name}")"
    if [[ -n "$table" ]]; then
      "${aws_cmd[@]}" ec2 delete-route-table --route-table-id "$table"
      state_put "route_table_${name}" ''
    fi
  done
  for name in public-a public-b app-a database-a firewall-a; do
    subnet="$(state_get "subnet_${name}")"
    if [[ -n "$subnet" ]]; then
      "${aws_cmd[@]}" ec2 delete-subnet --subnet-id "$subnet"
      state_put "subnet_${name}" ''
    fi
  done
  igw="$(state_get internet_gateway_id)"
  vpc="$(state_get vpc_id)"
  if [[ -n "$igw" ]]; then
    "${aws_cmd[@]}" ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"
    "${aws_cmd[@]}" ec2 delete-internet-gateway --internet-gateway-id "$igw"
    state_put internet_gateway_id ''
  fi
  if [[ -n "$vpc" ]]; then
    "${aws_cmd[@]}" ec2 delete-vpc --vpc-id "$vpc"
    state_put vpc_id ''
  fi

  printf 'All recorded seed-owned resources deleted, including the POC VPC.\n'
  printf 'Manifest retained: %s\n' "$state_file"
  exit 0
fi

[[ ! -e "$state_file" ]] \
  || die "Seed manifest exists: $state_file; run destroy before redeploy"

ami="$("${aws_cmd[@]}" ssm get-parameter \
  --name '/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id' \
  --query Parameter.Value --output text)"
[[ "$ami" == ami-* ]] || die "Invalid Ubuntu AMI: $ami"

seed_id="$(date -u +%Y%m%d%H%M%S)-$(openssl rand -hex 4)"
name_prefix="altseed-$(openssl rand -hex 4)"
seed_tags=("Key=MyOrgSeedId,Value=$seed_id" 'Key=ManagedBy,Value=myorg-aws-seed')
mkdir -p -- "$(dirname -- "$state_file")"
jq -n --arg region "$region" --arg account "$account_id" \
  --arg caller "$caller_arn" --arg seed "$seed_id" --arg prefix "$name_prefix" \
  '{schema_version:1,seed_id:$seed,account_id:$account,caller_arn:$caller,
    region:$region,name_prefix:$prefix,resources:{}}' > "$state_file"
printf 'Seed ID=%s; manifest=%s\n' "$seed_id" "$state_file"

# The CLI must reproduce the same network declarations as modules/vpc/vpc.tf
# and deployments/myorg/poc/use1/vpc/config/vpc.yml for direct import.
network_tag_spec() {
  jq -nc --arg type "$1" --arg name "$2" --arg role "${3:-}" \
    '{ResourceType:$type,Tags:(
      [{Key:"Project",Value:"myorg-aws-poc"},
       {Key:"Purpose",Value:"pci-dss-network-control"},
       {Key:"BusinessUnit",Value:"myorg"},
       {Key:"Environment",Value:"poc"},
       {Key:"Location",Value:"use1"},
       {Key:"Region",Value:"us-east-1"},
       {Key:"Stack",Value:"vpc"},
       {Key:"Module",Value:"vpc"},
       {Key:"ManagedBy",Value:"Terraform"},
       {Key:"Name",Value:$name}] +
       (if $role == "" then [] else [{Key:"SubnetRole",Value:$role}] end))}'
}

vpc="$("${aws_cmd[@]}" ec2 create-vpc --cidr-block 10.42.0.0/16 \
  --tag-specifications "$(network_tag_spec vpc myorg-poc-use1)" \
  --query Vpc.VpcId --output text)"
state_put vpc_id "$vpc"
"${aws_cmd[@]}" ec2 modify-vpc-attribute --vpc-id "$vpc" --enable-dns-hostnames '{"Value":true}'
"${aws_cmd[@]}" ec2 modify-vpc-attribute --vpc-id "$vpc" --enable-dns-support '{"Value":true}'

igw="$("${aws_cmd[@]}" ec2 create-internet-gateway \
  --tag-specifications "$(network_tag_spec internet-gateway myorg-poc-use1-igw)" \
  --query InternetGateway.InternetGatewayId --output text)"
state_put internet_gateway_id "$igw"
"${aws_cmd[@]}" ec2 attach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"

network_names=(public-a public-b app-a database-a firewall-a)
network_cidrs=(10.42.0.0/24 10.42.1.0/24 10.42.10.0/24 10.42.20.0/24 10.42.30.0/24)
network_azs=(us-east-1a us-east-1b us-east-1a us-east-1a us-east-1a)
network_roles=(public public application database firewall)
for i in "${!network_names[@]}"; do
  name="${network_names[$i]}"
  subnet="$("${aws_cmd[@]}" ec2 create-subnet --vpc-id "$vpc" \
    --cidr-block "${network_cidrs[$i]}" --availability-zone "${network_azs[$i]}" \
    --tag-specifications "$(network_tag_spec subnet "myorg-poc-use1-${name}" "${network_roles[$i]}")" \
    --query Subnet.SubnetId --output text)"
  state_put "subnet_${name}" "$subnet"
  table="$("${aws_cmd[@]}" ec2 create-route-table --vpc-id "$vpc" \
    --tag-specifications "$(network_tag_spec route-table "myorg-poc-use1-${name}" "${network_roles[$i]}")" \
    --query RouteTable.RouteTableId --output text)"
  state_put "route_table_${name}" "$table"
  association="$("${aws_cmd[@]}" ec2 associate-route-table --route-table-id "$table" \
    --subnet-id "$subnet" --query AssociationId --output text)"
  state_put "route_association_${name}" "$association"
  if [[ "${network_roles[$i]}" == public ]]; then
    "${aws_cmd[@]}" ec2 create-route --route-table-id "$table" \
      --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
    state_put "public_route_${name}" '0.0.0.0/0'
  fi
done
subnets=("$(state_get subnet_public-a)" "$(state_get subnet_public-b)")

create_sg() {
  local group
  group="$("${aws_cmd[@]}" ec2 create-security-group \
    --vpc-id "$vpc" --group-name "${name_prefix}-$1" \
    --description "Disposable MyOrg brownfield $1 initial SG" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=MyOrgSeedId,Value=$seed_id},{Key=ManagedBy,Value=myorg-aws-seed}]" \
    --query GroupId --output text)"
  state_put "security_group_$1" "$group"
  printf '%s\n' "$group"
}
sg_alb="$(create_sg alb)"
sg_app="$(create_sg app)"
sg_db="$(create_sg db)"

# Baseline vulnerability: unrestricted default egress, TCP/80 ingress from any
# IPv4 address on all three newly-created SGs. The default SG is untouched.
"${aws_cmd[@]}" ec2 authorize-security-group-ingress --group-id "$sg_alb" \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]},{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
"${aws_cmd[@]}" ec2 authorize-security-group-ingress --group-id "$sg_app" \
  --ip-permissions "$(jq -nc --arg sg "$sg_alb" '[
    {IpProtocol:"tcp",FromPort:80,ToPort:80,IpRanges:[{CidrIp:"0.0.0.0/0"}]},
    {IpProtocol:"tcp",FromPort:8080,ToPort:8080,UserIdGroupPairs:[{GroupId:$sg}]}
  ]')"
"${aws_cmd[@]}" ec2 authorize-security-group-ingress --group-id "$sg_db" \
  --ip-permissions "$(jq -nc --arg sg "$sg_app" '[
    {IpProtocol:"tcp",FromPort:80,ToPort:80,IpRanges:[{CidrIp:"0.0.0.0/0"}]},
    {IpProtocol:"tcp",FromPort:3306,ToPort:3306,UserIdGroupPairs:[{GroupId:$sg}]}
  ]')"

# Database is a standalone EC2 with actual MySQL, not an ASG member.
db="$("${aws_cmd[@]}" ec2 run-instances \
  --image-id "$ami" --instance-type "${SEED_DB_INSTANCE_TYPE:-t3.micro}" \
  --count 1 --subnet-id "${subnets[0]}" --security-group-ids "$sg_db" \
  --associate-public-ip-address \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --user-data "file://${repo_root}/scripts/seed/database-user-data.sh" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${name_prefix}-db},{Key=MyOrgSeedId,Value=$seed_id},{Key=ManagedBy,Value=myorg-aws-seed}]" \
    "ResourceType=volume,Tags=[{Key=MyOrgSeedId,Value=$seed_id},{Key=ManagedBy,Value=myorg-aws-seed}]" \
  --query 'Instances[0].InstanceId' --output text)"
state_put database_instance_id "$db"
state_put ami_id "$ami"
state_put database_instance_type "${SEED_DB_INSTANCE_TYPE:-t3.micro}"
state_put application_instance_type "${SEED_APP_INSTANCE_TYPE:-t3.micro}"
"${aws_cmd[@]}" ec2 wait instance-running --instance-ids "$db"
db_ip="$("${aws_cmd[@]}" ec2 describe-instances --instance-ids "$db" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
state_put database_private_ip "$db_ip"

if [[ -n "${SEED_CERT_ARN:-}" ]]; then
  cert="$SEED_CERT_ARN"
  state_put external_certificate_arn "$cert"
else
  cert_key="${state_file%.json}.key"
  cert_pem="${state_file%.json}.crt"
  openssl req -x509 -newkey rsa:3072 -sha256 -days 30 -nodes \
    -subj "/CN=${SEED_CERT_DOMAIN:-seed.invalid}" \
    -keyout "$cert_key" -out "$cert_pem" >/dev/null 2>&1
  chmod 0600 "$cert_key" "$cert_pem"
  state_put private_key_path "$cert_key"
  state_put certificate_path "$cert_pem"
  cert="$("${aws_cmd[@]}" acm import-certificate \
    --certificate "fileb://${cert_pem}" --private-key "fileb://${cert_key}" \
    --query CertificateArn --output text)"
  state_put owned_certificate_arn "$cert"
  "${aws_cmd[@]}" acm add-tags-to-certificate --certificate-arn "$cert" --tags "${seed_tags[@]}"
fi

tg="$("${aws_cmd[@]}" elbv2 create-target-group \
  --name "${name_prefix}-app" --protocol HTTP --port 8080 \
  --target-type instance --vpc-id "$vpc" --health-check-path / \
  --matcher HttpCode=200 --tags "${seed_tags[@]}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
state_put target_group_arn "$tg"

alb="$("${aws_cmd[@]}" elbv2 create-load-balancer \
  --name "${name_prefix}-alb" --type application --scheme internet-facing \
  --subnets "${subnets[@]}" --security-groups "$sg_alb" \
  --tags "${seed_tags[@]}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
state_put alb_arn "$alb"
"${aws_cmd[@]}" elbv2 wait load-balancer-available --load-balancer-arns "$alb"

listener="$("${aws_cmd[@]}" elbv2 create-listener \
  --load-balancer-arn "$alb" --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$tg" --tags "${seed_tags[@]}" \
  --query 'Listeners[0].ListenerArn' --output text)"
state_put listener_http_arn "$listener"

listener="$("${aws_cmd[@]}" elbv2 create-listener \
  --load-balancer-arn "$alb" --protocol HTTPS --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --certificates "CertificateArn=$cert" \
  --default-actions "Type=forward,TargetGroupArn=$tg" --tags "${seed_tags[@]}" \
  --query 'Listeners[0].ListenerArn' --output text)"
state_put listener_https_arn "$listener"

work_dir="$(mktemp -d)"
trap 'rm -r -- "$work_dir"' EXIT
userdata="${work_dir}/application-user-data.sh"
printf '#!/usr/bin/env bash\nSEED_DB_HOST=%q\nSEED_RUNTIME_URL=%q\nSEED_BOOTSTRAP_URL=%q\n' \
  "$db_ip" 'https://secureweb.com' "${SEED_BOOTSTRAP_URL:-}" > "$userdata"
sed '1d' "${repo_root}/scripts/seed/application-user-data.sh" >> "$userdata"
userdata_b64="$(base64 < "$userdata" | tr -d '\n')"
state_put application_user_data_base64 "$userdata_b64"

jq -n --arg ami "$ami" --arg type "${SEED_APP_INSTANCE_TYPE:-t3.micro}" \
  --arg sg "$sg_app" --arg userdata "$userdata_b64" \
  --arg seed "$seed_id" --arg prefix "$name_prefix" \
  '{ImageId:$ami,InstanceType:$type,UserData:$userdata,
    MetadataOptions:{HttpEndpoint:"enabled",HttpTokens:"required"},
    NetworkInterfaces:[{DeviceIndex:0,AssociatePublicIpAddress:true,Groups:[$sg],DeleteOnTermination:true}],
    TagSpecifications:[
      {ResourceType:"instance",Tags:[{Key:"Name",Value:($prefix+"-app")},{Key:"MyOrgSeedId",Value:$seed},{Key:"ManagedBy",Value:"myorg-aws-seed"}]},
      {ResourceType:"volume",Tags:[{Key:"MyOrgSeedId",Value:$seed},{Key:"ManagedBy",Value:"myorg-aws-seed"}]}
    ]}' > "${work_dir}/launch-template.json"

template="$("${aws_cmd[@]}" ec2 create-launch-template \
  --launch-template-name "${name_prefix}-app" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=MyOrgSeedId,Value=$seed_id},{Key=ManagedBy,Value=myorg-aws-seed}]" \
  --launch-template-data "file://${work_dir}/launch-template.json" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)"
state_put launch_template_id "$template"

asg="${name_prefix}-app"
"${aws_cmd[@]}" autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$asg" --min-size 1 --max-size 1 --desired-capacity 1 \
  --health-check-type ELB --health-check-grace-period 300 \
  --vpc-zone-identifier "$(IFS=,; printf '%s' "${subnets[*]}")" \
  --launch-template "LaunchTemplateId=$template,Version=1" \
  --target-group-arns "$tg" \
  --tags "Key=MyOrgSeedId,Value=$seed_id,PropagateAtLaunch=true" \
         'Key=ManagedBy,Value=myorg-aws-seed,PropagateAtLaunch=true'
state_put asg_name "$asg"

dns="$("${aws_cmd[@]}" elbv2 describe-load-balancers --load-balancer-arns "$alb" \
  --query 'LoadBalancers[0].DNSName' --output text)"
printf '\nSeed deployed (AWS provisioning may still be completing):\n'
printf '  manifest:     %s\n' "$state_file"
printf '  POC VPC:     %s (seed-owned, 10.42.0.0/16)\n' "$vpc"
printf '  5 subnets:   public-a public-b app-a database-a firewall-a\n'
printf '  MySQL EC2:   %s (%s)\n' "$db" "$db_ip"
printf '  app ASG:     %s (desired=1)\n' "$asg"
printf '  ALB:         http://%s/ and https://%s/\n' "$dns" "$dns"
printf '  ACM cert:    %s\n' "$cert"
printf '  app paths:   /, /db, /dependency\n'
printf '  teardown:    AWS_PROFILE=%q SEED_REGION=%q %q destroy\n' "$AWS_PROFILE" "$region" "$0"
printf 'Browser TLS warning is expected for the self-signed test certificate.\n'
