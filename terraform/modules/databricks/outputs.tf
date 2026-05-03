output "workspace_id" {
  value = azurerm_databricks_workspace.ws.id
}

output "workspace_url" {
  value = "https://${azurerm_databricks_workspace.ws.workspace_url}"
}

output "cluster_id" {
  value = databricks_cluster.main.id
}

output "managed_identity_principal_id" {
  # The managed resource group's service principal; used for RBAC
  value = azurerm_databricks_workspace.ws.storage_account_identity[0].principal_id
}
