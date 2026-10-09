resource "aws_db_subnet_group" "database" {
  for_each = local.configs

  name = "${local.name_prefixes[each.key]}-rds"
  subnet_ids = [
    local.vpc_states[each.key].subnet_ids[each.value.database.subnet],
    local.vpc_states[each.key].subnet_ids[each.value.database.rds.standby_subnet],
  ]

  tags = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_db_instance" "database" {
  for_each = local.configs

  identifier                  = "${local.name_prefixes[each.key]}-mysql"
  engine                      = "mysql"
  engine_version              = each.value.database.rds.engine_version
  instance_class              = each.value.database.rds.instance_class
  allocated_storage           = each.value.database.rds.allocated_storage_gib
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = each.value.database.name
  username                    = each.value.database.rds.master_username
  manage_master_user_password = true
  port                        = each.value.database.port

  db_subnet_group_name   = aws_db_subnet_group.database[each.key].name
  vpc_security_group_ids = [aws_security_group.rds[each.key].id]
  publicly_accessible    = false
  multi_az               = true

  backup_retention_period   = each.value.database.rds.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefixes[each.key]}-mysql-final"

  tags = merge(local.common_tags, try(each.value.tags, {}))
}
