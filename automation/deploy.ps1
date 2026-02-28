#!/usr/bin/env pwsh
# ============================================================================
# Zero-Copy RAG Workshop — Automated Deployment Orchestrator
#
# This script deploys the entire ANF → OneLake → AI Search → AI Foundry
# pipeline automatically. After completion, open AI Foundry and start chatting.
#
# Prerequisites:
#   - Azure CLI (az) installed and logged in
#   - PowerShell 7+
#   - AWS CLI (for S3 data upload)
#   - openssl (for certificate generation, if not providing one)
#   - Service Principal with Fabric permissions
#   - Fabric capacity (Trial or paid)
#
# Usage:
#   ./deploy.ps1 -SubscriptionId "xxx" -Location "eastus2" ...
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'Azure Subscription ID')]
    [string]$SubscriptionId,

    [Parameter(Mandatory, HelpMessage = 'Azure region (must support GPT-4o, e.g., eastus2, swedencentral, westus3)')]
    [string]$Location,

    [Parameter(HelpMessage = 'Resource group name')]
    [string]$ResourceGroupName = 'rg-rag-workshop',

    [Parameter(HelpMessage = 'Resource name prefix (lowercase, 3-15 chars)')]
    [ValidatePattern('^[a-z][a-z0-9-]{2,14}$')]
    [string]$Prefix = 'ragworkshop',

    [Parameter(Mandatory, HelpMessage = 'Password for the gateway VM admin user')]
    [SecureString]$VmAdminPassword,

    [Parameter(HelpMessage = 'Username for the gateway VM admin')]
    [string]$VmAdminUsername = 'azureuser',

    [Parameter(Mandatory, HelpMessage = 'Your Azure AD user Object ID (az ad signed-in-user show --query id -o tsv)')]
    [string]$UserObjectId,

    [Parameter(Mandatory, HelpMessage = 'Service Principal App/Client ID (for Fabric + Gateway)')]
    [string]$ServicePrincipalAppId,

    [Parameter(Mandatory, HelpMessage = 'Service Principal client secret')]
    [string]$ServicePrincipalSecret,

    [Parameter(Mandatory, HelpMessage = 'Azure AD Tenant ID')]
    [string]$TenantId,

    [Parameter(Mandatory, HelpMessage = 'Microsoft Fabric capacity ID')]
    [string]$FabricCapacityId,

    [Parameter(HelpMessage = 'Path to TLS certificate PEM file (auto-generated if not provided)')]
    [string]$CertificatePath,

    [Parameter(HelpMessage = 'Skip infrastructure deployment (use if Bicep already deployed)')]
    [switch]$SkipInfrastructure,

    [Parameter(HelpMessage = 'Skip Fabric configuration (use if Fabric already configured)')]
    [switch]$SkipFabric
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# ============================================================================
# Banner
# ============================================================================
Write-Host @"

  ╔══════════════════════════════════════════════════════════════════╗
  ║   Zero-Copy RAG Workshop — Automated Deployment                ║
  ║   ANF → OneLake → AI Search → AI Foundry                      ║
  ╚══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# Validate Prerequisites
# ============================================================================
Write-Host "=== Validating Prerequisites ===" -ForegroundColor Cyan

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
    exit 1
}

# Check AWS CLI (for S3 upload)
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Warning "AWS CLI not found. Data upload step will be skipped. Install from https://aws.amazon.com/cli/"
}

# Set subscription
az account set --subscription $SubscriptionId
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Green
Write-Host "  Location: $Location" -ForegroundColor Green
Write-Host "  Prefix: $Prefix" -ForegroundColor Green

# ============================================================================
# Step 1: Register Resource Providers
# ============================================================================
& "$scriptRoot/scripts/01-register-providers.ps1" -SubscriptionId $SubscriptionId

# ============================================================================
# Step 2: Deploy Azure Infrastructure (Bicep)
# ============================================================================
if (-not $SkipInfrastructure) {
    Write-Host "`n=== Step 2: Deploying Azure Infrastructure (Bicep) ===" -ForegroundColor Cyan

    # Create resource group
    Write-Host "  Creating resource group '$ResourceGroupName'..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none

    # Convert SecureString to plain text for Bicep parameter
    $vmPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($VmAdminPassword)
    )

    # Deploy Bicep
    Write-Host "  Deploying Bicep template (this may take 15-20 minutes)..." -ForegroundColor Yellow
    $deployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "$scriptRoot/main.bicep" `
        --parameters `
            location=$Location `
            prefix=$Prefix `
            vmAdminUsername=$VmAdminUsername `
            vmAdminPassword=$vmPasswordPlain `
            userObjectId=$UserObjectId `
        --query 'properties.outputs' `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bicep deployment failed. Check the Azure portal for details."
        exit 1
    }

    Write-Host "  Infrastructure deployed successfully." -ForegroundColor Green

    # Extract outputs
    $netappAccountName = $deployment.netappAccountName.value
    $anfVolumeName = $deployment.anfVolumeName.value
    $anfPoolName = $deployment.anfCapacityPoolName.value
    $gatewayVmName = $deployment.gatewayVmName.value
    $searchServiceName = $deployment.searchServiceName.value
    $searchEndpoint = $deployment.searchServiceEndpoint.value
    $searchPrincipalId = $deployment.searchServicePrincipalId.value
    $aiServicesName = $deployment.aiServicesName.value
    $aiServicesEndpoint = $deployment.aiServicesEndpoint.value
    $aiHubName = $deployment.aiHubName.value
    $aiProjectName = $deployment.aiProjectName.value
} else {
    Write-Host "`n=== Skipping infrastructure deployment (--SkipInfrastructure) ===" -ForegroundColor Yellow
    # User must provide these values
    $netappAccountName = "${Prefix}-netapp"
    $anfVolumeName = 'anf-finance-vol'
    $anfPoolName = "${Prefix}-pool"
    $searchServiceName = "${Prefix}-search"
    $searchEndpoint = "https://${Prefix}-search.search.windows.net"
    $aiServicesName = "${Prefix}-ai-services"
    $aiServicesEndpoint = "https://${Prefix}-ai-services.cognitiveservices.azure.com"
    $aiProjectName = "${Prefix}-project"
}

# ============================================================================
# Step 3: Configure ANF Object Bucket
# ============================================================================
$bucketResult = & "$scriptRoot/scripts/02-configure-anf-bucket.ps1" `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -NetAppAccountName $netappAccountName `
    -CapacityPoolName $anfPoolName `
    -VolumeName $anfVolumeName `
    -CertificatePath $CertificatePath

$anfEndpoint = $bucketResult.Endpoint
$anfAccessKey = $bucketResult.AccessKey
$anfSecretKey = $bucketResult.SecretKey
$bucketName = $bucketResult.BucketName

# ============================================================================
# Step 4: Upload Test Data
# ============================================================================
if (Get-Command aws -ErrorAction SilentlyContinue) {
    & "$scriptRoot/scripts/03-upload-data.ps1" `
        -Endpoint $anfEndpoint `
        -AccessKey $anfAccessKey `
        -SecretKey $anfSecretKey `
        -BucketName $bucketName
} else {
    Write-Warning "Skipping data upload (AWS CLI not found). Upload test_data/ manually."
}

# ============================================================================
# Step 5: Install Data Gateway on VM (via Custom Script Extension)
# ============================================================================
Write-Host "`n=== Step 5: Installing Data Gateway on VM ===" -ForegroundColor Cyan

$certContent = ''
if ($bucketResult.CertPath -and (Test-Path $bucketResult.CertPath)) {
    $certContent = (Get-Content $bucketResult.CertPath -Raw) -replace '"', '\"'
}

$gwScriptUri = 'https://raw.githubusercontent.com/DwirefS/ANF-OneLake-AIFoundry/main/automation/scripts/gateway/install-gateway.ps1'

# For local execution, use the local script
$gwScriptContent = Get-Content "$scriptRoot/scripts/gateway/install-gateway.ps1" -Raw
$encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($gwScriptContent))

Write-Host "  Running gateway installation on VM '$gatewayVmName'..." -ForegroundColor Yellow
Write-Host "  (This installs the gateway software and registers it. May take 5-10 minutes.)" -ForegroundColor Gray

az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $gatewayVmName `
    --command-id RunPowerShellScript `
    --scripts "
        `$decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedScript'))
        `$decoded | Out-File -FilePath C:\install-gateway.ps1 -Encoding utf8
        powershell -ExecutionPolicy Bypass -File C:\install-gateway.ps1 ``
            -ServicePrincipalAppId '$ServicePrincipalAppId' ``
            -ServicePrincipalSecret '$ServicePrincipalSecret' ``
            -TenantId '$TenantId' ``
            -RegionKey '$Location'
    " --output none

Write-Host "  Gateway installation initiated." -ForegroundColor Green

# Wait for gateway to register
Write-Host "  Waiting 30 seconds for gateway registration to complete..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# ============================================================================
# Step 6: Configure Microsoft Fabric
# ============================================================================
if (-not $SkipFabric) {
    $fabricResult = & "$scriptRoot/scripts/04-configure-fabric.ps1" `
        -TenantId $TenantId `
        -ServicePrincipalAppId $ServicePrincipalAppId `
        -ServicePrincipalSecret $ServicePrincipalSecret `
        -FabricCapacityId $FabricCapacityId `
        -AnfEndpoint $anfEndpoint `
        -AnfAccessKey $anfAccessKey `
        -AnfSecretKey $anfSecretKey `
        -BucketName $bucketName

    $fabricWorkspaceId = $fabricResult.WorkspaceId
    $fabricLakehouseId = $fabricResult.LakehouseId
} else {
    Write-Host "`n=== Skipping Fabric configuration (--SkipFabric) ===" -ForegroundColor Yellow
    $fabricWorkspaceId = Read-Host "Enter Fabric Workspace ID"
    $fabricLakehouseId = Read-Host "Enter Fabric Lakehouse ID"
}

# ============================================================================
# Step 7: Configure Azure AI Search
# ============================================================================

# Get search admin key
$searchAdminKey = az search admin-key show `
    --resource-group $ResourceGroupName `
    --service-name $searchServiceName `
    --query primaryKey -o tsv

# Get AI Services key
$aiServicesKey = az cognitiveservices account keys list `
    --resource-group $ResourceGroupName `
    --name $aiServicesName `
    --query key1 -o tsv

$searchResult = & "$scriptRoot/scripts/05-configure-ai-search.ps1" `
    -SearchServiceEndpoint $searchEndpoint `
    -SearchAdminKey $searchAdminKey `
    -FabricWorkspaceId $fabricWorkspaceId `
    -LakehouseId $fabricLakehouseId `
    -AiServicesEndpoint $aiServicesEndpoint `
    -AiServicesKey $aiServicesKey

$indexName = $searchResult.IndexName

# ============================================================================
# Step 8: Create AI Foundry Agent
# ============================================================================
$agentResult = & "$scriptRoot/scripts/06-configure-agent.ps1" `
    -AiServicesName $aiServicesName `
    -ProjectName $aiProjectName `
    -IndexName $indexName `
    -SearchServiceName $searchServiceName `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName

# ============================================================================
# Deployment Complete
# ============================================================================
Write-Host @"

  ╔══════════════════════════════════════════════════════════════════╗
  ║   DEPLOYMENT COMPLETE                                          ║
  ╚══════════════════════════════════════════════════════════════════╝

  Your Zero-Copy RAG pipeline is deployed and ready!

  What was created:
    - Azure NetApp Files volume with Object REST API bucket
    - On-Premises Data Gateway VM
    - Microsoft Fabric workspace with OneLake shortcut
    - Azure AI Search with vectorized index
    - Azure AI Foundry Hub + Project
    - AI Agent grounded on your enterprise data

  Next Steps:
    1. Open Azure AI Foundry: https://ai.azure.com
    2. Navigate to project '$aiProjectName'
    3. Go to Agents and select '$($agentResult.AgentName)'
    4. Start chatting! Try:
       - "What is the total spend for vendor OfficeMax?"
       - "Show me all transactions from Q1 2025"
       - "List all invoices over $1000"

  Agent ID: $($agentResult.AgentId)

"@ -ForegroundColor Green
