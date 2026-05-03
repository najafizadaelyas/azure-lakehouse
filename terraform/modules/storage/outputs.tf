output "account_name" {
  value = azurerm_storage_account.adls.name
}

output "account_id" {
  value = azurerm_storage_account.adls.id
}

output "primary_access_key" {
  value     = azurerm_storage_account.adls.primary_access_key
  sensitive = true
}

output "dfs_endpoint" {
  value = azurerm_storage_account.adls.primary_dfs_endpoint
}
