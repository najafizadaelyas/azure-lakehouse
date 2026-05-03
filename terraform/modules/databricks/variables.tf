variable "resource_group_name"             { type = string }
variable "location"                         { type = string }
variable "name_prefix"                      { type = string }
variable "sku"                              { type = string }
variable "cluster_node_type"               { type = string }
variable "spark_version"                   { type = string }
variable "autotermination_minutes"         { type = number }
variable "adls_account_name"              { type = string }
variable "adls_account_key_secret_id"     { type = string }
variable "key_vault_id"                   { type = string  default = "" }
variable "key_vault_uri"                  { type = string  default = "" }
variable "tags"                            { type = map(string) }
