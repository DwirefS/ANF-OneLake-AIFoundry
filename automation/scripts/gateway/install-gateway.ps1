# ============================================================================
# Gateway VM Script: Install and Register On-Premises Data Gateway
# This script runs ON the gateway VM (via Custom Script Extension or manually)
# Requires: PowerShell 7+, Internet access
# ============================================================================

param(
    [Parameter(Mandatory)][string]$ServicePrincipalAppId,
    [Parameter(Mandatory)][string]$ServicePrincipalSecret,
    [Parameter(Mandatory)][string]$TenantId,
    [string]$GatewayName = 'ANF-Gateway',
    [string]$RegionKey = 'eastus2',
    [string]$CertificatePem
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Installing On-Premises Data Gateway ===" -ForegroundColor Cyan

# --- Step 1: Download and install the gateway silently ---
$installerUrl = 'https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409'
$installerPath = "$env:TEMP\GatewayInstall.exe"

Write-Host "  Downloading gateway installer..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

Write-Host "  Installing gateway (silent)..." -ForegroundColor Yellow
Start-Process -FilePath $installerPath -ArgumentList '/quiet', 'ACCEPTEULA=yes' -Wait -NoNewWindow
Write-Host "  Gateway installed." -ForegroundColor Green

# --- Step 2: Install PowerShell 7 if not present ---
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing PowerShell 7..." -ForegroundColor Yellow
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
}

# --- Step 3: Install DataGateway module and register ---
Write-Host "  Installing DataGateway PowerShell module..." -ForegroundColor Yellow

# Use pwsh to run the registration commands (DataGateway module requires PS7+)
$registrationScript = @"
Install-Module -Name DataGateway -Force -Scope CurrentUser
Import-Module DataGateway

# Authenticate with Service Principal
`$secureSecret = ConvertTo-SecureString '$ServicePrincipalSecret' -AsPlainText -Force
Connect-DataGatewayServiceAccount -ApplicationId '$ServicePrincipalAppId' -ClientSecret `$secureSecret -TenantId '$TenantId'

# Register the gateway
Install-DataGateway -RegionKey '$RegionKey'

# Get the gateway cluster ID
`$clusters = Get-DataGatewayCluster
`$clusterId = `$clusters[0].Id
Write-Host "  Gateway registered. Cluster ID: `$clusterId" -ForegroundColor Green

# Output cluster ID for downstream use
`$clusterId | Out-File -FilePath 'C:\gateway-cluster-id.txt'
"@

$scriptPath = "$env:TEMP\register-gateway.ps1"
$registrationScript | Out-File -FilePath $scriptPath -Encoding utf8

# Execute with PowerShell 7
$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshPath) {
    $pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
}

& $pwshPath -ExecutionPolicy Bypass -File $scriptPath

# --- Step 4: Import ANF certificate if provided ---
if ($CertificatePem) {
    Write-Host "  Importing ANF certificate to trusted store..." -ForegroundColor Yellow
    $certPath = "$env:TEMP\anf-cert.pem"
    $CertificatePem | Out-File -FilePath $certPath -Encoding utf8
    Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root
    Write-Host "  Certificate imported." -ForegroundColor Green
}

Write-Host "=== Gateway setup complete ===" -ForegroundColor Green
