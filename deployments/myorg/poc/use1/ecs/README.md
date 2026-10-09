# `modernized-pulumi`: ECS/Fargate modernization (review-only by default)

This is the third, independent IaC stage after `main` and `audit-hardening`.
Pulumi TypeScript replaces the **application compute platform**, not the
Terraform state owner of the underlying VPC, Network Firewall, RDS, WAF,
logging bucket, or existing ALB/ASG.

The old ALB, listeners, application ASG, MySQL EC2, and any DNS record are **not
modified**. Pulumi creates a separate HTTPS ALB and ECS service for a later,
explicitly approved traffic cutover. The RDS database and Secrets Manager
secret are shared only after the reviewed MySQL migration. Terraform's
GuardDuty detector and CloudTrail continue to be managed by their own stacks.

## Resources created by Pulumi

- ECR repository with immutable tags and scan-on-push;
- ECS cluster, Fargate task definition and service; task role with access to
  the one existing database secret, execution role for ECR/CloudWatch;
- separate HTTPS ALB, `ip` target group, listener, and association with the
  **existing** WAF ACL; ALB logs go into the existing audit S3 bucket;
- isolated ALB/task security groups, a scoped inbound rule on the Terraform-
  owned RDS security group and a rule on the existing Secrets Manager VPC
  endpoint security group;
- private ECR API/DKR and CloudWatch Logs interface endpoints, and S3 gateway
  endpoint for existing app-subnet route tables; CloudWatch log group (30 days).

No EC2 MySQL retirement, DNS migration, Terraform `state rm`, import, RDS
creation, or WAF/GuardDuty creation is performed by this Pulumi program.

## Security and known limitations

- HTTPS source ranges **must** be an approved finite CIDR list. The example
  `203.0.113.10/32` in `Pulumi.example.yaml` is documentation-only.
- Fargate runs in private application subnets with no public IP. The current
  POC has only `app-a` for application capacity (one AZ), not production HA.
- HTTPS task egress is routed through the existing Network Firewall policy;
  the task SG by itself **does not** enforce allowed DNS names. Validate the
  actual app subnet routes, NAT/firewall status and SNI allowlist beforehand.
- ECR image pulls and `awslogs` use dedicated private endpoints. Existing
  Secrets Manager endpoint is reused; no conflicting duplicate endpoint.
- The container fetches the external customer artifact over HTTPS **when it
  starts**. It verifies SHA-256 if configured and writes an ephemeral file
  inside the running container. It never bakes or mirrors that artifact.
- `app.py` is only the documented POC fixture. `/db` checks TCP reachability
  (not SQL auth or data correctness); `/dependency` checks an HTTPS request.
  The real app/image and the artifact's ownership/install semantics remain
  customer-specific and must be reviewed before claiming application parity.
- `Pulumi.*.yaml`, local Pulumi state and `node_modules` are ignored. **Keep
  credentials, state files, and customer artifacts out of Git.**

> **Cost warning:** `pulumi up`, including with `desiredCount: 0`, can create
> a billable ALB, three interface endpoints, logs and other AWS resources.
> Setting `desiredCount: 1` additionally starts Fargate tasks. Existing RDS,
> Network Firewall and WAF have their own recurring costs. Nothing deploys
> from the included GitHub Actions workflow; it only checks TypeScript.

## Prerequisites

Node.js 20+, npm, Pulumi CLI, AWS CLI v2, Terraform, Docker, and an authorized
AWS CLI profile. Pulumi needs AWS access for an actual `preview` and a
separate state backend (Pulumi Cloud or a locally configured backend); it does
**not** read/write Terraform states directly. The Terraform hardening roots
must be **applied** before a deployable preview can use their real output IDs:

- `vpc`: `vpc_id`, `subnet_ids`, `route_table_ids`;
- `ec2`: `endpoint_security_group_id`, `database_secret_arn`;
- `rds`: `rds_security_group_id`, `database_rds_endpoint`;
- `logging`: `audit_bucket_name`;
- `waf`: `waf_web_acl_arn`;
- `acm` or approved operator input: a valid TLS `certificateArn`.

`Pulumi.example.yaml` lists every config key, but all its resource IDs/ARNs
and the ingress CIDR are intentionally fake. **Never use it to deploy.** If
the hardening stage remains unapplied, the code can be typechecked but a real
AWS preview cannot truthfully describe a deployable service.

## Local syntax check (no AWS access, no cost)

From the repo root:

```bash
cd deployments/myorg/poc/use1/ecs
npm ci
npm run typecheck
```

## Preview with your own AWS profile (no changes to AWS)

Review the outputs of each existing Terraform root. Example, from the repo
root (initialize their existing S3 backends first):

```bash
export AWS_PROFILE=default
export AWS_REGION=us-east-1
export TF_STATE_BUCKET=myorg-aws-terraform-state-681578444202
terraform -chdir=deployments/myorg/poc/use1/vpc output -json subnet_ids
terraform -chdir=deployments/myorg/poc/use1/vpc output -json route_table_ids
terraform -chdir=deployments/myorg/poc/use1/rds output -raw database_rds_endpoint
terraform -chdir=deployments/myorg/poc/use1/waf output -raw waf_web_acl_arn
```

Then, in `deployments/myorg/poc/use1/ecs`:

```bash
pulumi login --local             # or use your approved Pulumi backend
pulumi stack init poc
pulumi config set aws:region us-east-1
pulumi config set desiredCount 0

# Fill all remaining keys from Pulumi.example.yaml using 'pulumi config set'.
# For array-valued keys, use e.g.:
pulumi config set --path 'appSubnetIds[0]' 'subnet-FROM_VPC_STATE'
pulumi config set --path 'appRouteTableIds[0]' 'rtb-FROM_VPC_STATE'
pulumi config set --path 'publicSubnetIds[0]' 'subnet-PUBLIC_A'
pulumi config set --path 'publicSubnetIds[1]' 'subnet-PUBLIC_B'
pulumi config set --path 'ingressCidrs[0]' 'APPROVED_CLIENT_CIDR'

pulumi preview --diff
```

Check all proposed creates and the two ingress rules added to existing SGs.
There must be **no replacement or deletion** of any Terraform-owned object.
Do not run `pulumi up` merely to produce a review diagram or a preview.

## Optional two-phase deployment (requires separate approval and budget)

1. With `desiredCount=0`, review preview and, only if authorized, run `pulumi
   up`. This provisions the ECR repository, security boundaries, ALB,
   endpoints and ECS service with no running tasks. **It already incurs cost.**
2. Build the POC image from the repo root and push into the created ECR
   repository (repository URI is `pulumi stack output ecrRepositoryUrl`):

   ```bash
   export AWS_PROFILE=default
   export AWS_REGION=us-east-1
   export ECR_URI='VALUE_FROM_PULUMI_STACK_OUTPUT'
   aws ecr get-login-password --region us-east-1 --profile default |
     docker login --username AWS --password-stdin "${ECR_URI%%/*}"
   docker build -t "${ECR_URI}:poc-v1" containers/myorg/poc/use1/application
   docker push "${ECR_URI}:poc-v1"
   ```

3. Review the verified artifact URL/SHA-256, dependency, database secret and
   image tag. `pulumi config set desiredCount 1`, then `pulumi preview --diff`
   and (only after approval) `pulumi up`.
4. Verify ALB HTTPS, `/`, `/db` and `/dependency`, AWS WAF logs, CloudWatch
   task logs, ECR image provenance, outbound firewall logs, and private RDS
   access. DNS/cutover and eventual Terraform ASG/old DB retirement require
   **separate** change authorization and a rollback plan.

Stopping tasks without touching old infrastructure is a reviewed update to
`desiredCount=0`; destroying this stack removes its own ALB/endpoints but may
still require cleanup of an ECR repository containing images. No rollback of
database writes is implied by switching traffic back to EC2.
