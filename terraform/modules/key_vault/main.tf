data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.name_prefix}-${var.suffix}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true

  tags = var.tags
}

# Allow the deploying principal full access
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  key_permissions    = ["Get", "List", "Create", "Delete", "Update"]
}

resource "azurerm_key_vault_secret" "adls_key" {
  name         = "adls-primary-access-key"
  value        = var.adls_primary_access_key
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}
