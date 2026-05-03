variable "resource_group_name"              { type = string }
variable "location"                          { type = string }
variable "name_prefix"                       { type = string }
variable "adls_account_name"                { type = string }
variable "adls_account_id"                  { type = string }
variable "databricks_workspace_url"         { type = string }
variable "databricks_workspace_resource_id" {
  type    = string
  default = ""
}
variable "databricks_cluster_id"            { type = string }
variable "key_vault_id"                     { type = string }
variable "key_vault_uri"                    { type = string }
variable "tags"                              { type = map(string) }
