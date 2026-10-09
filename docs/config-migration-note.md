# Location configuration and state migration (main)

The location owns the AWS region. Set it once in
`deployments/myorg/poc/use1/location.yml`:

```yaml
region: us-east-1
```

Stack YAML files under `deployments/myorg/poc/use1/<stack>/config/` do
**not** declare `region`. Terraform reads it from the parent location
directory; this is separate from Terraform's static S3 backend configuration.

One YAML represents one independently keyed logical resource bundle, with
related AWS child resources. Adding `config/second.yml` to a module creates
`resource["second"]` addresses; it does **not** overwrite the first bundle.
This follows the existing VPC and ACM config conventions.

| Stack | Existing YAML key | Collection output | Legacy single-object output |
| --- | --- | --- | --- |
| vpc | `vpc` | `vpcs` | root VPC flat outputs |
| acm | `certificate` | `certificate_arns` | `certificate_arn` |
| logging | `audit` | `loggings` | audit bucket/CloudTrail/flow log |
| iam | `instances` | `groups` | app/database roles and profiles |
| firewall | `egress` | `firewalls` | firewall, endpoint, NAT |
| ec2 | `compute` | `computes` | ALB/app/database outputs |
| dlm | `database` | `policies` | `policy_arn` |
| terraform-state | `state` | `buckets` | `bucket_name`, `bucket_arn` |

Existing filenames are significant: `moved.tf` maps the old Terraform
addresses to the corresponding keyed addresses. Do not rename those YAML
files during adoption without reviewing the state moves.

For consumers of existing VPCs, `vpc_key: vpc` is the default in logging,
firewall and ec2. To bind another bundle to a second VPC, put for example
`vpc_key: analytics` in that bundle's YAML, after adding
`vpc/config/analytics.yml`. EC2 additionally supports `iam_key`,
`logging_key`, and `acm_key`; defaults are `instances`, `audit`, and
`certificate`. The selected keys must exist in upstream state outputs.

The first, unchanged logical bundles keep their existing AWS physical
names. Additional bundles get distinct names based on filename except
where the schema requires an explicit name (such as firewall `name`).
Terraform-state uses the original bucket name for `state.yml` and a
filename suffix for additional bucket configs.

## Safe execution order

1. Back up all existing Terraform state files and review the configured
   S3 state bucket and backend keys. Never recreate/delete the state bucket
   during this migration.
2. From the repository root, run `terraform -chdir=deployments/myorg/poc/use1/vpc
   init -backend-config="bucket=$TF_STATE_BUCKET"` (repeat for each stack).
3. Run `terraform fmt -check` and `terraform validate` for each root.
4. Run `terraform plan -out=adoption.tfplan` for each root in dependency
   order: vpc, iam/route53, logging/firewall/acm, ec2, dlm. Use the
   actual root directory as working directory.
5. Read `terraform show adoption.tfplan`. An existing resource should
   appear under a moved address, not as a destroy/create replacement.
   Do not apply a plan with unexplained infrastructure changes.
6. Apply **that exact reviewed** `adoption.tfplan` only after approval.
   Re-run a plan to check for unintended drift.

`moved.tf` only readdresses resources *already in Terraform state*.
For AWS resources not yet imported, use explicit Terraform import blocks
and real AWS identifiers, as described by the brownfield adoption guide.
Never interpret a clean plan without an import as evidence that adoption
is complete.

**Deployment caution:** this change restructures resource addresses.
It was prepared without AWS access; a provider-backed plan against the
real state is mandatory before apply.
