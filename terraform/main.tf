locals {
  name_prefix = "${var.project}-${var.environment}"
  default_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project
    managed_by  = "terraform"
  })
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# ── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.default_tags
}

# ── Modules ────────────────────────────────────────────────────────────────────
module "storage" {
  source = "./modules/storage"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = local.name_prefix
  suffix              = random_string.suffix.result
  replication_type    = var.adls_replication_type
  tags                = local.default_tags
}

module "key_vault" {
  source = "./modules/key_vault"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = local.name_prefix
  suffix              = random_string.suffix.result
  tags                = local.default_tags
}

module "databricks" {
  source = "./modules/databricks"

  resource_group_name              = azurerm_resource_group.main.name
  location                         = var.location
  name_prefix                      = local.name_prefix
  sku                              = var.databricks_sku
  cluster_node_type                = var.databricks_cluster_node_type
  spark_version                    = var.databricks_spark_version
  autotermination_minutes          = var.databricks_autotermination_minutes
  adls_account_name                = module.storage.account_name
  adls_account_key_secret_id       = module.key_vault.adls_key_secret_id
  tags                             = local.default_tags
}

module "data_factory" {
  source = "./modules/data_factory"

  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  name_prefix                 = local.name_prefix
  adls_account_name           = module.storage.account_name
  adls_account_id             = module.storage.account_id
  databricks_workspace_url    = module.databricks.workspace_url
  databricks_cluster_id       = module.databricks.cluster_id
  key_vault_id                = module.key_vault.key_vault_id
  key_vault_uri               = module.key_vault.key_vault_uri
  tags                        = local.default_tags
}

# ── RBAC: ADF managed identity → ADLS ─────────────────────────────────────────
resource "azurerm_role_assignment" "adf_storage_contributor" {
  scope                = module.storage.account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.data_factory.principal_id
}

# ── RBAC: Databricks → ADLS ────────────────────────────────────────────────────
resource "azurerm_role_assignment" "databricks_storage_contributor" {
  scope                = module.storage.account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.databricks.managed_identity_principal_id
}
