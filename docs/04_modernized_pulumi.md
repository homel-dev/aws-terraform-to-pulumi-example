# Modernized Pulumi branch — complete target infrastructure

The `modernized-pulumi` branch describes the **full intended AWS target** in
Pulumi TypeScript. It does not read Terraform remote state, require Terraform
outputs, or adopt an AWS resource automatically.

## Source layout and ownership

| Reusable implementation | Resources / responsibility |
| --- | --- |
| `modules/pulumi/vpc/` | VPC, IGW, public/private subnets, route tables |
| `modules/pulumi/firewall/` | Network Firewall, TLS-SNI allowlist, NAT, protected routing and logs |
| `modules/pulumi/security/` | Allowed HTTPS sources, ALB/application/RDS/endpoint security groups and rules |
| `modules/pulumi/logging/` | Encrypted versioned audit S3, CloudTrail, VPC Flow Logs |
| `modules/pulumi/route53/` | Public hosted zone and application ALB alias |
| `modules/pulumi/acm/` | DNS-validated ACM certificate, or explicitly imported certificate ARN |
| `modules/pulumi/rds/` | Private Multi-AZ MySQL, backups, encryption, app secret metadata |
| `modules/pulumi/iam/` | Task execution role and least-privilege app-secret read |
| `modules/pulumi/ecs/` | ECR, Fargate, ECS cluster, ALB, private AWS endpoints, CloudWatch logs |
| `modules/pulumi/waf/` | Regional ACL, AWS managed rule groups and ALB association |
| `modules/pulumi/guardduty/` | Regional GuardDuty detector |
| `modules/pulumi/platform/` | Component composition, typed configuration and outputs |

Each implementation exports a `pulumi.ComponentResource` with resource children
parented to that component. Deployment-specific values live **only** in
`deployments/myorg/poc/use1/pulumi/config/*.yml`; its `Pulumi.yaml` points
at the common platform entrypoint under `modules/pulumi/platform/index.ts`.
`package.json`, the lockfile and TypeScript configuration also live under
`modules/pulumi/` instead of the deployment root.

The prior `deployments/myorg/poc/use1/ecs/index.ts` monolith is removed by
this *incremental patch over the previous Pulumi patch*. Its container fixture
at `containers/myorg/poc/use1/application/` is retained.

The older Terraform roots remain available in the repository as the baseline
and hardening migration source; **they are not dependencies of this Pulumi
program and must not independently manage the same live AWS resources**.

## Review without deployment

Run these commands from the repository root:

```bash
cd modules/pulumi
npm ci
npm run typecheck

cd ../../deployments/myorg/poc/use1/pulumi
export AWS_PROFILE=default
export AWS_REGION=us-east-1
pulumi login --local  # or your approved Pulumi state backend
pulumi stack init poc
pulumi config set aws:region us-east-1
pulumi preview --diff
```

`npm run typecheck` does not access AWS. `pulumi preview` may need read-only
AWS permissions and a configured Pulumi state backend. It does **not** apply
the preview. GitHub Actions only checks the TypeScript source; it contains no
automatic `pulumi up` or OIDC credential configuration.

## Required decisions before any real `pulumi up`

1. Replace the RFC 5737 example client CIDR in `config/security.yml` with
   the approved public source range.
2. Replace `poc.example.com` and `app.poc.example.com` in `config/dns.yml`
   with a **delegated** zone/domain. Managed ACM DNS validation cannot
   complete until the correct authoritative DNS exists. Alternatively choose
   `certificate_mode: imported` and supply a valid ARN in the same region.
3. Replace the placeholder `https://example.com/` boot artifact and establish
   ownership, redirect destinations, optional SHA-256 and application install
   semantics. The container downloads the artifact at runtime; it never bakes
   it into the image or copies it to a persistent package mirror.
4. Prepare the **actual application container**. The checked-in `app.py` is
   only a synthetic POC fixture: `/db` checks TCP reachability, not SQL login
   or data parity. Populate the separate application DB credential secret
   after provisioning; Pulumi deliberately does not store its password.
5. Review domain-level egress. The SG allows TCP/443, but the application
   subnet route passes through Network Firewall. ECR API/DKR, CloudWatch Logs
   and Secrets Manager have private endpoints, with an S3 gateway endpoint.
6. Check regional singleton resources. GuardDuty permits one regional
   detector per account. If the audit-hardening branch already created one,
   use a reviewed import/ownership transfer rather than creating a duplicate.
7. Establish the target ownership model. This code creates a **separate**
   named platform (`myorg-poc-use1-modern`), not an automatic import of
   Terraform-managed VPC/RDS/ALB. A same-resource migration requires an
   explicit, backed-up cross-tool state plan; no state is modified here.

### Explicit cost boundary

The project is for review by default (`desired_count: 0`). **Even at zero
tasks, `pulumi up` would create chargeable RDS Multi-AZ, Network Firewall,
NAT Gateway, ALB, ECR/VPC endpoints, GuardDuty/WAF and logging resources**.
Do not apply merely to render a diagram. RDS deletion protection is enabled,
and ECR image retention can complicate eventual stack destruction.

The POC has only one `app-a` AZ (as in the Terraform baseline). Multi-AZ RDS
does not imply Multi-AZ ECS availability. A second application AZ is an
explicit later availability decision, not silently added by this patch.

## Image preparation after an explicitly authorized first deployment

For a reviewed first deployment, set `desired_count: 0`, review `pulumi
preview`, then manually authorize `pulumi up`. After the ECR repository exists,
from the repository root:

```bash
export AWS_PROFILE=default
export AWS_REGION=us-east-1
export ECR_URI='VALUE_FROM_pulumi_stack_output_ecrRepositoryUrl'
aws ecr get-login-password --region us-east-1 --profile default |
  docker login --username AWS --password-stdin "${ECR_URI%%/*}"
docker build -t "${ECR_URI}:poc-v1" containers/myorg/poc/use1/application
docker push "${ECR_URI}:poc-v1"
```

Only after verifying application readiness and credentials, change
`config/application.yml` to `desired_count: 1`, preview again, then consider
an explicitly approved apply. This source update does not implement database
cutover, DNS switchover from the Terraform ALB, or legacy EC2/DLM retirement.
