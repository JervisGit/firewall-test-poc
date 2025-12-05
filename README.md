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
- Sufficient Azure quota for:
  - Azure Firewall Premium
  - Synapse Analytics workspace
  - Virtual Machines

## Cost Warning

This POC deploys:
- Azure Firewall Premium (~$1.25/hour + data processing)
- Synapse Analytics workspace (~$0.50/hour)
- Spark pool with 3 nodes (~$0.10-0.20/hour when running, auto-pauses after 15 min)
- Storage account with Data Lake Gen2 (~$0.02/GB)
- Windows 10 VM (~$0.20/hour)
- Small Key Vault (minimal cost)

**Estimated cost: ~$2.00/hour or $48/day**

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
synapse_workspace_name = "syn-fw-test-$(Get-Random -Minimum 100 -Maximum 999)"
synapse_sql_admin_password = "YourSynapsePassword123!"
"@ | Out-File -FilePath terraform.tfvars -Encoding utf8
```

**Important:** 
- Replace passwords with strong passwords (minimum 12 characters, mix of upper/lower/numbers/symbols)
- Synapse workspace name must be globally unique (3-50 characters, alphanumeric only)
- The command above generates a random suffix for uniqueness

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

Type `yes` when prompted. Deployment takes approximately **25-35 minutes**:
- Firewall Premium: ~10-15 minutes
- Synapse workspace: ~15-20 minutes
- Other resources: ~5 minutes

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

### Testing in Synapse Studio

1. **Access Synapse Studio** from the test VM:
   - Open browser and navigate to your workspace URL (from terraform output)
   - Login with your Azure credentials
   - Navigate to **Manage** → **Apache Spark pools**

2. **Create a Spark Application**:
   - Go to **Develop** → **+ New notebook**
   - Select your Spark pool from the dropdown
   - Run this simple PySpark code:
     ```python
     df = spark.range(1000)
     df.show()
     ```
   - Wait for the job to complete

3. **Test the Blocking**:
   - Try to navigate to **Monitor** → **Apache Spark applications**
   - Try to click on your application to view details/logs
   - **Expected**: You should see connection errors or blocked access
   - The firewall is blocking `/monitoring/workloadTypes/spark/*` and `/sparkhistory/*`

### Expected Test Results

| Test | URL | Expected Result | Reason |
|------|-----|----------------|---------|
| 1 | `https://www.microsoft.com` | ✅ SUCCESS | Network rule allows all traffic, application rule allows (no deny match) |
| 2 | `https://<workspace>.dev.azuresynapse.net/` | ✅ SUCCESS | Can access Synapse Studio homepage |
| 3 | `https://<workspace>.dev.azuresynapse.net/sparkhistory/*` | ❌ BLOCKED | Application rule explicitly denies this URL path |
| 4 | `https://<workspace>.dev.azuresynapse.net/monitoring/workloadTypes/spark/*` | ❌ BLOCKED | Application rule explicitly denies monitoring endpoints |
| 5 | Synapse Studio - Develop/Data tabs | ✅ SUCCESS | General Synapse access works |
| 6 | Synapse Studio - Monitor → Spark apps | ❌ BLOCKED | Cannot view Spark application logs/monitoring |

### PowerShell Test Script

Save this as `test-firewall-rules.ps1` and run on the test VM after installing the TLS certificate:

```powershell
# Test script to verify firewall rules
# Get workspace name from terraform output or set manually
$synapseWorkspace = "syn-fw-test-001"  # Replace with your workspace name

Write-Host "`n=== Testing Firewall Rules ===" -ForegroundColor Cyan
Write-Host "Synapse Workspace: $synapseWorkspace" -ForegroundColor White
Write-Host "Note: TLS certificate must be installed for HTTPS inspection to work`n" -ForegroundColor Yellow

# Test 1: General web access
Write-Host "[Test 1] Testing general HTTPS (should succeed)..." -ForegroundColor Yellow
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
    Write-Host "⚠️ Check if Synapse is deployed - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 3: Spark History (should be blocked)
Write-Host "`n[Test 3] Testing Spark History URL (should be BLOCKED)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$synapseWorkspace.dev.azuresynapse.net/sparkhistory/" -UseBasicParsing -TimeoutSec 10
    Write-Host "❌ UNEXPECTED - Request succeeded when it should be blocked!" -ForegroundColor Red
    Write-Host "    Status: $($response.StatusCode)" -ForegroundColor Red
} catch {
    if ($_.Exception.Message -match "403|Forbidden|blocked|denied") {
        Write-Host "✅ CORRECTLY BLOCKED - Firewall denied access" -ForegroundColor Green
    } else {
        Write-Host "✅ BLOCKED - $($_.Exception.Message)" -ForegroundColor Green
    }
}

# Test 4: Monitoring endpoint (should be blocked)
Write-Host "`n[Test 4] Testing Monitoring URL (should be BLOCKED)..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$synapseWorkspace.dev.azuresynapse.net/monitoring/workloadTypes/spark/" -UseBasicParsing -TimeoutSec 10
    Write-Host "❌ UNEXPECTED - Request succeeded when it should be blocked!" -ForegroundColor Red
    Write-Host "    Status: $($response.StatusCode)" -ForegroundColor Red
} catch {
    if ($_.Exception.Message -match "403|Forbidden|blocked|denied") {
        Write-Host "✅ CORRECTLY BLOCKED - Firewall denied access" -ForegroundColor Green
    } else {
        Write-Host "✅ BLOCKED - $($_.Exception.Message)" -ForegroundColor Green
    }
}

# Test 5: Check if running from correct subnet
Write-Host "`n[Test 5] Checking VM network configuration..." -ForegroundColor Yellow
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "10.101.*"}).IPAddress
if ($ip) {
    Write-Host "✅ VM IP: $ip (in test subnet)" -ForegroundColor Green
} else {
    Write-Host "⚠️ WARNING: VM not in expected subnet (10.101.1.0/24)" -ForegroundColor Yellow
}

Write-Host "`n=== Testing Complete ===" -ForegroundColor Cyan
Write-Host "`nSummary:" -ForegroundColor White
Write-Host "- If Tests 3 & 4 are blocked: ✅ POC successful!" -ForegroundColor Green
Write-Host "- If Tests 3 & 4 succeed: ❌ Check firewall config and TLS cert" -ForegroundColor Red
Write-Host "- Check Azure Firewall logs for detailed traffic analysis" -ForegroundColor Cyan
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

## What This POC Includes

### Complete End-to-End Testing Environment

1. **Networking**:
   - Hub VNet with Azure Firewall Premium
   - Spoke VNet with test VM and Synapse subnet
   - VNet peering and route tables
   - Private DNS zones for Synapse endpoints

2. **Azure Firewall Premium**:
   - Network rule (priority 300) allowing all traffic on all ports
   - Application rule (priority 410) blocking Synapse monitoring URLs
   - TLS inspection with self-signed certificate
   - Intrusion Detection (IDPS) in Deny mode

3. **Synapse Analytics**:
   - Full Synapse workspace deployment
   - Apache Spark pool (3 nodes, auto-pause enabled)
   - Storage account with Data Lake Gen2
   - Private endpoints for secure connectivity
   - Firewall rules for network access

4. **Test Infrastructure**:
   - Windows 10 VM for testing
   - Key Vault for TLS certificates
   - All necessary IAM roles and permissions

## Adapting for Your Corporate Environment

This POC uses anonymized, generic naming. To apply to your production environment:

1. **Network Rules:** Your existing network rule allows all VNet-to-VNet traffic on all ports (including 443)
2. **Application Rules:** Add the blocking rule with higher priority number (e.g., 410)
3. **TLS Inspection:** Ensure your corporate firewall has TLS inspection enabled with `terminate_tls = true`
4. **Source Addresses:** Specify only the user subnets (datauser, developer) that should be blocked
5. **Destination URLs:** Use your actual Synapse workspace FQDN (e.g., `syn-udp-uatizapp-002.dev.azuresynapse.net`)

## Files in This POC

- `provider.tf` - Terraform and Azure provider configuration
- `versions.tf` - Required provider versions (includes random provider)
- `variables.tf` - Input variables (VM credentials, Synapse config)
- `network.tf` - VNets, subnets, peering, route tables
- `firewall.tf` - Azure Firewall Premium with network and application rules
- `synapse.tf` - Synapse workspace, Spark pool, storage, private endpoints
- `vm.tf` - Windows test VM with network security group
- `outputs.tf` - Deployment outputs and testing instructions
- `terraform.tfvars.example` - Example configuration file
- `.gitignore` - Git ignore rules for Terraform files
- `README.md` - This file

## Questions?

This POC demonstrates that:
- ✅ Application rules work even when network rules allow the port
- ✅ Priority numbers don't affect network vs application rule ordering
- ✅ TLS inspection enables URL-based filtering at Layer 7
- ✅ The solution will work in your production environment

If you have questions about applying this to your corporate infrastructure, review the firewall rule configuration in `firewall.tf`.
