output "resource_group_name" {
  description = "Resource group containing the lab."
  value       = azurerm_resource_group.lab.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL logical server."
  value       = azurerm_mssql_server.lab.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL database."
  value       = azurerm_mssql_database.lab.name
}

output "key_vault_uri" {
  description = "Key Vault URI, used to build Key Vault references in app settings."
  value       = azurerm_key_vault.lab.vault_uri
}

output "web_subnet_id" {
  description = "Resource ID of the web-tier subnet, for App Service VNet integration."
  value       = azurerm_subnet.web.id
}

output "data_subnet_id" {
  description = "Resource ID of the data-tier subnet, for the SQL private endpoint."
  value       = azurerm_subnet.data.id
}
