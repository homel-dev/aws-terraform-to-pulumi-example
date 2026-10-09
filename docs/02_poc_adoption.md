# POC seed and direct Terraform adoption

This procedure describes the AWS CLI seed and Terraform adoption directly into
the final `poc/use1` deployment roots. The VPC and its network resources import
into `deployments/myorg/poc/use1/vpc`. Compute imports into
`deployments/myorg/poc/use1/ec2`: database EC2, application Launch Template
and ASG, three Security Groups, ALB, target group and both HTTP/HTTPS listeners.
The same EC2 plan may also contain the desired POC configuration changes.
There is **no separate `deployments/myorg/brownfield/use1/compute` root in this
checkout**; earlier versions may nevertheless have left a separate remote state
that still owns Compute objects (see section 6).

**Before any EC2 replacement:** the checked-in public Ubuntu AMI parameters are a seed-adoption fallback, not complete POC images. A fresh private database EC2 requires MySQL, `jq` and AWS CLI; the app image requires the `myorg-poc-app` systemd service. Build the Packer images and switch both `ami_ssm_parameter` settings to their published SSM parameters before launching replacements. The isolated database subnet has no package-download Internet route.
The ACM certificate is referenced separately through the `acm` stack.

A Terraform configuration and its import declarations do **not** establish that
AWS resources have been imported or that an upgrade has succeeded. Review the
actual plan before applying changes. The EC2 MySQL → RDS migration belongs to
`audit-hardening`; ECS/Fargate and Pulumi belong to `modernized-pulumi`.

## 1. Prerequisites

AWS CLI v2, Bash, `jq`, `openssl`, Terraform **1.16.5**, and permissions
for VPC/EC2, ELBv2, Auto Scaling, ACM, SSM and S3. Region is `us-east-1`
(other regions are explicitly refused). AWS will charge for EC2, EBS,
public IPv4, ALB and later NAT/Network Firewall. Use **no real customer data**.

Run the next commands **from the repository root**:

```bash
export AWS_PROFILE=default  # or your configured AWS CLI profile
export AWS_REGION=us-east-1
export SEED_REGION=us-east-1
export SEED_STATE_FILE="$PWD/.terraform/seed/brownfield-use1.json"
export TF_SEED_MANIFEST="$SEED_STATE_FILE"
aws sso login --profile "$AWS_PROFILE"  # only if using IAM Identity Center
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

The CLI script creates a new custom VPC with CIDR `10.42.0.0/16`; it never
needs, modifies or deletes the account's default VPC. Its state manifest
contains AWS account/region/IDs and is checked before any teardown.

## 2. Deploy the manually managed baseline

```bash
./scripts/aws-brownfield-seed.sh deploy
```

| Manually seeded resource | Count | Terraform import target |
| --- | ---: | --- |
| Custom POC VPC and Internet Gateway | 1 + 1 | `deployments/myorg/poc/use1/vpc` |
| Subnets `public-a`, `public-b`, `app-a`, `database-a`, `firewall-a` | 5 | VPC root |
| Route tables, associations and public default routes | 5 + 5 + 2 | VPC root |
| ALB, app and database SGs | 3 | `deployments/myorg/poc/use1/ec2` |
| Ubuntu EC2 running MySQL (`myorg_seed` database) | 1 | `module.ec2.aws_instance.database["compute"]` |
| Application EC2, launched by Launch Template + ASG | 1 | EC2 root: import ASG and Launch Template, not the ASG member |
| Internet-facing ALB, target group, HTTP and HTTPS listeners | 1 + 1 + 2 | EC2 root, including `module.ec2.aws_lb_listener.http["compute"]` |
| Seed-owned self-signed ACM certificate | 1 | Not a Compute import; supply the ARN through `acm/config/certificate.yml` |

The three SGs intentionally have public TCP/80 ingress and unrestricted
default egress. ALB also allows TCP/443; app allows TCP/8080 from ALB SG;
MySQL SG allows TCP/3306 from app SG. The database and app are in a seed-owned
public subnet for installation; the private subnets are created for eventual
migration. This is **not yet PCI compliant**.

The synthetic app serves `/`, probes the DB port at `/db` and checks HTTPS
reachability at `/dependency`. The original exercise did not supply the
application artifact or live credentials, so do not mistake the synthetic
fixture for a byte-identical production application.

Options: `SEED_APP_INSTANCE_TYPE` and `SEED_DB_INSTANCE_TYPE` default to
`t3.micro`; `SEED_BOOTSTRAP_URL` downloads an HTTPS artifact but never
executes it. `SEED_CERT_ARN` reuses an **external, non-seed-owned** ACM
certificate. Otherwise a self-signed test cert, PEM and 0600 private key are
generated. The key and JSON manifest live under `.terraform/seed/`, are
gitignored, and **must be safeguarded**. The `acm` module's `imported` mode
references only the certificate ARN; it does not store that private key in
Terraform state. Browser TLS warnings are expected.

```bash
aws elbv2 describe-target-health --profile "$AWS_PROFILE" --region us-east-1 \
  --target-group-arn "$(jq -r '.resources.target_group_arn' "$SEED_STATE_FILE")"
aws autoscaling describe-auto-scaling-groups --profile "$AWS_PROFILE" --region us-east-1 \
  --auto-scaling-group-names "$(jq -r '.resources.asg_name' "$SEED_STATE_FILE")"
```

AWS API completion does not guarantee that cloud-init and ALB health checks
are ready. Check them before continuing.

## 3. Capture discovery and backup evidence

```bash
mkdir -p brownfield-evidence
chmod 700 brownfield-evidence
cp "$SEED_STATE_FILE" brownfield-evidence/seed-manifest.json
chmod 600 brownfield-evidence/seed-manifest.json
mapfile -t sg_ids < <(jq -r '.resources | .security_group_alb,.security_group_app,.security_group_db' "$SEED_STATE_FILE")
aws ec2 describe-security-groups --profile "$AWS_PROFILE" --region us-east-1 \
  --group-ids "${sg_ids[@]}" > brownfield-evidence/security-groups.json
aws ec2 describe-instances --profile "$AWS_PROFILE" --region us-east-1 \
  --instance-ids "$(jq -r '.resources.database_instance_id' "$SEED_STATE_FILE")" \
  > brownfield-evidence/database-instance.json
```

Also capture `elbv2 describe-*`, ASG state, launch template version, AMIs,
volumes and DB backup. Protect these local evidence files (do not commit).
The ASG already owns its application instance; separately importing that EC2,
its attached EBS volume or ENI would create competing lifecycle owners.
Default SG, main VPC route table and default network ACL were AWS-generated
implicitly, not manually seeded resources.

## 4. Initialize the encrypted remote-state backend

If the per-account project bucket already exists, verify its ownership and
skip bootstrap. Otherwise the existing Terraform state root creates it:

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
export TF_STATE_BUCKET="myorg-aws-terraform-state-${AWS_ACCOUNT_ID}"
export STATE_ROOT=deployments/myorg/poc/use1/terraform-state
terraform -chdir="$STATE_ROOT" init -backend=false
terraform -chdir="$STATE_ROOT" plan -out=bootstrap.tfplan
terraform -chdir="$STATE_ROOT" show bootstrap.tfplan
# Review the bucket and protections, then explicitly authorize:
terraform -chdir="$STATE_ROOT" apply bootstrap.tfplan
terraform -chdir="$STATE_ROOT" init -migrate-state \
  -backend-config="bucket=$TF_STATE_BUCKET"
```

Confirm the backend migration prompt and avoid accidentally managing the
same bucket from two independent states. Backend encryption and access
restrictions still matter because Terraform state and saved plans may contain
other sensitive infrastructure data; the imported ACM ARN is not its key.

## 5. Import the custom VPC and all seeded routes

The seed network intentionally matches the existing `modules/vpc`
declarations, names, CIDRs and tags. All **19** import blocks are in
`deployments/myorg/poc/use1/vpc/imports.tf`. They activate only when a seed
manifest path is supplied, so ordinary CI VPC plans still work.

```bash
export VPC_ROOT=deployments/myorg/poc/use1/vpc
terraform -chdir="$VPC_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$VPC_ROOT" fmt -check
terraform -chdir="$VPC_ROOT" validate
terraform -chdir="$VPC_ROOT" plan -var="seed_manifest_path=$TF_SEED_MANIFEST" \
  -out=import-vpc.tfplan
terraform -chdir="$VPC_ROOT" show import-vpc.tfplan
# Apply ONLY if all intended actions are imports, with no replacements/destroys.
terraform -chdir="$VPC_ROOT" apply import-vpc.tfplan
terraform -chdir="$VPC_ROOT" plan
```

The last plan should be empty except for understood drift. If it proposes
replacing a route, subnet or VPC, stop and reconcile AWS observations/HCL.

## 6. Import Compute into `poc/use1/ec2`

**Run from the repository root.** The EC2 root uses remote state key
`myorg/poc/use1/ec2/terraform.tfstate`. Its `imports.tf` contains nine
manifest-driven import blocks; `imports_http.tf` contains the tenth, for the
existing HTTP/80 listener. All blocks use the existing seed manifest and
Terraform addresses under `module.ec2`.

**Before planning EC2, deploy its upstream states.** The EC2 module reads the
VPC, IAM, logging, and ACM remote states even when the ALB config contains an
explicit certificate ARN. The VPC state was prepared in section 5. Set the
real seed certificate ARN in both `acm/config/certificate.yml` and
`ec2/config/compute.yml` (under `alb.certificate_arn`); the checked-in ARN is
account-specific. In the current ACM `imported` mode, a Route 53 state is not
needed for ACM, but the separate `full` workflow still deploys Route 53.

Prepare IAM, logging, and ACM individually. For each stack, initialize its
S3 backend, save and inspect its plan, and apply **only its reviewed plan**:

```bash
export IAM_ROOT=deployments/myorg/poc/use1/iam
terraform -chdir="$IAM_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$IAM_ROOT" plan -out=iam.tfplan
terraform -chdir="$IAM_ROOT" show iam.tfplan
# After review and approval:
terraform -chdir="$IAM_ROOT" apply iam.tfplan

export LOGGING_ROOT=deployments/myorg/poc/use1/logging
terraform -chdir="$LOGGING_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$LOGGING_ROOT" plan -out=logging.tfplan
terraform -chdir="$LOGGING_ROOT" show logging.tfplan
# After review and approval:
terraform -chdir="$LOGGING_ROOT" apply logging.tfplan

export ACM_ROOT=deployments/myorg/poc/use1/acm
terraform -chdir="$ACM_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$ACM_ROOT" plan -out=acm.tfplan
terraform -chdir="$ACM_ROOT" show acm.tfplan
# After review and approval:
terraform -chdir="$ACM_ROOT" apply acm.tfplan
```

The checked-in public Ubuntu AMI parameters are suitable only for seed
adoption, **not** for launching replacement POC instances. Before approving
an EC2 plan that replaces the application or database, build both Packer AMIs
using `task image:build IMAGE=application` and
`task image:build IMAGE=database` (requires Task and Packer), then change
the two `ami_ssm_parameter` values in `ec2/config/compute.yml` to
`/myorg/poc/use1/ami/application` and `/myorg/poc/use1/ami/database`.
Review database backup/recovery before any instance replacement.

The minimal `main` network control also requires the independent firewall
stack. It is a **new** Network Firewall/NAT deployment, not a seed import.
Prepare it before the EC2 upgrade so the target application's private-subnet
egress route is in place:

```bash
export FIREWALL_ROOT=deployments/myorg/poc/use1/firewall
terraform -chdir="$FIREWALL_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$FIREWALL_ROOT" plan -out=firewall.tfplan
terraform -chdir="$FIREWALL_ROOT" show firewall.tfplan
# After review and approval of the routing and firewall changes:
terraform -chdir="$FIREWALL_ROOT" apply firewall.tfplan
```

**If an earlier brownfield Compute state already owns these AWS objects:**
before importing into the POC EC2 state, use the original state/root to back
up `terraform state pull` output, inspect `terraform state list`, and remove
with `terraform state rm` only those among the ten seeded Compute resources
that the old state actually owns.
The older root is not included in this checkout, so its addresses must be
verified from that state rather than guessed here. `state rm` only removes
Terraform ownership; it must not destroy AWS resources. Do not run the old
root's plan/apply afterward or let two states manage the same objects.

The seeded application EC2 is managed by its ASG and is **not** imported as
`aws_instance`. The ALB HTTPS listener and HTTP listener are separate imports.
The seed-owned ACM certificate is **not** imported by this EC2 root. The
`acm` stack must reference a real certificate ARN instead of its example value
before planning EC2; this does not itself transfer certificate ownership.

```bash
export EC2_ROOT=deployments/myorg/poc/use1/ec2
terraform -chdir="$EC2_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$EC2_ROOT" fmt -check
terraform -chdir="$EC2_ROOT" validate
terraform -chdir="$EC2_ROOT" plan -var="seed_manifest_path=$TF_SEED_MANIFEST" \
  -out=import-ec2.tfplan
terraform -chdir="$EC2_ROOT" show import-ec2.tfplan
# Review every import, create, update and replacement before authorizing:
terraform -chdir="$EC2_ROOT" apply import-ec2.tfplan
terraform -chdir="$EC2_ROOT" plan -var="seed_manifest_path=$TF_SEED_MANIFEST"
```

The import plan may propose changes or resource replacements because the
original seed (public application/database instances and original ALB names)
differs from the desired POC. In particular, changing the database EC2
subnet may force replacement and loss of its local MySQL data. Review those
actions and data impact before applying the saved plan.

An earlier brownfield state is not an input to these import blocks: the final
resource addresses and AWS IDs come from this root and `TF_SEED_MANIFEST`.
Complete the conditional state-ownership transfer above before this import;
do not leave both states managing the same AWS objects.

## 7. Complete the `main` POC and distinguish the later branches

The `main` EC2 import plan may include SG hardening and application/database
changes. Together with the independently applied Network Firewall/NAT, SNI
allowlist, and route controls, **the result of the reviewed adoption/upgrade
is the minimum viable POC for PCI-DSS 1.3.1/1.3.2**. The imported seed by
itself is not that result. Review network path changes and affected traffic.

The POC `ec2` root describes the target architecture **and** imports the
initial seeded objects. Its plan can therefore contain replacements. Database
migration, traffic cutover, rollback and eventual decommission are not proven
by an import declaration:

1. `main`: manual seed → VPC import → required POC states and firewall →
   EC2 import plus reviewed minimum PCI network remediation in the final roots.
2. `audit-hardening`: Multi-AZ RDS MySQL with encryption and backups, WAF and
   GuardDuty, followed by an explicit reviewed **MySQL EC2 → RDS** data
   migration ([runbook](03_audit_hardening.md)). AWS Config and Security Hub
   are not enabled in this branch.
3. `modernized-pulumi`: **Pulumi TypeScript + ECS/Fargate**, as a separate
   target platform. It does not automatically import Terraform state, migrate
   application data, or replace the running Terraform deployment
   ([runbook](04_modernized_pulumi.md)).

## 8. Destroy the seed **before import only**

```bash
./scripts/aws-brownfield-seed.sh destroy
```

The script deletes the ASG and its app EC2, MySQL EC2, both ALB listeners,
ALB, target group, Launch Template, seed-owned ACM certificate and local
PEM/key, three SGs, two public routes, five route-table associations and
tables, five subnets, IGW and the **custom POC VPC**. It refuses to delete
anything if account/region differs from its manifest; external ACM certs are
never deleted. The manifest remains for evidence, with successfully deleted
resource IDs cleared. Rerun after addressing any partial-teardown failure.
**After Terraform adoption, decommission via Terraform state instead.**
