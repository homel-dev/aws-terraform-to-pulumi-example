# Brownfield seed, Terraform import, and migration

> **Superseded.** The authoritative, current procedure is [POC seed and direct Terraform adoption](02_poc_adoption.md). The instructions below are retained only for historical reference; do not execute them.

This procedure describes the **main-branch initial-state adoption**. AWS CLI
creates a deliberately vulnerable, manually managed environment in a **new POC
VPC**. The VPC root contains working import declarations, but the checked-in
`poc/use1/ec2` root models the *target* infrastructure. The separate
`brownfield/use1/compute` root imports the seed topology, but **its state
is not the POC EC2 state**. The POC EC2 root now has manifest-driven import
declarations for adopting the existing Compute resources while upgrading them.
Importing the VPC does not import Compute. Full audit hardening
and the EC2 MySQL → RDS migration belong to
`audit-hardening`; Pulumi and ECS/Fargate belong to `modernized-pulumi`.

**This repository is not proof of an AWS deployment or a completed Compute
import.** The operator must execute
the following commands against an isolated AWS account and review each plan.

## 1. Prerequisites

AWS CLI v2, Bash, `jq`, `openssl`, Terraform **1.16.5**, and permissions
for VPC/EC2, ELBv2, Auto Scaling, ACM, SSM and S3. Region is `us-east-1`
(other regions are explicitly refused). AWS will charge for EC2, EBS,
public IPv4, ALB and later NAT/Network Firewall. Use **no real customer data**.

Run the next commands **from the repository root**:

```bash
export AWS_PROFILE=myorg-sandbox
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
| ALB, app and database SGs | 3 | Brownfield Compute → `poc/use1/ec2` migration |
| Ubuntu EC2 running MySQL (`myorg_seed` database) | 1 | Brownfield Compute → `poc/use1/ec2` migration |
| Application EC2, launched by Launch Template + ASG | 1 | Transfer ASG and Launch Template; never import the ASG member as an EC2 instance |
| Internet-facing ALB, target group, HTTPS listener | 1 + 1 + 1 | Brownfield Compute → `poc/use1/ec2` migration |
| Legacy HTTP listener | 1 | Must be decommissioned explicitly; no corresponding target POC resource |
| Seed-owned ACM certificate | 1 | Remains in brownfield Compute state until an explicit ACM ownership transfer/decommission |

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
gitignored, and **must be safeguarded**; Terraform remote state will also
contain sensitive ACM key material. Browser TLS warnings are expected.

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
restrictions matter because a self-signed ACM private key enters state.

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

## 6. Move imported Compute into the POC EC2 root and upgrade

The source root **exists** at `deployments/myorg/brownfield/use1/compute`.
Its backend key is `myorg/brownfield/use1/compute/terraform.tfstate`.
The target root is `deployments/myorg/poc/use1/ec2`, with a **different**
backend key, `myorg/poc/use1/ec2/terraform.tfstate`. Both roots refer to
the same seeded AWS account; importing into one does not populate the other.

The source contains 10 unconditional imports and one optional ACM import.
The target `ec2/imports.tf` deliberately maps **nine** seed-owned resources
to the keyed addresses in `module.ec2`. It does not import the ASG member as
a standalone instance. It also does not invent Terraform ownership for the
seed-only HTTP listener or certificate.

**This is an import plus architecture change.** Unlike the initial VPC import,
the first POC EC2 plan can contain imports, new resources, in-place changes
and **replacements**, notably database EC2 (public → private subnet), ALB
(seed name differs from POC name), and Launch Template. Database replacement
can destroy its local data, and ALB/ASG modifications can cause downtime.
Do not approve that plan until the seed MySQL data has been backed up,
service cutover has been evaluated and the exact replacement actions are
acceptable. No Terraform state rewrite can make incompatible AWS settings
match without an AWS change.

Run commands below from the repository root. They are an **operator procedure**;
the patch does not modify AWS or remote states.

```bash
export BROWNFIELD_COMPUTE_ROOT=deployments/myorg/brownfield/use1/compute
export EC2_ROOT=deployments/myorg/poc/use1/ec2
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$EC2_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"

# Verify source ownership; these should be populated if the prior import ran.
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" state list
terraform -chdir="$EC2_ROOT" state list

# Save the precise pre-migration remote states in an operator-controlled,
# private directory before state address changes.
install -d -m 0700 brownfield-evidence/states
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" state pull > brownfield-evidence/states/compute-before.tfstate
terraform -chdir="$EC2_ROOT" state pull > brownfield-evidence/states/ec2-before.tfstate
chmod 0600 brownfield-evidence/states/*.tfstate
```

The HTTP/80 listener is not part of the target EC2 module. Before transferring
ALB ownership, **separately review its deletion** from the source root. This
prevents an unmanaged HTTP entry point and allows the old ALB to be replaced
if the approved plan requires it:

```bash
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" plan -destroy \
  -target=aws_lb_listener.http \
  -var="seed_manifest_path=$TF_SEED_MANIFEST" \
  -out=retire-http.tfplan
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" show retire-http.tfplan
# Proceed only after explicit review: this deletes the seeded HTTP listener.
terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" apply retire-http.tfplan
```

Next, remove **only** the nine addresses in the table from the *old Terraform
state*. `terraform state rm` forgets objects but does not delete them in AWS.
After removal, the target `import` blocks can assume ownership. The source
root must not be planned/applied again as a workload root: its old HCL would
otherwise propose recreating the forgotten resources.

| Brownfield source address | POC target address |
| --- | --- |
| `aws_security_group.alb` | `module.ec2.aws_security_group.alb["compute"]` |
| `aws_security_group.application` | `module.ec2.aws_security_group.application["compute"]` |
| `aws_security_group.database` | `module.ec2.aws_security_group.database["compute"]` |
| `aws_instance.database` | `module.ec2.aws_instance.database["compute"]` |
| `aws_launch_template.application` | `module.ec2.aws_launch_template.application["compute"]` |
| `aws_autoscaling_group.application` | `module.ec2.aws_autoscaling_group.application["compute"]` |
| `aws_lb.this` | `module.ec2.aws_lb.this["compute"]` |
| `aws_lb_target_group.application` | `module.ec2.aws_lb_target_group.application["compute"]` |
| `aws_lb_listener.https` | `module.ec2.aws_lb_listener.https["compute"]` |

```bash
# Each line below alters only the OLD Terraform state; no AWS deletion.
for address in \
  aws_security_group.alb \
  aws_security_group.application \
  aws_security_group.database \
  aws_instance.database \
  aws_launch_template.application \
  aws_autoscaling_group.application \
  aws_lb.this \
  aws_lb_target_group.application \
  aws_lb_listener.https; do
  terraform -chdir="$BROWNFIELD_COMPUTE_ROOT" state rm "$address"
done

terraform -chdir="$EC2_ROOT" plan \
  -var="seed_manifest_path=$TF_SEED_MANIFEST" -out=adopt-and-upgrade-ec2.tfplan
terraform -chdir="$EC2_ROOT" show adopt-and-upgrade-ec2.tfplan
# Review every import AND every create/update/replace/destroy.
# Apply the saved plan only if its exact effects are authorized.
terraform -chdir="$EC2_ROOT" apply adopt-and-upgrade-ec2.tfplan
terraform -chdir="$EC2_ROOT" state list
terraform -chdir="$EC2_ROOT" plan
```

The source state retains the seed ACM certificate if it was seed-owned. Its
private key must remain safeguarded; certificate retirement or transfer into
the ACM root is a **separate ownership decision**. The POC ACM root currently
accepts an external ARN as a config input; that is not an import of certificate
ownership. Until the remaining old root resources are explicitly resolved,
do not destroy or apply the brownfield Compute root as a whole.

The first POC EC2 plan may now reach the AMI and ACM data sources. To avoid
missing custom SSM parameters before Packer builds, `compute.yml` uses the
same public Canonical Ubuntu 24.04 AMI parameter as the seed. The ACM reader
accepts both the legacy `certificate_arn` and the keyed
`certificate_arns` outputs.

## 7. Stage 0 minimum firewall, followed by the other branches

In `main`, after adoption, approve a *separate* hardening plan: deploy the
existing `deployments/myorg/poc/use1/firewall` Network Firewall/NAT, SNI
allowlist and route controls, validate symmetric routing and tighten the
imported application/database SG ingress and outbound rules according to the
traffic register. The firewall is **new Terraform remediation**, so it was
not imported from the deliberately vulnerable manual seed.

The existing POC `ec2` root describes the **target private application
architecture**, not the initial imported public-subnet ASG/DB. Do **not**
apply the full-location workflow/POC `ec2` root against this brownfield as
if cutover had occurred. DB migration, traffic cutover, health gates, rollback
and eventual brownfield decommission require separate, reviewed plans:

1. `main`: manual seed → Terraform VPC + compute imports → minimum PCI firewall.
2. `audit-hardening`: additional CloudTrail/Config/GuardDuty/KMS/WAF/backup
   controls and explicit **MySQL EC2 → RDS** migration.
3. `modernized-pulumi`: **Pulumi TypeScript + ECS/Fargate** for the app;
   database remains RDS.

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
