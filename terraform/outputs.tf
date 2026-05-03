output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "adls_account_name" {
  value = module.storage.account_name
}

output "databricks_workspace_url" {
  value = module.databricks.workspace_url
}

output "databricks_cluster_id" {
  value = module.databricks.cluster_id
}

output "data_factory_name" {
  value = module.data_factory.name
}

output "key_vault_uri" {
  value = module.key_vault.key_vault_uri
}
