# ============================================================================
# Gateway VM Script: Install OPDG and Import ANF Certificate
# This script runs ON the gateway VM via 'az vm run-command invoke'
# ============================================================================
#
# Usage (from Cloud Shell / automation host):
#   # Step 1: Install OPDG
#   az vm run-command invoke --resource-group $RG --name $VM \
#     --command-id RunPowerShellScript --scripts @install-gateway.ps1 \
#     --parameters "Action=InstallOPDG"
#
#   # Step 2: Import ANF self-signed cert
#   az vm run-command invoke --resource-group $RG --name $VM \
#     --command-id RunPowerShellScript --scripts @install-gateway.ps1 \
#     --parameters "Action=ImportCert" "AnfIpAddress=10.0.1.4"
#
#   # Step 3 (MANUAL): RDP via Bastion, open OPDG app, sign in to register.
#   # Service Principal registration is NOT supported in enterprise tenants
#   # that block app registration (Lesson 4).
#
# ORIGINAL script used Custom Script Extension and required:
#   param(
#       [Parameter(Mandatory)][string]$ServicePrincipalAppId,
#       [Parameter(Mandatory)][string]$ServicePrincipalSecret,
#       [Parameter(Mandatory)][string]$TenantId,
#       [string]$GatewayName = 'ANF-Gateway',
#       [string]$RegionKey = 'eastus2',
#       [string]$CertificatePem
#   )
# FIX: SP-based registration doesn't work in enterprise tenants (Lesson 4).
# FIX: Certificate import via file doesn't work for self-signed certs from
#      remote ANF endpoints — must retrieve via TcpClient/SslStream (Lesson 18).
# Rewritten to use az vm run-command invoke with Action parameter.
# ============================================================================

param(
    [ValidateSet('InstallOPDG', 'ImportCert', 'All')]
    [string]$Action = 'All',

    [string]$AnfIpAddress,
    [int]$AnfPort = 443
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Step 1: Download and Install On-Premises Data Gateway
# ============================================================================
function Install-OPDG {
    Write-Host "=== Installing On-Premises Data Gateway ===" -ForegroundColor Cyan

    # Force TLS 1.2 (required for Microsoft download URLs)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $installerUrl = 'https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409'
    $installerPath = 'C:\GatewayInstall.exe'

    # Download
    Write-Host "  Downloading gateway installer..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    if (-not (Test-Path $installerPath)) {
        Write-Error "Download failed. File not found at $installerPath"
        exit 1
    }
    $fileSize = (Get-Item $installerPath).Length / 1MB
    Write-Host "  Downloaded: $([math]::Round($fileSize, 1)) MB" -ForegroundColor Gray

    # Silent install
    Write-Host "  Installing gateway (silent)..." -ForegroundColor Yellow
    Start-Process -FilePath $installerPath -ArgumentList '/quiet', 'ACCEPTEULA=yes' -Wait -NoNewWindow

    # Verify service is running
    $svc = Get-Service -Name 'PBIEgwService' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "  OPDG installed successfully." -ForegroundColor Green
        Write-Host "  Service: $($svc.Name) — Status: $($svc.Status), StartType: $($svc.StartType)" -ForegroundColor Gray
    } else {
        Write-Warning "OPDG service not found or not running. Check install logs at C:\Users\<admin>\AppData\Local\Microsoft\On-premises data gateway\*.log"
        Get-Service *PBIEgw* | Format-Table Name, Status, StartType
    }

    # Cleanup installer
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "  NEXT STEP: RDP into this VM via Azure Bastion, open the" -ForegroundColor Yellow
    Write-Host "  'On-premises data gateway' app, and sign in with your" -ForegroundColor Yellow
    Write-Host "  organizational account to register the gateway." -ForegroundColor Yellow
    Write-Host "  (SP-based registration not available — see Lesson 4)" -ForegroundColor Yellow
}

# ============================================================================
# Step 2: Import ANF Self-Signed Certificate to Trusted Root Store
# ============================================================================
# FIX: Original script tried Import-Certificate from a PEM file parameter.
# This doesn't work because the cert is self-signed and lives on the ANF
# endpoint — not passed as a parameter. The working approach retrieves the
# cert directly from the ANF S3 endpoint via TcpClient/SslStream.
# ============================================================================
function Import-AnfCertificate {
    param(
        [Parameter(Mandatory)][string]$IpAddress,
        [int]$Port = 443
    )

    Write-Host "=== Importing ANF Certificate from ${IpAddress}:${Port} ===" -ForegroundColor Cyan

    # Connect to ANF S3 endpoint and retrieve the self-signed certificate
    Write-Host "  Connecting to ANF endpoint..." -ForegroundColor Yellow
    $tcp = New-Object Net.Sockets.TcpClient($IpAddress, $Port)
    # Accept any certificate (it's self-signed, that's why we're importing it)
    $ssl = New-Object Net.Security.SslStream(
        $tcp.GetStream(),
        $false,
        { param($sender, $certificate, $chain, $errors) $true }
    )
    $ssl.AuthenticateAsClient($IpAddress)
    $remoteCert = $ssl.RemoteCertificate
    $ssl.Close()
    $tcp.Close()

    if (-not $remoteCert) {
        Write-Error "Failed to retrieve certificate from ${IpAddress}:${Port}"
        exit 1
    }

    # Convert to X509Certificate2 for store import
    $cert2 = New-Object Security.Cryptography.X509Certificates.X509Certificate2($remoteCert)
    Write-Host "  Certificate retrieved:" -ForegroundColor Gray
    Write-Host "    Subject:    $($cert2.Subject)" -ForegroundColor Gray
    Write-Host "    Issuer:     $($cert2.Issuer)" -ForegroundColor Gray
    Write-Host "    Thumbprint: $($cert2.Thumbprint)" -ForegroundColor Gray
    Write-Host "    Expires:    $($cert2.NotAfter)" -ForegroundColor Gray

    # Import to LocalMachine\Root (Trusted Root Certification Authorities)
    Write-Host "  Importing to LocalMachine\Root trusted store..." -ForegroundColor Yellow
    $store = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $store.Open('ReadWrite')
    $store.Add($cert2)
    $store.Close()

    # Verify import
    $verifyStore = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $verifyStore.Open('ReadOnly')
    $found = $verifyStore.Certificates | Where-Object { $_.Thumbprint -eq $cert2.Thumbprint }
    $verifyStore.Close()

    if ($found) {
        Write-Host "  Certificate imported and verified in trusted root store." -ForegroundColor Green
    } else {
        Write-Error "Certificate import could not be verified. Thumbprint: $($cert2.Thumbprint)"
    }
}

# ============================================================================
# Dispatch based on Action parameter
# ============================================================================
switch ($Action) {
    'InstallOPDG' {
        Install-OPDG
    }
    'ImportCert' {
        if (-not $AnfIpAddress) {
            Write-Error "AnfIpAddress is required for ImportCert action. Pass -AnfIpAddress <IP>"
            exit 1
        }
        Import-AnfCertificate -IpAddress $AnfIpAddress -Port $AnfPort
    }
    'All' {
        Install-OPDG
        if ($AnfIpAddress) {
            Import-AnfCertificate -IpAddress $AnfIpAddress -Port $AnfPort
        } else {
            Write-Host "`n  Skipping cert import — no AnfIpAddress provided." -ForegroundColor Yellow
            Write-Host "  Re-run with: -Action ImportCert -AnfIpAddress <ANF_IP>" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n=== Gateway setup script complete ===" -ForegroundColor Green
