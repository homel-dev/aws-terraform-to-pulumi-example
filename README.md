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
├── ci/
│   ├── images.yml
│   ├── images.sh
│   ├── order.yml
│   └── run.sh
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

`deployments/myorg/poc/use1/ci/config.yml` is only the **first-deployment/apply order** used by the location-local CI helper. It is not a Terraform dependency graph and it does not cause Terraform to recreate upstream stacks.

Cross-stack data is read explicitly with `terraform_remote_state`. For example, the firewall stack reads VPC outputs. If the VPC state already exists and has no changes, applying firewall does not apply or recreate the VPC. If the VPC state does not exist yet, the firewall plan fails because its required inputs are unavailable.

Inside one Terraform stack, normal HCL references and occasional resource-level `depends_on` are real Terraform graph edges. They control ordering inside that state only; they do not automatically recreate a dependency.

## Main-branch scope

`main` implements the scenario baseline:

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

The location stack registry is [`deployments/myorg/poc/use1/ci/config.yml`](deployments/myorg/poc/use1/ci/config.yml). The first-deployment order is documented here; image creation is a separate pipeline between `vpc` and the remaining runtime stacks.

The order exists because downstream stacks consume outputs from already-created remote states. It is not lifecycle coupling between their states.

## GitHub Actions

GitHub executes workflows only from `.github/workflows/`. The repository therefore keeps thin GitHub entry points there while the location-specific execution logic lives under `deployments/myorg/poc/use1/ci/`.

Required GitHub variables:

- `AWS_ROLE_ARN` — OIDC role for Terraform plan/apply;
- `AWS_IMAGE_ROLE_ARN` — OIDC role for Packer builds.

`apply` uses the protected GitHub Environment `myorg-poc-use1`.

The Terraform workflow plans or applies one selected stack at a time. This makes each state boundary explicit and prevents a CI helper from hiding cross-stack changes. The separate image workflow builds and publishes AMI IDs.

## Local validation

```bash
task ci:validate
```

Validation is not deployment evidence. The acceptance tests and evidence contract live in [`docs/01_architecture.md`](docs/01_architecture.md#11-verification-and-evidence).

## Branch roadmap

- `main` — scenario baseline.
- `audit-hardening` — RDS/Aurora migration plus stronger encryption, backup, security, and audit evidence.
- `modernized-pulumi` — containerized target architecture authored with Pulumi TypeScript.
