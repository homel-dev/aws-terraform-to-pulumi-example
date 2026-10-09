module "rds" {
  source   = "../rds"
  for_each = local.configs

  name_prefix = local.name_prefixes[each.key]
  vpc_id      = local.vpc_states[each.key].vpc_id
  subnet_ids = [
    local.vpc_states[each.key].subnet_ids[each.value.database.subnet],
    local.vpc_states[each.key].subnet_ids[each.value.database.rds.standby_subnet],
  ]
  application_security_group_id = aws_security_group.application[each.key].id
  migration_security_group_id   = aws_security_group.database[each.key].id
  db_name                       = each.value.database.name
  port                          = each.value.database.port
  engine_version                = each.value.database.rds.engine_version
  instance_class                = each.value.database.rds.instance_class
  allocated_storage_gib         = each.value.database.rds.allocated_storage_gib
  master_username               = each.value.database.rds.master_username
  backup_retention_days         = each.value.database.rds.backup_retention_days
  tags                          = merge(local.common_tags, try(each.value.tags, {}))
}
