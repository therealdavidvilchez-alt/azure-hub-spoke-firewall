terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-hubspoke-project"
  location = "West Europe"
}

resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "fw_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --------------------------------------------------------------
# VNet Spoke A (Workload)
resource "azurerm_virtual_network" "spoke_a" {
  name                = "vnet-spoke-a"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "snet_workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke_a.name
  address_prefixes     = ["10.1.1.0/24"]
}

# --------------------------------------------------------------
# VNet Spoke B (Database)
resource "azurerm_virtual_network" "spoke_b" {
  name                = "vnet-spoke-b"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_subnet" "snet_db" {
  name                 = "snet-database"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke_b.name
  address_prefixes     = ["10.2.1.0/24"]
}

# --------------------------------------------------------------
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_subnet" "gw_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# --------------------------------------------------------------
resource "azurerm_public_ip" "fw_pip" {
  name                = "pip-firewall"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Recurso Azure Firewall
resource "azurerm_firewall" "afw" {
  name                = "afw-central-hub"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.main_policy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.fw_subnet.id
    public_ip_address_id = azurerm_public_ip.fw_pip.id
  }
}

# --- PEERINGS PARA SPOKE A ----------------------------------------

resource "azurerm_virtual_network_peering" "hub_to_spoke_a" {
  name                      = "peer-hub-to-spoke-a"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_a.id
  allow_gateway_transit     = true
}

resource "azurerm_virtual_network_peering" "spoke_a_to_hub" {
  name                      = "peer-spoke-a-to-hub"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.spoke_a.name
  remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
  use_remote_gateways       = false
}

# --- PEERINGS PARA SPOKE B ---

resource "azurerm_virtual_network_peering" "hub_to_spoke_b" {
  name                      = "peer-hub-to-spoke-b"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_b.id
  allow_gateway_transit     = true
}

resource "azurerm_virtual_network_peering" "spoke_b_to_hub" {
  name                      = "peer-spoke-b-to-hub"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.spoke_b.name
  remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
  use_remote_gateways       = false
}
# ------------------------------------------------------------------------------------------------
# Política FW (contenedor principal)
resource "azurerm_firewall_policy" "main_policy" {
  name                = "policy-hub-central"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Rules FW
resource "azurerm_firewall_policy_rule_collection_group" "network_rules" {
  name               = "gr-network-rules"
  firewall_policy_id = azurerm_firewall_policy.main_policy.id
  priority           = 100

  network_rule_collection {
    name     = "app-to-db-rules"
    priority = 110
    action   = "Allow"

    rule {
      name                  = "allow-sql-access"
      protocols             = ["TCP"]
      source_addresses      = ["10.1.1.0/24"]
      destination_addresses = ["10.2.1.0/24"]
      destination_ports     = ["1433"]
    }

    rule {
      name                  = "allow-icmp-internal"
      protocols             = ["ICMP"]
      source_addresses      = ["10.1.1.0/24"]
      destination_addresses = ["10.2.1.0/24"]
      destination_ports     = ["*"]
    }
  }
}

# ------------------------------------------------------------------------------------------------
#Rutas
resource "azurerm_route_table" "rt_spoke_a" {
  name                = "rt-spoke-a"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  route {
    name                   = "to-spoke-b-via-fw"
    address_prefix         = "10.2.0.0/16" # Destino: Spoke B
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.1.4"
  }
}

resource "azurerm_subnet_route_table_association" "assoc_spoke_a" {
  subnet_id      = azurerm_subnet.snet_workload.id
  route_table_id = azurerm_route_table.rt_spoke_a.id
}

resource "azurerm_route_table" "rt_spoke_b" {
  name                = "rt-spoke-b"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  route {
    name                   = "to-spoke-a-via-fw"
    address_prefix         = "10.1.0.0/16" # Destino: Spoke A
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.1.4"
  }
}

resource "azurerm_subnet_route_table_association" "assoc_spoke_b" {
  subnet_id      = azurerm_subnet.snet_db.id
  route_table_id = azurerm_route_table.rt_spoke_b.id
}

