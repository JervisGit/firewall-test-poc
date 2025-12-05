variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-firewall-test-poc"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "test_vm_admin_username" {
  description = "Admin username for test VM"
  type        = string
  default     = "azureadmin"
}

variable "test_vm_admin_password" {
  description = "Admin password for test VM (use strong password)"
  type        = string
  sensitive   = true
}

variable "synapse_workspace_name" {
  description = "Name of the Synapse workspace (must be globally unique, 3-50 chars, alphanumeric)"
  type        = string
  default     = "syn-fw-test-001"
}

variable "synapse_sql_admin_password" {
  description = "SQL admin password for Synapse workspace (use strong password)"
  type        = string
  sensitive   = true
}
