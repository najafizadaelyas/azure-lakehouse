output "name" {
  value = azurerm_data_factory.adf.name
}

output "id" {
  value = azurerm_data_factory.adf.id
}

output "principal_id" {
  value = azurerm_data_factory.adf.identity[0].principal_id
}
