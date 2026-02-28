# ============================================================================
# Step 2: Create ANF Object REST API Bucket and Generate Credentials
# ============================================================================

param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$NetAppAccountName,
    [Parameter(Mandatory)][string]$CapacityPoolName,
    [Parameter(Mandatory)][string]$VolumeName,
    [string]$BucketName = 'finance-data',
    [string]$CertificatePath
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 2: Configuring ANF Object REST API Bucket ===" -ForegroundColor Cyan

# --- Generate certificate if not provided ---
if (-not $CertificatePath -or -not (Test-Path $CertificatePath)) {
    Write-Host "  No certificate provided. Generating self-signed certificate..." -ForegroundColor Yellow
    $certDir = Join-Path $PSScriptRoot '..' '.certs'
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null

    $CertificatePath = Join-Path $certDir 'cert.pem'
    $keyPath = Join-Path $certDir 'private.key'

    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:4096 `
        -keyout $keyPath `
        -out $CertificatePath `
        -days 365 -nodes `
        -subj "/CN=anf-object-api/O=RAGWorkshop" 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to generate certificate. Ensure openssl is installed."
        exit 1
    }
    Write-Host "  Certificate generated: $CertificatePath" -ForegroundColor Green
}

# --- Read certificate content ---
$certContent = Get-Content $CertificatePath -Raw

# --- Create the bucket via Azure REST API ---
Write-Host "  Creating ANF bucket '$BucketName'..." -ForegroundColor Yellow

$token = az account get-access-token --query accessToken -o tsv
$apiVersion = '2025-03-01-preview'
$volumeResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.NetApp/netAppAccounts/$NetAppAccountName/capacityPools/$CapacityPoolName/volumes/$VolumeName"
$bucketUri = "https://management.azure.com${volumeResourceId}/buckets/${BucketName}?api-version=$apiVersion"

$bucketBody = @{
    properties = @{
        path = '/'
        permissions = 'readwrite'
        fileSystemUser = @{
            nfsUser = @{
                userId = 0
                groupId = 0
            }
        }
        server = @{
            certificateObject = $certContent
        }
    }
} | ConvertTo-Json -Depth 10

$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = 'application/json'
}

$response = Invoke-RestMethod -Uri $bucketUri -Method Put -Headers $headers -Body $bucketBody
Write-Host "  Bucket '$BucketName' created successfully." -ForegroundColor Green

# --- Generate access credentials ---
Write-Host "  Generating bucket access credentials..." -ForegroundColor Yellow

$credUri = "https://management.azure.com${volumeResourceId}/buckets/${BucketName}/generateCredentials?api-version=$apiVersion"
$credResponse = Invoke-RestMethod -Uri $credUri -Method Post -Headers $headers -Body '{}' -ContentType 'application/json'

$accessKey = $credResponse.accessKey
$secretKey = $credResponse.secretAccessKey
$endpoint = $credResponse.endpoint

# If endpoint is not in the response, construct it from volume properties
if (-not $endpoint) {
    $volInfo = Invoke-RestMethod -Uri "https://management.azure.com${volumeResourceId}?api-version=2024-07-01" -Headers $headers
    $endpoint = "https://$($volInfo.properties.mountTargets[0].ipAddress)"
}

Write-Host "  Credentials generated successfully." -ForegroundColor Green
Write-Host "  Endpoint: $endpoint" -ForegroundColor Gray

# --- Return values for downstream scripts ---
$result = @{
    BucketName  = $BucketName
    Endpoint    = $endpoint
    AccessKey   = $accessKey
    SecretKey   = $secretKey
    CertPath    = $CertificatePath
}

return $result
