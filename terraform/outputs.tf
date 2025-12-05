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

output "synapse_workspace_url" {
  description = "Synapse workspace URL"
  value       = "https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net"
}

output "synapse_workspace_name" {
  description = "Synapse workspace name"
  value       = azurerm_synapse_workspace.main.name
}

output "spark_pool_name" {
  description = "Spark pool name"
  value       = azurerm_synapse_spark_pool.main.name
}

output "storage_account_name" {
  description = "Storage account name for Synapse"
  value       = azurerm_storage_account.synapse.name
}

output "instructions" {
  description = "Next steps for testing"
  value       = <<-EOT
  
  ========================================
  DEPLOYMENT COMPLETE - TESTING INSTRUCTIONS
  ========================================
  
  IMPORTANT: Deployment takes 20-30 minutes (Synapse workspace is slow to provision)
  
  1. Connect to Test VM:
     - VM Name: ${azurerm_windows_virtual_machine.testvm.name}
     - Private IP: ${azurerm_network_interface.testvm.private_ip_address}
     - Use Azure Bastion or configure RDP access
  
  2. Install Firewall TLS Certificate on Test VM:
     - Download certificate from Key Vault: ${azurerm_key_vault.main.name}
     - Install as Trusted Root Certificate Authority
     - This allows the firewall to inspect HTTPS traffic
  
  3. Access Synapse Studio:
     - URL: https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net
     - Login with your Azure credentials
     - Navigate to Manage → Apache Spark pools
     - You should see: ${azurerm_synapse_spark_pool.main.name}
  
  4. Create and Run a Spark Application:
     - In Synapse Studio, go to Develop → New Notebook
     - Select Spark pool: ${azurerm_synapse_spark_pool.main.name}
     - Run simple code: 
       df = spark.range(1000)
       df.show()
     - This creates a Spark application that will appear in monitoring
  
  5. Test Application Rule Blocking:
     
     A. From VM browser, try to access Spark History:
        URL: https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net/sparkhistory/
        Expected: ❌ BLOCKED by firewall application rule
     
     B. Try to access Monitoring:
        URL: https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net/monitoring/workloadTypes/spark/
        Expected: ❌ BLOCKED by firewall application rule
     
     C. Access general Synapse (should work):
        URL: https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net/
        Expected: ✅ SUCCESS (only specific paths are blocked)
  
  6. Verify in Synapse Studio:
     - Navigate to Monitor → Apache Spark applications
     - You should NOT be able to view application details/logs
     - This proves the blocking is working at Layer 7
  
  7. Check Firewall Logs:
     - Go to Azure Portal → Firewall → Logs
     - Run query to see denied requests:
       AzureDiagnostics
       | where Category == "AzureFirewallApplicationRule"
       | where msg_s contains "sparkhistory" or msg_s contains "monitoring"
       | project TimeGenerated, Action, msg_s
  
  Key Concept Proven:
  ✅ Network rule (priority 300) allows all traffic on all ports
  ✅ Application rule (priority 410) blocks specific Synapse URLs with TLS inspection
  ✅ Application rules evaluated AFTER network rules (Layer 7 filtering)
  ✅ Users can access Synapse workspace but NOT view Spark logs/monitoring
  
  Cost Warning:
  - Synapse workspace: ~$0.50/hour
  - Spark pool (auto-paused): ~$0.10-0.20/hour when running
  - Firewall Premium: ~$1.25/hour
  - Total: ~$2/hour or ~$48/day
  
  Remember to run 'terraform destroy' when done testing!
  
  EOT
}
