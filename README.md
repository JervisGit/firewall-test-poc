# Azure Firewall TLS Inspection Test POC

## Overview

This proof-of-concept demonstrates that **Azure Firewall Premium application rules with TLS inspection can block specific URLs even when network rules allow the traffic on port 443**.

### What This Proves

- ✅ Network rules (Layer 4) are evaluated first and allow port 443 traffic
- ✅ Application rules (Layer 7) are evaluated second with TLS inspection
- ✅ Application rules can block specific URL paths while allowing other traffic on the same port
- ✅ Lower priority numbers in application rules don't make them evaluate before network rules

### Architecture

```
Test VM (10.101.1.0/24)
    ↓
Route Table → Forces traffic to Firewall
    ↓
Azure Firewall Premium (10.100.1.4)
    ├─ Network Rule (Priority 300): Allow all port 443
    └─ Application Rule (Priority 410): Block specific Synapse URLs with TLS inspection
    ↓
Internet / Synapse Workspace
```

## Prerequisites

- Azure subscription with permissions to create resources
- Azure CLI or PowerShell installed
- Terraform >= 1.0
- Synapse workspace to test against (or update variables to test with any HTTPS endpoint)

## Cost Warning

This POC deploys:
- Azure Firewall Premium (~$1.25/hour + data processing)
- Windows 10 VM (~$0.20/hour)
- Small Key Vault (minimal cost)

**Estimated cost: ~$1.50/hour or $35/day**

⚠️ **Remember to destroy resources after testing!**

## Deployment Steps

### 1. Clone or Navigate to POC Directory

```powershell
cd c:\Users\INLJLAA\Downloads\infra\firewall-test-poc\terraform
```

### 2. Create terraform.tfvars File

```powershell
@"
resource_group_name = "rg-firewall-test-poc"
location = "eastus"
test_vm_admin_username = "azureadmin"
test_vm_admin_password = "YourStrongPassword123!"
synapse_workspace_name = "your-synapse-workspace-name"
"@ | Out-File -FilePath terraform.tfvars -Encoding utf8
```

**Important:** 
- Replace `YourStrongPassword123!` with a strong password
- Replace `your-synapse-workspace-name` with your actual Synapse workspace name
- Or use any HTTPS endpoint for testing (edit `firewall.tf` destination URLs)

### 3. Initialize Terraform

```powershell
terraform init
```

### 4. Review Deployment Plan

```powershell
terraform plan
```

### 5. Deploy Resources

```powershell
terraform apply
```

Type `yes` when prompted. Deployment takes approximately **15-20 minutes** (firewall takes longest).

### 6. Save Outputs

After deployment completes, save the output information:

```powershell
terraform output
```

## Testing Steps

### Option A: Test from Azure Portal (Cloud Shell)

1. Open Azure Portal → Resource Group → Find your test VM
2. Click **Connect** → **Bastion** (or use serial console)
3. Login with credentials from terraform.tfvars

### Option B: Test via PowerShell Commands

You can test the firewall rules using Azure Run Command without RDP:

```powershell
# Get VM name from Terraform output
$vmName = "vm-test-win"
$rgName = "rg-firewall-test-poc"

# Test 1: General HTTPS should work (network rule allows 443)
az vm run-command invoke --name $vmName --resource-group $rgName --command-id RunPowerShellScript --scripts "Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing"

# Test 2: Blocked Synapse URL (application rule blocks)
az vm run-command invoke --name $vmName --resource-group $rgName --command-id RunPowerShellScript --scripts "Invoke-WebRequest -Uri 'https://your-synapse-workspace.dev.azuresynapse.net/sparkhistory/' -UseBasicParsing"
```

### Install TLS Certificate (Required for HTTPS Inspection)

For the firewall to inspect HTTPS traffic, the test VM needs to trust the firewall's TLS certificate:

1. Download certificate from Key Vault:
   ```powershell
   az keyvault certificate download --vault-name <key-vault-name> --name firewall-tls-cert --file firewall-cert.cer --encoding DER
   ```

2. On the test VM, install certificate:
   ```powershell
   Import-Certificate -FilePath "firewall-cert.cer" -CertStoreLocation Cert:\LocalMachine\Root
   ```

### Expected Test Results

| Test | URL | Expected Result | Reason |
|------|-----|----------------|---------|
| 1 | `https://www.microsoft.com` | ✅ SUCCESS | Network rule allows 443, application rule allows (no deny match) |
| 2 | `https://<workspace>.dev.azuresynapse.net/` | ✅ SUCCESS | Network rule allows 443, application rule allows (no deny match) |
| 3 | `https://<workspace>.dev.azuresynapse.net/sparkhistory/` | ❌ BLOCKED | Application rule explicitly denies this URL path |
| 4 | `https://<workspace>.dev.azuresynapse.net/monitoring/workloadTypes/spark/` | ❌ BLOCKED | Application rule explicitly denies this URL path |

### PowerShell Test Script

Save this as `test-firewall-rules.ps1` and run on the test VM:

```powershell
# Test script to verify firewall rules
$synapseWorkspace = "your-synapse-workspace-name"

Write-Host "`n=== Testing Firewall Rules ===" -ForegroundColor Cyan

# Test 1: General web access
Write-Host "`n[Test 1] Testing general HTTPS (should succeed)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10
    Write-Host "✅ SUCCESS - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Synapse base URL
Write-Host "`n[Test 2] Testing Synapse base URL (should succeed)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$synapseWorkspace.dev.azuresynapse.net/" -UseBasicParsing -TimeoutSec 10
    Write-Host "✅ SUCCESS - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "⚠️ EXPECTED ERROR - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 3: Spark History (should be blocked)
Write-Host "`n[Test 3] Testing Spark History URL (should be BLOCKED)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$synapseWorkspace.dev.azuresynapse.net/sparkhistory/" -UseBasicParsing -TimeoutSec 10
    Write-Host "❌ UNEXPECTED - Request succeeded when it should be blocked!" -ForegroundColor Red
} catch {
    Write-Host "✅ CORRECTLY BLOCKED - $($_.Exception.Message)" -ForegroundColor Green
}

# Test 4: Monitoring endpoint (should be blocked)
Write-Host "`n[Test 4] Testing Monitoring URL (should be BLOCKED)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$synapseWorkspace.dev.azuresynapse.net/monitoring/workloadTypes/spark/" -UseBasicParsing -TimeoutSec 10
    Write-Host "❌ UNEXPECTED - Request succeeded when it should be blocked!" -ForegroundColor Red
} catch {
    Write-Host "✅ CORRECTLY BLOCKED - $($_.Exception.Message)" -ForegroundColor Green
}

Write-Host "`n=== Testing Complete ===" -ForegroundColor Cyan
```

## Verification in Azure Portal

### Check Firewall Logs

1. Navigate to Azure Portal → Your Firewall → **Logs**
2. Run this KQL query:

```kql
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s, Action
| order by TimeGenerated desc
```

You should see:
- ✅ Allow actions for general HTTPS traffic
- ❌ Deny actions for sparkhistory and monitoring URLs

### Check Firewall Rules

1. Navigate to **Firewall Policy** → **Rule Collection Groups**
2. Verify:
   - Network rule collection `network-allow-443` (Priority 300) - Action: Allow
   - Application rule collection `app-block-synapse-monitoring` (Priority 410) - Action: Deny
   - Application rule has `terminate_tls = true` enabled

## Key Concepts Demonstrated

### Rule Processing Order

```
1. Network Rules (Layer 4) - Priority 300
   └─ Allow TCP/443 from VM subnet to anywhere
      ↓ (Traffic passes Layer 4 check)
   
2. TLS Inspection (Layer 7)
   └─ Firewall terminates TLS connection
   └─ Inspects HTTP request including URL path
      ↓
   
3. Application Rules (Layer 7) - Priority 410
   └─ Deny requests matching:
      - *.azuresynapse.net/sparkhistory/*
      - *.azuresynapse.net/monitoring/workloadTypes/spark/*
```

### Why Application Rule Priority Doesn't Matter vs Network Rules

- Network rules and application rules are **separate evaluation stages**
- Network rules always evaluated first (Layer 4 - port/protocol)
- Application rules always evaluated second (Layer 7 - URLs/FQDNs)
- Priority only matters **within the same rule type**
- Application rule priority 100 or 410 doesn't change evaluation order

## Troubleshooting

### Issue: Application rule not blocking traffic

**Solution:** Ensure TLS certificate is installed on test VM. Without it, browser won't trust the firewall's TLS interception.

### Issue: All traffic blocked

**Solution:** Check route table is correctly forcing traffic through firewall, and network rule is configured correctly.

### Issue: Can't RDP to VM

**Solution:** Use Azure Bastion or Serial Console. Or modify NSG to allow RDP from your specific public IP.

### Issue: Firewall deployment fails

**Solution:** Ensure you have sufficient quota for Premium Firewall in your region. Try a different region.

## Cleanup

**IMPORTANT:** Destroy resources to avoid ongoing charges:

```powershell
terraform destroy
```

Type `yes` when prompted.

Verify in Azure Portal that resource group is deleted.

## Adapting for Your Corporate Environment

This POC uses anonymized, generic naming. To apply to your production environment:

1. **Network Rules:** Your existing network rule allows all VNet-to-VNet traffic on all ports (including 443)
2. **Application Rules:** Add the blocking rule with higher priority number (e.g., 410)
3. **TLS Inspection:** Ensure your corporate firewall has TLS inspection enabled with `terminate_tls = true`
4. **Source Addresses:** Specify only the user subnets (datauser, developer) that should be blocked
5. **Destination URLs:** Use your actual Synapse workspace FQDN

## Files in This POC

- `provider.tf` - Terraform and Azure provider configuration
- `variables.tf` - Input variables
- `network.tf` - VNets, subnets, peering, route tables
- `firewall.tf` - Azure Firewall Premium with network and application rules
- `vm.tf` - Windows test VM
- `outputs.tf` - Deployment outputs and testing instructions
- `README.md` - This file

## Questions?

This POC demonstrates that:
- ✅ Application rules work even when network rules allow the port
- ✅ Priority numbers don't affect network vs application rule ordering
- ✅ TLS inspection enables URL-based filtering at Layer 7
- ✅ The solution will work in your production environment

If you have questions about applying this to your corporate infrastructure, review the firewall rule configuration in `firewall.tf`.
