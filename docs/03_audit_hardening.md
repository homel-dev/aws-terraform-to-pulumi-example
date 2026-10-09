# Audit-hardening: RDS migration, GuardDuty and WAF

This branch adds three independent Terraform roots and S3 state keys under
`myorg/poc/use1`: `rds`, `waf`, and `guardduty`. They invoke the reusable
modules in `modules/rds`, `modules/waf`, and `modules/guardduty`. The original
`ec2` and `logging` roots do not own these resources.

The EC2 MySQL instance and its DLM snapshot policy remain managed until a
separately approved retirement. The new RDS and WAF stacks read outputs from
the already-applied EC2 state. There is no EC2-to-RDS remote-state dependency.

## Terraform resources and ordering

1. Apply `deployments/myorg/poc/use1/vpc` to add the private `database-b`
   subnet (`us-east-1b`, `10.42.21.0/24`). Existing `database-a` remains in
   `us-east-1a`. RDS requires a DB subnet group spanning at least two AZs.
2. Apply `deployments/myorg/poc/use1/guardduty` for the regional detector.
3. Apply `deployments/myorg/poc/use1/ec2` for the existing ALB, application,
   database EC2 and their security groups.
4. Apply `deployments/myorg/poc/use1/rds` for private MySQL 8.4 RDS with
   Multi-AZ standby, AWS-managed KMS encryption, seven-day automated backups
   and deletion protection, plus app/database-to-RDS security-group rules.
5. Apply `deployments/myorg/poc/use1/waf` to associate a regional WAF ACL with
   the ALB managed by the EC2 stack.

Use the existing plan/review/apply workflow for these roots. The EC2 root still
manages the old MySQL EC2 instance, which is required as the migration source.
The RDS master password is managed in AWS Secrets Manager, not stored in
Terraform configuration or outputs.

### GuardDuty adoption

GuardDuty supports exactly one detector per AWS account and Region. Check the
account before the first Terraform apply:

```bash
aws guardduty list-detectors --region us-east-1 --output json
```

If a detector already exists, import its ID into the GuardDuty root
before running the apply. Set `TF_STATE_BUCKET` as in
[the state-backend procedure](02_poc_adoption.md#4-initialize-the-encrypted-remote-state-backend)
and initialize **this root's own backend** before import:

```bash
terraform -chdir=deployments/myorg/poc/use1/guardduty init \
  -backend-config="bucket=$TF_STATE_BUCKET"
terraform -chdir=deployments/myorg/poc/use1/guardduty import \
  module.guardduty.aws_guardduty_detector.regional DETECTOR_ID
```

If no detector exists, the GuardDuty Terraform root creates it. Never enable a
second detector via another Terraform state root in the same account/Region.

### Existing audit-hardening state migration

**Do not apply the new roots while any RDS/WAF/GuardDuty resources remain
managed by the old EC2 or logging states.** Terraform `moved` blocks cannot
move resources between two independently configured remote backends. Inspect
both state files and migrate the exact resource addresses with a controlled,
backed-up cross-state operation before running a plan or apply. This branch
does not automatically modify remote states.

For an earlier modular audit-hardening apply, the old-to-new address mapping is:

| Old address (within its root state) | New address (within its root state) |
| --- | --- |
| `module.ec2.module.rds["compute"].aws_db_instance.database` | `module.rds.aws_db_instance.database` |
| `module.ec2.module.rds["compute"].aws_db_subnet_group.database` | `module.rds.aws_db_subnet_group.database` |
| `module.ec2.module.rds["compute"].aws_security_group.rds` | `module.rds.aws_security_group.rds` |
| `module.ec2.module.rds["compute"].aws_vpc_security_group_ingress_rule.rds_from_application` | `module.rds.aws_vpc_security_group_ingress_rule.rds_from_application` |
| `module.ec2.module.rds["compute"].aws_vpc_security_group_ingress_rule.rds_from_database` | `module.rds.aws_vpc_security_group_ingress_rule.rds_from_database` |
| `module.ec2.aws_vpc_security_group_egress_rule.application_to_rds["compute"]` | `module.rds.aws_vpc_security_group_egress_rule.application_to_rds` |
| `module.ec2.aws_vpc_security_group_egress_rule.database_to_rds["compute"]` | `module.rds.aws_vpc_security_group_egress_rule.database_to_rds` |
| `module.ec2.module.waf["compute"].aws_wafv2_web_acl.application` | `module.waf.aws_wafv2_web_acl.application` |
| `module.ec2.module.waf["compute"].aws_wafv2_web_acl_association.application` | `module.waf.aws_wafv2_web_acl_association.application` |
| `module.logging.module.guardduty.aws_guardduty_detector.regional` | `module.guardduty.aws_guardduty_detector.regional` |

If the prior audit-hardening revision did not use child modules, its source
addresses differ. Read `terraform state list` instead of assuming the mapping
above. Confirm plans for all five affected roots do not propose resource
destruction or recreation before applying. Existing AWS tags retain the old
`Stack` and `Module` tag values to avoid a separate retagging change.

## Planned MySQL cutover (requires downtime)

The database cutover is **not** triggered by Terraform apply. The customer
application artifact is still a placeholder, so its handling of the existing
`MYORG_DATABASE_SECRET` name and the secret's `host`/`port` fields must be
confirmed before traffic is resumed.

1. Confirm RDS is available. Record the EC2 Terraform outputs
   `database_instance_id`, `database_secret_arn`, and the **RDS** stack outputs
   `database_rds_endpoint` and `database_rds_master_secret_arn`.
2. Stop application writes, stop application workers and preserve a recoverable
   source snapshot/backup. Do not resume writes during the dump and restore.
3. Open an SSM session on the **existing database EC2 instance**. This is the
   migration source and has a VPC security-group path to the private RDS
   instance. Copy `scripts/migrate-mysql-ec2-to-rds.sh` there.
4. Obtain the RDS master password using the master secret ARN and an authorized
   operator identity. Supply it through the interactive SSM shell without
   placing credentials in a script, Terraform variable or shell history:

```bash
export AWS_DEFAULT_REGION=us-east-1
export DATABASE_SECRET_ID=myorg-poc-use1/database
export RDS_HOST=RDS_ENDPOINT_FROM_TERRAFORM_OUTPUT
export RDS_MASTER_USER=myorg_admin
read -r -s -p 'RDS master password: ' RDS_MASTER_PASSWORD
export RDS_MASTER_PASSWORD
bash scripts/migrate-mysql-ec2-to-rds.sh
unset RDS_MASTER_PASSWORD
```

The script streams a transactional MySQL dump directly into RDS using TLS,
creates/updates the database application principal with the existing secret's
password, and only then adds the RDS `host` and `port` to the same application
Secrets Manager secret. It does **not** delete or stop the EC2 database,
start the application, or issue a Terraform apply.

5. Ensure the application reads the updated endpoint from Secrets Manager,
   restart/roll it under operator control, verify its DB connection and data,
   then release the write freeze.

### Failure and rollback

If any import or connectivity step fails, keep application writes stopped and
continue using the existing EC2 database only after confirming its data is
intact. If the secret was switched, restore the previous secret version (or its
original fields) before restarting the application. Once writes have resumed
against RDS, switching back requires data reconciliation; no automatic
rollback is provided.

The old EC2 instance and DLM policy remain active until a **separate approved
decommission**. RDS deletion protection intentionally blocks direct deletion
on Terraform destroy. Multi-AZ RDS, GuardDuty and WAF introduce recurring AWS
charges. WAF uses the AWS-managed IP Reputation and Common Rule groups with
their blocking actions, so false positives can reject legitimate requests.

The branch does not enable AWS Config or Security Hub. GitHub Actions adds the
three new roots to plan/apply selections, PR plans, full-location ordering and
deployed-state architecture generation without changing permissions.
