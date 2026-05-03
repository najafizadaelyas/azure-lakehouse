variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus2"
}

variable "project" {
  type        = string
  description = "Project name used in resource naming"
  default     = "lhouse"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}

# Databricks
variable "databricks_sku" {
  type        = string
  description = "Databricks workspace SKU"
  default     = "premium"
}

variable "databricks_cluster_node_type" {
  type        = string
  default     = "Standard_DS3_v2"
}

variable "databricks_spark_version" {
  type        = string
  default     = "13.3.x-scala2.12"
}

variable "databricks_autotermination_minutes" {
  type        = number
  default     = 30
}

# Storage
variable "adls_replication_type" {
  type        = string
  default     = "ZRS"
}

# ADF
variable "adf_git_integration" {
  type        = bool
  description = "Enable ADF Git integration"
  default     = false
}
