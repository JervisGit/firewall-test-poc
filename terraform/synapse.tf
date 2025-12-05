# Storage Account for Synapse workspace
resource "azurerm_storage_account" "synapse" {
  name                     = "stsynapse${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Required for Data Lake Gen2

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    
    # Allow access from Synapse subnet
    virtual_network_subnet_ids = [
      azurerm_subnet.synapse.id
    ]
  }
}

# Storage container for Synapse
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse-filesystem"
  storage_account_id = azurerm_storage_account.synapse.id
}

# Subnet for Synapse workspace
resource "azurerm_subnet" "synapse" {
  name                 = "snet-synapse"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.101.2.0/24"]
}

# Synapse Workspace
resource "azurerm_synapse_workspace" "main" {
  name                                 = var.synapse_workspace_name
  resource_group_name                  = azurerm_resource_group.main.name
  location                             = azurerm_resource_group.main.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = "sqladmin"
  sql_administrator_login_password     = var.synapse_sql_admin_password
  
  # Managed VNet integration
  managed_virtual_network_enabled       = true
  managed_resource_group_name           = "${var.resource_group_name}-synapse-managed"
  public_network_access_enabled         = true
  data_exfiltration_protection_enabled  = false

  identity {
    type = "SystemAssigned"
  }

  tags = {
    purpose = "firewall-test-poc"
  }
}

# Grant Synapse workspace access to storage account
resource "azurerm_role_assignment" "synapse_storage_blob_contributor" {
  scope                = azurerm_storage_account.synapse.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Synapse Firewall Rule - Allow Azure services
resource "azurerm_synapse_firewall_rule" "allow_azure_services" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Synapse Firewall Rule - Allow VM subnet
resource "azurerm_synapse_firewall_rule" "allow_vm_subnet" {
  name                 = "AllowVMSubnet"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = "10.101.1.0"
  end_ip_address       = "10.101.1.255"
}

# Synapse Firewall Rule - Allow Firewall public IP
resource "azurerm_synapse_firewall_rule" "allow_firewall" {
  name                 = "AllowFirewallPublicIP"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = azurerm_public_ip.firewall.ip_address
  end_ip_address       = azurerm_public_ip.firewall.ip_address
}

# Apache Spark Pool
resource "azurerm_synapse_spark_pool" "main" {
  name                 = "sparkpool01"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"
  node_count           = 3

  auto_scale {
    max_node_count = 5
    min_node_count = 3
  }

  auto_pause {
    delay_in_minutes = 15
  }

  spark_version = "3.3"

  tags = {
    purpose = "firewall-test-poc"
  }
}

# Private endpoint for Synapse Dev endpoint
resource "azurerm_private_endpoint" "synapse_dev" {
  name                = "pe-synapse-dev"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.synapse.id

  private_service_connection {
    name                           = "psc-synapse-dev"
    private_connection_resource_id = azurerm_synapse_workspace.main.id
    is_manual_connection           = false
    subresource_names              = ["Dev"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-synapse"
    private_dns_zone_ids = [azurerm_private_dns_zone.synapse_dev.id]
  }
}

# Private DNS Zone for Synapse Dev endpoint
resource "azurerm_private_dns_zone" "synapse_dev" {
  name                = "privatelink.dev.azuresynapse.net"
  resource_group_name = azurerm_resource_group.main.name
}

# Link Private DNS Zone to Spoke VNet
resource "azurerm_private_dns_zone_virtual_network_link" "synapse_dev_spoke" {
  name                  = "pdz-link-synapse-spoke"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_dev.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
}

# Link Private DNS Zone to Hub VNet (so firewall can resolve)
resource "azurerm_private_dns_zone_virtual_network_link" "synapse_dev_hub" {
  name                  = "pdz-link-synapse-hub"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_dev.name
  virtual_network_id    = azurerm_virtual_network.hub.id
}

# Storage account private endpoint
resource "azurerm_private_endpoint" "storage_dfs" {
  name                = "pe-storage-dfs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.synapse.id

  private_service_connection {
    name                           = "psc-storage-dfs"
    private_connection_resource_id = azurerm_storage_account.synapse.id
    is_manual_connection           = false
    subresource_names              = ["dfs"]
  }
}
