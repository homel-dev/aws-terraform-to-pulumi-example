# Brownfield Adoption Procedure

## 1. Purpose

The deployable POC and adoption of the existing manual environment are separate operations.

The import procedure MUST establish Terraform ownership without authorizing redesign or replacement.

## 2. Sequence

1. Export the observed AWS resource inventory and current security-group rules.
2. Match existing resources to the appropriate stack and Terraform addresses.
3. Add stack-local `import` blocks.
4. Run `terraform plan` and review every proposed action.
5. Adjust configuration until unintended replacement/destruction is removed.
6. Apply imports.
7. Record the post-import plan as evidence.
8. Perform architecture migration as a separate reviewed change.

## 3. Import ownership

Import identifiers belong to deployment stacks, for example:

```text
deployments/myorg/poc/use1/vpc/imports.tf
deployments/myorg/poc/use1/ec2/imports.tf
```

Reusable modules MUST NOT contain environment-specific import IDs.

## 4. Default VPC

The existing default VPC is observed state. Importing it does not make deletion acceptable.

Any migration from the default VPC to the POC VPC MUST have an explicit traffic cutover and rollback plan.
