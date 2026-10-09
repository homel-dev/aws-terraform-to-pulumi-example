# VPC (Terraform, main branch)

Each `*.yml` file under a deployment root's `config/` manages one VPC.
For example, `config/vpc.yml` and `config/analytics.yml` create two independent
VPCs in **the same Terraform root and state**. There is no one-file limit.
All files in that root must use the same AWS region because the module has one
AWS provider configuration.

The existing brownfield YAML is
`deployments/myorg/poc/use1/vpc/config/vpc.yml`.
`examples/analytics.yml` shows a **second VPC** but is intentionally outside
the active deployment `config/`; it creates no AWS resources until deliberately
copied there. Adding the example to `config/` would make Terraform plan a new
VPC; it is not an import of an already existing VPC.

The YAML shape follows the ACM module's convention: read files from
`${path.root}/config`, merge `default.yml`, check `schema.yml` with the
`tlkamp/validation` provider, and address resources with `for_each`.

```hcl
aws_vpc.this["vpc"]
aws_vpc.this["analytics"]
aws_subnet.this["vpc/public-a"]
aws_subnet.this["analytics/public-a"]
```

`output "vpcs"` is a map keyed by relative YAML filename (minus `.yml`):

```hcl
module.vpc.vpcs["vpc"].vpc_id
module.vpc.vpcs["analytics"].subnet_ids["public-a"]
```

In the POC deployment root only, old flat outputs are explicitly mapped to
`module.vpc.vpcs["vpc"]` to preserve remote-state consumers while supporting
more VPCs. This is a brownfield compatibility choice at the **root**, not a
single-VPC restriction inside the reusable module.

The existing POC topology requirements are preserved for **each** VPC:
at least two public subnets and at least one each of `application`, `database`,
and `firewall`. The module creates an Internet gateway, a route table per
subnet and a default Internet-gateway route only for `public` subnets;
private route defaults are managed by the firewall stack.

Brownfield state migration is explicit: the deployment root has `moved.tf`
mapping the old addresses to `"vpc"`-prefixed addresses and `imports.tf`
targeting the same final addresses for a not-yet-imported seed environment.
**Review `terraform plan` before applying; do not apply blindly to live VPCs.**
