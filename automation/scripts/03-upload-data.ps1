# ============================================================================
# Step 3: Upload Test Data to ANF Object Bucket
# Uses AWS CLI with S3-compatible endpoint
# ============================================================================

param(
    [Parameter(Mandatory)][string]$Endpoint,
    [Parameter(Mandatory)][string]$AccessKey,
    [Parameter(Mandatory)][string]$SecretKey,
    [Parameter(Mandatory)][string]$BucketName,
    [string]$CertificatePath,
    [string]$TestDataPath
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 3: Uploading Test Data to ANF Bucket ===" -ForegroundColor Cyan

# --- Resolve test data path ---
if (-not $TestDataPath) {
    $TestDataPath = Join-Path $PSScriptRoot '..' '..' 'test_data'
}

if (-not (Test-Path $TestDataPath)) {
    Write-Error "Test data directory not found: $TestDataPath"
    exit 1
}

# --- Set AWS CLI environment for S3-compatible access ---
$env:AWS_ACCESS_KEY_ID = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION = 'us-east-1'  # Required but unused for S3-compatible

# --- Build common args ---
$s3Args = @(
    '--endpoint-url', $Endpoint,
    '--no-verify-ssl'
)

# --- Upload invoices ---
$invoicesPath = Join-Path $TestDataPath 'invoices'
if (Test-Path $invoicesPath) {
    Write-Host "  Uploading invoices/..." -ForegroundColor Yellow
    aws s3 sync $invoicesPath "s3://${BucketName}/invoices/" @s3Args
    Write-Host "  Invoices uploaded." -ForegroundColor Green
}

# --- Upload financial statements ---
$statementsPath = Join-Path $TestDataPath 'financial_statements'
if (Test-Path $statementsPath) {
    Write-Host "  Uploading financial_statements/..." -ForegroundColor Yellow
    aws s3 sync $statementsPath "s3://${BucketName}/financial_statements/" @s3Args
    Write-Host "  Financial statements uploaded." -ForegroundColor Green
}

# --- Verify upload ---
Write-Host "  Verifying bucket contents..." -ForegroundColor Yellow
aws s3 ls "s3://${BucketName}/" --recursive @s3Args

Write-Host "  Data upload complete." -ForegroundColor Green

# --- Clean up env vars ---
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
