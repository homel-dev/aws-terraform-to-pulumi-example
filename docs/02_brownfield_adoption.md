# Superseded adoption guide

The authoritative procedure is **[POC seed and direct Terraform adoption](02_poc_adoption.md)**.

The former `deployments/myorg/brownfield/use1/compute` Terraform root has been removed. Do **not** follow historical brownfield Compute commands, import into its old state, or operate both states against the same AWS resources. VPC and Compute imports now target `deployments/myorg/poc/use1/vpc` and `deployments/myorg/poc/use1/ec2` respectively.

This path is retained only to avoid broken links to the previous document.
