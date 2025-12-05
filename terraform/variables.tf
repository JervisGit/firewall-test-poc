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
  description = "Name of the Synapse workspace to test blocking against"
  type        = string
  default     = "testsynapseworkspace001"
}
