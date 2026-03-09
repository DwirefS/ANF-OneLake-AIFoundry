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
    [string]$CertificatePath,
    # FIX (Lesson 15): UID 0 (root) is a system user and cannot be used for S3 NAS buckets.
    # ONTAP rejects it with: "user (0:1) cannot be modified as it is a system user"
    # Original: userId = 0, groupId = 0
    [int]$NfsUserId = 1000,
    [int]$NfsGroupId = 1000,
    [int]$KeyPairExpiryDays = 365
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
    # FIX (Lesson 13): Create combined PEM for base64 encoding
    $combinedPath = Join-Path $certDir 'combined.pem'

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

    # FIX (Lesson 13): Combine cert + key into single PEM for base64 encoding
    $certPem = Get-Content $CertificatePath -Raw
    $keyPem = Get-Content $keyPath -Raw
    "$certPem`n$keyPem" | Set-Content $combinedPath -NoNewline

    Write-Host "  Certificate generated: $CertificatePath" -ForegroundColor Green
}

# --- Read and base64-encode certificate content ---
# FIX (Lesson 13): The REST API requires base64-encoded combined cert+key PEM,
# not raw PEM content. Original code sent raw PEM which doesn't work.
# Original: $certContent = Get-Content $CertificatePath -Raw
if (Test-Path (Join-Path (Split-Path $CertificatePath) 'combined.pem')) {
    $combinedPath = Join-Path (Split-Path $CertificatePath) 'combined.pem'
} else {
    $combinedPath = $CertificatePath
}
$certBytes = [System.IO.File]::ReadAllBytes($combinedPath)
$certBase64 = [Convert]::ToBase64String($certBytes)

# --- Create the bucket via Azure REST API ---
Write-Host "  Creating ANF bucket '$BucketName' (nfsUser=$NfsUserId`:$NfsGroupId)..." -ForegroundColor Yellow

$token = az account get-access-token --query accessToken -o tsv
$apiVersion = '2025-03-01-preview'
$volumeResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.NetApp/netAppAccounts/$NetAppAccountName/capacityPools/$CapacityPoolName/volumes/$VolumeName"
$bucketUri = "https://management.azure.com${volumeResourceId}/buckets/${BucketName}?api-version=$apiVersion"

$bucketBody = @{
    properties = @{
        path = '/'
        # FIX: Removed 'permissions' field — not supported in 2025-03-01-preview API.
        # The 'permissions' field requires api-version 2025-07-01-preview or later.
        # Original: permissions = 'readwrite'
        fileSystemUser = @{
            nfsUser = @{
                # FIX (Lesson 15): Changed from userId=0,groupId=0 to configurable non-system user
                userId  = $NfsUserId
                groupId = $NfsGroupId
            }
        }
        server = @{
            # FIX (Lesson 13): Send base64-encoded combined PEM, not raw PEM
            # Original: certificateObject = $certContent
            certificateObject = $certBase64
        }
    }
} | ConvertTo-Json -Depth 10

$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = 'application/json'
}

$response = Invoke-RestMethod -Uri $bucketUri -Method Put -Headers $headers -Body $bucketBody

# FIX (Lesson 17): The PUT returns 201 "Accepted" even when async processing will fail.
# Must poll the bucket GET endpoint to confirm provisioningState transitions to "Succeeded".
Write-Host "  Bucket PUT accepted. Waiting for provisioning to complete..." -ForegroundColor Yellow
$maxRetries = 12
$retryDelay = 10
for ($i = 1; $i -le $maxRetries; $i++) {
    Start-Sleep -Seconds $retryDelay
    try {
        $bucketStatus = Invoke-RestMethod -Uri $bucketUri -Method Get -Headers $headers
        $state = $bucketStatus.properties.provisioningState
        Write-Host "  Check $i/$maxRetries`: provisioningState=$state" -ForegroundColor Gray
        if ($state -eq 'Succeeded') {
            Write-Host "  Bucket '$BucketName' created successfully." -ForegroundColor Green
            break
        }
        if ($state -eq 'Failed') {
            Write-Error "Bucket creation failed. Check Activity Log: az monitor activity-log list --resource-group $ResourceGroupName --offset 1h --query `"[?contains(operationName.value,'bucket')]`""
            exit 1
        }
    } catch {
        # NoBucketFound means async creation failed silently
        Write-Host "  Check $i/$maxRetries`: Bucket not found (may have failed). Checking Activity Log..." -ForegroundColor Red
        if ($i -eq $maxRetries) {
            Write-Error "Bucket '$BucketName' was not created. The PUT was accepted but async processing failed. Check Activity Log for the actual error (Lesson 15: common cause is userId=0 being a system user)."
            exit 1
        }
    }
}

# --- Generate access credentials ---
Write-Host "  Generating bucket access credentials..." -ForegroundColor Yellow

$credUri = "https://management.azure.com${volumeResourceId}/buckets/${BucketName}/generateCredentials?api-version=$apiVersion"
# FIX (Lesson 16): Must pass keyPairExpiryDays (1-365). Empty body {} defaults to 0 which is rejected.
# Original: $credResponse = Invoke-RestMethod -Uri $credUri -Method Post -Headers $headers -Body '{}' -ContentType 'application/json'
$credBody = @{ keyPairExpiryDays = $KeyPairExpiryDays } | ConvertTo-Json
$credResponse = Invoke-RestMethod -Uri $credUri -Method Post -Headers $headers -Body $credBody -ContentType 'application/json'

$accessKey = $credResponse.accessKey
$secretKey = $credResponse.secretKey
# FIX: Response field is 'secretKey' not 'secretAccessKey'
# Original: $secretKey = $credResponse.secretAccessKey

# Get endpoint IP from bucket GET response
$endpoint = "https://$($bucketStatus.properties.server.ipAddress)"

Write-Host "  Credentials generated successfully." -ForegroundColor Green
Write-Host "  Endpoint: $endpoint" -ForegroundColor Gray
Write-Host "  Access Key: $accessKey" -ForegroundColor Gray

# --- Return values for downstream scripts ---
$result = @{
    BucketName  = $BucketName
    Endpoint    = $endpoint
    AccessKey   = $accessKey
    SecretKey   = $secretKey
    CertPath    = $CertificatePath
    IpAddress   = $bucketStatus.properties.server.ipAddress
}

return $result
