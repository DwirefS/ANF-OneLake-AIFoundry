# ============================================================================
# Step 1: Register Required Azure Resource Providers
# ============================================================================

param(
    [Parameter(Mandatory)][string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 1: Registering Resource Providers ===" -ForegroundColor Cyan

$providers = @(
    'Microsoft.NetApp',
    'Microsoft.Search',
    'Microsoft.CognitiveServices',
    'Microsoft.MachineLearningServices',
    'Microsoft.Fabric'
)

az account set --subscription $SubscriptionId

foreach ($provider in $providers) {
    $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($state -ne 'Registered') {
        Write-Host "  Registering $provider..." -ForegroundColor Yellow
        az provider register --namespace $provider --wait
    } else {
        Write-Host "  $provider already registered." -ForegroundColor Green
    }
}

Write-Host "  All resource providers registered." -ForegroundColor Green
