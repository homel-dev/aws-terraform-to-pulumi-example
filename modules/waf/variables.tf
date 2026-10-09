variable "name_prefix" {
  type = string
}

variable "resource_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
