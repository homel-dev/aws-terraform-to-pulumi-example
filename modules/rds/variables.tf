variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "application_security_group_id" {
  type = string
}

variable "migration_security_group_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "port" {
  type = number
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage_gib" {
  type = number
}

variable "master_username" {
  type = string
}

variable "backup_retention_days" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
