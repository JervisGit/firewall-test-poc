# Public IP for Azure Firewall
resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Firewall Policy
resource "azurerm_firewall_policy" "main" {
  name                = "fwpol-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Premium"

  # Enable TLS Inspection
  tls_certificate {
    key_vault_secret_id = azurerm_key_vault_certificate.firewall_cert.secret_id
    name                = "firewall-tls-cert"
  }

  # Match production configuration
  dns {
    proxy_enabled = false
    servers       = []
  }

  private_ip_ranges = ["0.0.0.0/0"]

  intrusion_detection {
    mode = "Deny"  # Match production (was "Alert")
  }
}

# Key Vault for storing TLS certificate
resource "azurerm_key_vault" "main" {
  name                       = "kv-fw-test-${random_string.unique.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = [
      "Create",
      "Delete",
      "Get",
      "Import",
      "List",
      "Purge",
      "Update"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
  }

  # Access policy for Firewall managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.firewall.principal_id

    certificate_permissions = [
      "Get",
      "List"
    ]

    secret_permissions = [
      "Get",
      "List"
    ]
  }
}

# Self-signed certificate for TLS inspection (for testing only)
resource "azurerm_key_vault_certificate" "firewall_cert" {
  name         = "firewall-tls-cert"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=FirewallTestCA"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = ["*.azuresynapse.net"]
      }
    }
  }
}

# User Assigned Managed Identity for Firewall
resource "azurerm_user_assigned_identity" "firewall" {
  name                = "id-firewall-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Random string for unique Key Vault name
resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

# Azure Firewall Premium
resource "azurerm_firewall" "main" {
  name                = "fw-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.main.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

# Firewall Policy Rule Collection Group
resource "azurerm_firewall_policy_rule_collection_group" "main" {
  name               = "rcg-test-rules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 500  # Match production priority

  # Network Rule Collection - Allow all traffic on port 443 (simulating your network rule)
  network_rule_collection {
    name     = "network-allow-443"
    priority = 300
    action   = "Allow"

    # Simulating production's "cpp_udp_vnets--udp_vnets_any" rule
    rule {
      name                  = "allow-all-https"
      protocols             = ["Any"]  # Match production (was "TCP")
      source_addresses      = ["10.101.1.0/24"] # VM subnet
      destination_addresses = ["*"]
      destination_ports     = ["*"]  # Match production (was "443")
    }
  }

  # Application Rule Collection - Block specific Synapse URLs
  application_rule_collection {
    name     = "app-block-synapse-monitoring"
    priority = 410
    action   = "Deny"

    rule {
      name = "block-spark-history"
      
      protocols {
        type = "Https"
        port = 443
      }

      source_addresses = ["10.101.1.0/24"] # VM subnet

      # Replace with your actual Synapse workspace URL
      destination_urls = [
        "${var.synapse_workspace_name}.dev.azuresynapse.net/sparkhistory/*",
        "${var.synapse_workspace_name}.dev.azuresynapse.net/monitoring/workloadTypes/spark/*"
      ]

      terminate_tls = true
    }
  }

  # Application Rule Collection - Allow general internet access
  application_rule_collection {
    name     = "app-allow-internet"
    priority = 500
    action   = "Allow"

    rule {
      name = "allow-web-browsing"
      
      protocols {
        type = "Https"
        port = 443
      }

      protocols {
        type = "Http"
        port = 80
      }

      source_addresses      = ["10.101.1.0/24"]
      destination_fqdn_tags = ["WindowsUpdate"]
      destination_fqdns     = ["*.microsoft.com", "*.azure.com", "*.azuresynapse.net"]
    }
  }
}

# Data source for current Azure client config
data "azurerm_client_config" "current" {}
