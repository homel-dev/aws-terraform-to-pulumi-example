# AWS Terraform to Pulumi Example

This example uses a fictional organization called MyOrg. The three branches demonstrate infrastructure adoption, hardening, and modernization; they are not evidence of a deployed environment.

Terraform proof of concept for the MyOrg PCI-DSS network-control scenario.

The repository follows the organization-wide policy in `homel-dev/.github`. The canonical project contract is [`docs/01_architecture.md`](docs/01_architecture.md).

## Repository model

Reusable implementation lives in `modules/`. Deployment roots are identified by:

`business-unit / environment / location / stack`

For the POC, `use1` maps to AWS `us-east-1`:

```text
deployments/myorg/poc/use1/
├── terraform-state/
├── vpc/
├── iam/
├── logging/
├── route53/
├── acm/
├── firewall/
├── ec2/
└── dlm/
```

Every stack owns:

- its own Terraform root;
- its own `config/` tree;
- its own Terraform state object.

Reusable modules read YAML from `${path.root}/config`, following the development-module pattern used as the basis for this repository. Schema errors are raised from Terraform through the `tlkamp/validation` provider; Route53 keeps the same zone-directory configuration model as the supplied development module.

State keys are independent:

```text
myorg/poc/use1/terraform-state/terraform.tfstate
myorg/poc/use1/vpc/terraform.tfstate
myorg/poc/use1/firewall/terraform.tfstate
myorg/poc/use1/ec2/terraform.tfstate
```

The `terraform-state` stack bootstraps the S3 bucket locally on first creation and immediately migrates its own state into its dedicated S3 key.

## Stack ordering versus Terraform dependencies

The first-deployment DAG is declared in `.github/workflows/myorg-poc-use1.yml` through GitHub Actions `needs` edges. It orders jobs without causing one Terraform root to plan or apply another root.

Cross-stack data is read explicitly with `terraform_remote_state`. For example, the firewall stack reads VPC outputs. If the VPC state already exists and has no changes, applying firewall does not apply or recreate the VPC. If the VPC state does not exist yet, the firewall plan fails because its required inputs are unavailable.

Inside one Terraform stack, normal HCL references and occasional resource-level `depends_on` are real Terraform graph edges. They control ordering inside that state only; they do not automatically recreate a dependency.

## Main-branch scope

`main` includes the **manual brownfield starting point, Terraform adoption,
and minimum PCI 1.3.1/1.3.2 network controls**. The initial infrastructure
is created by `scripts/aws-brownfield-seed.sh deploy` in a **new custom POC
VPC**, not in an account's default VPC. Native Terraform import blocks cover
its VPC, 5 subnets, routes, three security groups, both EC2 workloads (the
application through its ASG), ALB/listeners and the seed-owned ACM cert.
See [the executable adoption procedure](docs/02_brownfield_adoption.md) for
exact commands, preserved vulnerabilities, state bootstrapping, plan-review
gates and pre-import-only `destroy`.

The existing POC modules also describe the **intended network-controlled
target layout**. Importing the baseline is not permission to apply the full
target EC2 root immediately: application/database cutover is a separate
reviewed migration. The target layout includes:

- dedicated VPC and subnet roles;
- public HTTPS ALB with finite source allowlist;
- single application instance through ASG `1/1/1`;
- MySQL on EC2, intentionally retained for the scenario baseline;
- Network Firewall + NAT for controlled application egress;
- SSM interface endpoints for private administration;
- Route53 and ACM support;
- VPC Flow Logs, CloudTrail, ALB access logs, and firewall logs;
- DLM snapshots for the database volume;
- one S3 state object per stack;
- GitHub Actions with OIDC and pinned third-party actions;
- Packer pipelines for application and database base AMIs.

The application artifact from `example.com` remains a boot-time dependency in `main`. It is not mirrored or baked into the application AMI until its ownership, persistence, and customer-IP contract is known. See [`docs/03_boot_artifact_boundary.md`](docs/03_boot_artifact_boundary.md).

## First deployment order

The Packer builders use the POC VPC public subnet, so first deployment is intentionally staged:

```text
1. terraform-state
2. vpc
3. build application + database AMIs and publish their IDs to SSM
4. iam
5. logging
6. route53
7. acm
8. firewall
9. ec2
10. dlm
```

The stack order is visible in [the location workflow](.github/workflows/myorg-poc-use1.yml). The image workflow is separate: application and database AMIs must already have been built and published to SSM before `ec2` is deployed.

The order exists because downstream stacks consume outputs from already-created remote states. It is not lifecycle coupling between their states.

## GitHub Actions

GitHub Actions workflows declare their own orchestration. [`_terraform-stack.yml`](.github/workflows/_terraform-stack.yml) is the reusable implementation for one Terraform root: format/init/validate, plan to an artifact, protected-environment approval, then apply of the exact saved plan.

Required GitHub variables:

- `AWS_ROLE_ARN` — OIDC role for Terraform plan/apply;
- `AWS_IMAGE_ROLE_ARN` — OIDC role for Packer builds.
- `TF_STATE_BUCKET` — existing or to-be-created S3 state bucket, named `myorg-aws-terraform-state-<AWS-account-id>`.

`apply` uses the protected GitHub Environment `myorg-poc-use1`.

Pull requests format-check and validate every Terraform root without AWS credentials, then plan changed roots and downstream consumers against deployed remote-state outputs using OIDC. The manual `plan` and `apply` modes operate on one selected root; `full` deploys the location DAG. Each apply waits for the `myorg-poc-use1` protected GitHub Environment and consumes the plan artifact produced earlier in the same workflow run. Saved Terraform plans can contain sensitive data; artifact retention is one day. An initial `terraform-state` apply creates the bucket with local state and migrates that state to S3.

Packer reads `config/image.pkrvars.hcl` directly. The image workflow validates both templates and can build either or both AMIs; builds publish their IDs to SSM. No YAML interpreter or CI driver script is involved.

## Local validation

```bash
task ci:validate
```

Validation is not deployment evidence. The acceptance tests and evidence contract live in [`docs/01_architecture.md`](docs/01_architecture.md#11-verification-and-evidence).

## Branch roadmap

- `main` — scenario baseline.
- `audit-hardening` — RDS/Aurora migration plus stronger encryption, backup, security, and audit evidence.
- `modernized-pulumi` — containerized target architecture authored with Pulumi TypeScript.
