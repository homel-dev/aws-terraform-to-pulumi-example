resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Private managed MySQL; application and migration source only"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_application" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.application_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Application to managed MySQL"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_database" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.migration_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "MySQL data migration from existing EC2"
}

resource "aws_db_subnet_group" "database" {
  name       = "${var.name_prefix}-rds"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_db_instance" "database" {
  identifier                  = "${var.name_prefix}-mysql"
  engine                      = "mysql"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage_gib
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true
  port                        = var.port

  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = true

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-mysql-final"

  tags = var.tags
}
