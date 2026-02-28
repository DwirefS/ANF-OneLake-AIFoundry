# ============================================================================
# Step 4: Configure Microsoft Fabric (Workspace, Lakehouse, Connection, Shortcut)
# Uses Fabric REST API
# ============================================================================

param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ServicePrincipalAppId,
    [Parameter(Mandatory)][string]$ServicePrincipalSecret,
    [Parameter(Mandatory)][string]$FabricCapacityId,
    [Parameter(Mandatory)][string]$AnfEndpoint,
    [Parameter(Mandatory)][string]$AnfAccessKey,
    [Parameter(Mandatory)][string]$AnfSecretKey,
    [Parameter(Mandatory)][string]$BucketName,
    [string]$WorkspaceName = 'Financial_RAG_Workshop',
    [string]$LakehouseName = 'FinDataLake',
    [string]$ShortcutName = 'anf_shortcut'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 4: Configuring Microsoft Fabric ===" -ForegroundColor Cyan

# --- Get Fabric access token via Service Principal ---
$tokenBody = @{
    grant_type    = 'client_credentials'
    client_id     = $ServicePrincipalAppId
    client_secret = $ServicePrincipalSecret
    scope         = 'https://api.fabric.microsoft.com/.default'
}

$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
$fabricToken = $tokenResponse.access_token

$fabricHeaders = @{
    'Authorization' = "Bearer $fabricToken"
    'Content-Type'  = 'application/json'
}

$fabricBaseUrl = 'https://api.fabric.microsoft.com/v1'

# --- Step 4.1: Create Workspace ---
Write-Host "  Creating Fabric workspace '$WorkspaceName'..." -ForegroundColor Yellow

$workspaceBody = @{
    displayName = $WorkspaceName
    capacityId  = $FabricCapacityId
} | ConvertTo-Json

try {
    $workspace = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces" `
        -Method Post -Headers $fabricHeaders -Body $workspaceBody
    $workspaceId = $workspace.id
    Write-Host "  Workspace created: $workspaceId" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "  Workspace already exists. Fetching ID..." -ForegroundColor Yellow
        $workspaces = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces" -Headers $fabricHeaders
        $workspaceId = ($workspaces.value | Where-Object { $_.displayName -eq $WorkspaceName }).id
        Write-Host "  Found workspace: $workspaceId" -ForegroundColor Green
    } else {
        throw
    }
}

# --- Step 4.2: Create Lakehouse ---
Write-Host "  Creating Lakehouse '$LakehouseName'..." -ForegroundColor Yellow

$lakehouseBody = @{
    displayName = $LakehouseName
} | ConvertTo-Json

try {
    $lakehouse = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces/$workspaceId/lakehouses" `
        -Method Post -Headers $fabricHeaders -Body $lakehouseBody

    # Handle long-running operation
    if ($lakehouse.id) {
        $lakehouseId = $lakehouse.id
    } else {
        # Poll for completion if async
        Start-Sleep -Seconds 10
        $lakehouses = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces/$workspaceId/lakehouses" -Headers $fabricHeaders
        $lakehouseId = ($lakehouses.value | Where-Object { $_.displayName -eq $LakehouseName }).id
    }
    Write-Host "  Lakehouse created: $lakehouseId" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "  Lakehouse already exists. Fetching ID..." -ForegroundColor Yellow
        $lakehouses = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces/$workspaceId/lakehouses" -Headers $fabricHeaders
        $lakehouseId = ($lakehouses.value | Where-Object { $_.displayName -eq $LakehouseName }).id
        Write-Host "  Found lakehouse: $lakehouseId" -ForegroundColor Green
    } else {
        throw
    }
}

# --- Step 4.3: Read the gateway cluster ID ---
Write-Host "  Discovering gateway..." -ForegroundColor Yellow
$gateways = Invoke-RestMethod -Uri "$fabricBaseUrl/gateways" -Headers $fabricHeaders
$gatewayId = $gateways.value[0].id

if (-not $gatewayId) {
    Write-Error "No on-premises data gateway found. Ensure the gateway is installed and registered."
    exit 1
}
Write-Host "  Found gateway: $gatewayId" -ForegroundColor Green

# --- Step 4.4: Create S3-Compatible Connection ---
Write-Host "  Creating S3-compatible connection..." -ForegroundColor Yellow

# Discover connection type
$connectionTypes = Invoke-RestMethod -Uri "$fabricBaseUrl/connections/supportedConnectionTypes?gatewayId=$gatewayId" `
    -Headers $fabricHeaders
$s3Type = ($connectionTypes.value | Where-Object { $_.type -match 'S3Compatible|AmazonS3Compatible' }).type

if (-not $s3Type) {
    $s3Type = 'AmazonS3Compatible'  # Fallback to known type
}

$connectionBody = @{
    connectivityType = 'OnPremisesGateway'
    gatewayId        = $gatewayId
    displayName      = 'ANF-S3-Connection'
    connectionDetails = @{
        type             = $s3Type
        creationMethod   = 'Auto'
        parameters       = @(
            @{ name = 'url'; value = $AnfEndpoint }
        )
    }
    credentialDetails = @{
        credentials = @{
            credentialType = 'Key'
            accessKeyId    = $AnfAccessKey
            secretAccessKey = $AnfSecretKey
        }
    }
    privacyLevel = 'Organizational'
} | ConvertTo-Json -Depth 10

$connection = Invoke-RestMethod -Uri "$fabricBaseUrl/connections" `
    -Method Post -Headers $fabricHeaders -Body $connectionBody
$connectionId = $connection.id
Write-Host "  Connection created: $connectionId" -ForegroundColor Green

# --- Step 4.5: Create OneLake Shortcut ---
Write-Host "  Creating OneLake shortcut '$ShortcutName'..." -ForegroundColor Yellow

$shortcutBody = @{
    path   = 'Files'
    name   = $ShortcutName
    target = @{
        s3Compatible = @{
            location     = $AnfEndpoint
            bucket       = $BucketName
            subpath      = '/'
            connectionId = $connectionId
        }
    }
} | ConvertTo-Json -Depth 10

$shortcut = Invoke-RestMethod -Uri "$fabricBaseUrl/workspaces/$workspaceId/items/$lakehouseId/shortcuts" `
    -Method Post -Headers $fabricHeaders -Body $shortcutBody
Write-Host "  Shortcut created successfully." -ForegroundColor Green

# --- Return values for downstream scripts ---
$result = @{
    WorkspaceId  = $workspaceId
    LakehouseId  = $lakehouseId
    ConnectionId = $connectionId
    GatewayId    = $gatewayId
}

return $result
