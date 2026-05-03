variable "resource_group_name"      { type = string }
variable "location"                  { type = string }
variable "name_prefix"               { type = string }
variable "suffix"                    { type = string }
variable "tags"                      { type = map(string) }
variable "adls_primary_access_key"   {
  type      = string
  sensitive = true
  default   = ""  # injected by root module after storage is created
}
