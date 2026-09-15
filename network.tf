resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-lab"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# Web tier. Keeps default outbound internet access, because removing it would
# require a NAT gateway for the App Service to reach the internet once regional
# VNet integration is enabled.
resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]

  default_outbound_access_enabled = true

  # Required before an App Service can integrate into this subnet.
  # Uncomment together with the App Service in app-service.tf.
  # delegation {
  #   name = "app-service-delegation"
  #   service_delegation {
  #     name    = "Microsoft.Web/serverFarms"
  #     actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
  #   }
  # }
}

# Data tier. Private subnet: no default outbound access, because the only thing
# that will ever live here is the SQL private endpoint, which needs no egress.
resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.2.0/24"]

  default_outbound_access_enabled = false
}
