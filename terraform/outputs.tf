output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "firewall_private_ip" {
  description = "Private IP of Azure Firewall"
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

output "test_vm_private_ip" {
  description = "Private IP of test VM"
  value       = azurerm_network_interface.testvm.private_ip_address
}

output "test_vm_name" {
  description = "Name of test VM"
  value       = azurerm_windows_virtual_machine.testvm.name
}

output "key_vault_name" {
  description = "Key Vault name containing TLS certificate"
  value       = azurerm_key_vault.main.name
}

output "firewall_public_ip" {
  description = "Public IP of Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "instructions" {
  description = "Next steps for testing"
  value       = <<-EOT
  
  ========================================
  DEPLOYMENT COMPLETE - TESTING INSTRUCTIONS
  ========================================
  
  1. Connect to Test VM:
     - VM Name: ${azurerm_windows_virtual_machine.testvm.name}
     - Private IP: ${azurerm_network_interface.testvm.private_ip_address}
     - Use Azure Bastion or configure RDP via Firewall
  
  2. Install Firewall TLS Certificate on Test VM:
     - Download certificate from Key Vault: ${azurerm_key_vault.main.name}
     - Install as Trusted Root Certificate Authority
     - This allows the firewall to inspect HTTPS traffic
  
  3. Test Network Rule (allows 443):
     - From VM, try: curl https://www.microsoft.com
     - Expected: SUCCESS (network rule allows port 443)
  
  4. Test Application Rule (blocks Synapse URLs):
     - From VM, try: curl https://${var.synapse_workspace_name}.dev.azuresynapse.net/sparkhistory/
     - Expected: BLOCKED by application rule
     - Try: curl https://${var.synapse_workspace_name}.dev.azuresynapse.net/monitoring/workloadTypes/spark/
     - Expected: BLOCKED by application rule
  
  5. Test Other Synapse Access (should work):
     - From VM, try: curl https://${var.synapse_workspace_name}.dev.azuresynapse.net/
     - Expected: SUCCESS (only specific paths are blocked)
  
  Key Concept Proven:
  - Network rule at priority 300 allows all port 443 traffic
  - Application rule at priority 410 blocks specific URLs with TLS inspection
  - Application rules are evaluated AFTER network rules
  - TLS inspection enables Layer 7 (URL path) filtering
  
  EOT
}
