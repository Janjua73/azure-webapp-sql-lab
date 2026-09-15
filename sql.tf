resource "azurerm_mssql_server" "lab" {
  name                = var.sql_server_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  version             = "12.0"
  tags                = var.tags

  # SQL authentication. Entra authentication is configured below; both are
  # enabled because the lab starts with SQL auth and moves to passwordless.
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  minimum_tls_version = "1.2"

  # Public endpoint stays on until the private endpoint replaces it.
  public_network_access_enabled = true

  azuread_administrator {
    login_username              = var.entra_admin_login
    object_id                   = var.entra_admin_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = false
  }
}

resource "azurerm_mssql_database" "lab" {
  name      = var.sql_database_name
  server_id = azurerm_mssql_server.lab.id
  tags      = var.tags

  # General Purpose serverless, Gen5, 1 vCore ceiling.
  sku_name     = "GP_S_Gen5_1"
  min_capacity = 0.5
  max_size_gb  = 32

  # Pause after an hour idle. Serverless bills per vCore-second of activity, so
  # a paused database costs nothing for compute. Cost of the trade-off is a
  # cold start of a few seconds on the first query after a pause.
  auto_pause_delay_in_minutes = 60

  # Locally-redundant backup storage. Geo-redundant costs more and is not
  # needed for a lab.
  storage_account_type = "Local"
  zone_redundant       = false

  collation = "SQL_Latin1_General_CP1_CI_AS"

  # Azure SQL free offer: 100,000 vCore-seconds, 32 GB data and 32 GB backup
  # per month. AutoPause means the database pauses when the free allowance is
  # exhausted instead of falling through to paid rates - the only genuine hard
  # cost stop available on a pay-as-you-go subscription.
  #
  # Requires a recent azurerm 4.x provider. If `terraform validate` rejects
  # these two arguments, upgrade the provider; do not simply delete them, or
  # the database will be created as a billable one.
  use_free_limit                = true
  free_limit_exhaustion_behavior = "AutoPause"

  lifecycle {
    # Guard against a careless plan proposing to drop and recreate the database.
    prevent_destroy = false # set true once this holds anything worth keeping
  }
}

# Allows other Azure services to reach the server. The 0.0.0.0 start/end pair
# is Azure's documented special case for this, not a literal address range.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.lab.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Local admin access from a home connection. This rule is pinned to one public
# IP and will need updating whenever the ISP changes it. It becomes unnecessary
# once the private endpoint is in place and public access is disabled.
resource "azurerm_mssql_firewall_rule" "allow_client_ip" {
  name             = "AllowClientIP"
  server_id        = azurerm_mssql_server.lab.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}
