# Brownfield seed, Terraform import, and migration

This procedure describes the **main-branch initial-state adoption**. AWS CLI
creates a deliberately vulnerable, manually managed environment in a **new POC
VPC**, and Terraform imports **every seed-owned resource**. Import preserves
the initial rules; minimal PCI 1.3.1/1.3.2 remediation is a subsequent change
in `main`. Full audit hardening and the EC2 MySQL → RDS migration belong to
`audit-hardening`; Pulumi and ECS/Fargate belong to `modernized-pulumi`.

**This repository contains working implementation and import declarations,
not proof of an AWS deployment or completed import.** The operator must execute
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
| ALB, app and database SGs | 3 | `deployments/myorg/brownfield/use1/compute` |
| Ubuntu EC2 running MySQL (`myorg_seed` database) | 1 | Compute root `aws_instance.database` |
| Application EC2, launched by Launch Template + ASG | 1 | Compute root **ASG and Launch Template** |
| Internet-facing ALB, target group, HTTP and HTTPS listeners | 1 + 1 + 2 | Compute root |
| Seed-imported, self-signed ACM certificate | 1 | Compute root unless an external certificate is supplied |

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

## 6. Import the two EC2 workloads and ALB/SG/ACM objects

This root uses **a separate remote state** from VPC and imports the database
EC2, ASG application ownership, Launch Template, three SGs, ALB, target
group and both listeners: **10 resources**, plus the seed-owned ACM
certificate when present (**11**). The application EC2 is controlled by the
ASG; there is deliberately no `aws_instance.application` import.

```bash
export COMPUTE_ROOT=deployments/myorg/brownfield/use1/compute
terraform -chdir="$COMPUTE_ROOT" init -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir="$COMPUTE_ROOT" fmt -check
terraform -chdir="$COMPUTE_ROOT" validate
terraform -chdir="$COMPUTE_ROOT" plan \
  -var="seed_manifest_path=$TF_SEED_MANIFEST" -out=import-compute.tfplan
terraform -chdir="$COMPUTE_ROOT" show import-compute.tfplan
# Approve ONLY imports, never an unreviewed resource change or replacement.
terraform -chdir="$COMPUTE_ROOT" apply import-compute.tfplan
terraform -chdir="$COMPUTE_ROOT" plan -var="seed_manifest_path=$TF_SEED_MANIFEST"
```

Imports change Terraform **ownership**, not resource architecture. If any
post-import plan shows updates, study the live AWS settings and correct the
configuration before applying. Do not use `-replace`, `-target` or blanket
`ignore_changes` to hide drift. Back up the remote-state version.
Once imported, **never run the AWS CLI seed destroy** against those objects.

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
