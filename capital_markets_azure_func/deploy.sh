#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Capital Markets Azure Function — Deployment Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script creates and deploys the Capital Markets Tool Calling API
# as an Azure Function in the <your-resource-group> resource group.
#
# Prerequisites:
#   - Azure CLI (az) logged in
#   - Azure Functions Core Tools (func) installed
#   - Python 3.11
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# After deployment:
#   1. Copy the function URL from the output
#   2. Update openapi_spec_azure_func.json "servers" URL
#   3. Paste into Azure AI Foundry Agent → Actions → OpenAPI 3.0 tool
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
RESOURCE_GROUP="<your-resource-group>"
LOCATION="eastus2"
STORAGE_ACCOUNT="<your-storage-account>"     # Must be globally unique, lowercase, no hyphens
FUNCTION_APP_NAME="<your-function-app-name>"  # Must be globally unique
PYTHON_VERSION="3.11"
FRED_API_KEY="${FRED_API_KEY:-your-fred-api-key}"   # Set env var or replace here

echo "═══════════════════════════════════════════════════════════════"
echo "  Capital Markets Azure Function Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo "  Resource Group:   $RESOURCE_GROUP"
echo "  Location:         $LOCATION"
echo "  Function App:     $FUNCTION_APP_NAME"
echo "  Storage Account:  $STORAGE_ACCOUNT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Create Storage Account (required for Azure Functions) ─────────────
echo "[1/5] Creating storage account..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --tags KeepAlive=yes \
  --output none 2>/dev/null || echo "  → Storage account already exists or created"

# ── Step 2: Create Function App ───────────────────────────────────────────────
echo "[2/5] Creating Function App (Python $PYTHON_VERSION, Consumption plan)..."
az functionapp create \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --consumption-plan-location "$LOCATION" \
  --runtime python \
  --runtime-version "$PYTHON_VERSION" \
  --functions-version 4 \
  --os-type Linux \
  --tags KeepAlive=yes \
  --output none 2>/dev/null || echo "  → Function App already exists or created"

# ── Step 3: Configure App Settings ────────────────────────────────────────────
echo "[3/5] Configuring app settings..."
az functionapp config appsettings set \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    FRED_API_KEY="$FRED_API_KEY" \
    FUNCTIONS_WORKER_RUNTIME=python \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
  --output none

# Enable CORS for Foundry Agent
az functionapp cors add \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --allowed-origins "https://ai.azure.com" "https://portal.azure.com" \
  --output none 2>/dev/null || true

# ── Step 4: Deploy Function Code ─────────────────────────────────────────────
echo "[4/5] Publishing function code..."
# If using Azure Functions Core Tools locally:
# func azure functionapp publish "$FUNCTION_APP_NAME" --python

# If deploying from Cloud Shell or CI/CD, use zip deploy:
cd "$(dirname "$0")"
zip -r /tmp/capmarkets-func.zip . -x "*.sh" ".git/*" "__pycache__/*" ".venv/*" "local.settings.json"
az functionapp deployment source config-zip \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --src /tmp/capmarkets-func.zip \
  --output none

# ── Step 5: Get Function URL & Keys ──────────────────────────────────────────
echo "[5/5] Retrieving function URL..."
echo ""

FUNC_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
FUNC_KEY=$(az functionapp keys list \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "functionKeys.default" -o tsv 2>/dev/null || echo "key-not-available-yet")

echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ DEPLOYMENT COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Function App URL:  $FUNC_URL"
echo "  Function Key:      $FUNC_KEY"
echo ""
echo "  Test endpoints:"
echo "    curl -X POST '${FUNC_URL}/tools/market_get_quote?code=${FUNC_KEY}' \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"ticker\": \"AAPL\"}'"
echo ""
echo "    curl '${FUNC_URL}/health?code=${FUNC_KEY}'"
echo ""
echo "  ─── Next Steps ───"
echo "  1. Update openapi_spec_azure_func.json:"
echo "     Replace <YOUR-FUNCTION-APP> with: $FUNCTION_APP_NAME"
echo ""
echo "  2. In Azure AI Foundry Agent → Actions → Add:"
echo "     - Choose 'OpenAPI 3.0 specified tool'"
echo "     - Name: Capital Markets Live Data"
echo "     - Paste the updated OpenAPI spec"
echo "     - Auth: API Key → Header → x-functions-key → paste the key above"
echo ""
echo "  3. Apply KeepAlive tag to new resources:"
echo "     az tag update --resource-id \$(az functionapp show -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP --query id -o tsv) --operation merge --tags KeepAlive=yes"
echo "═══════════════════════════════════════════════════════════════"
