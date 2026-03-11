# Capital Markets Azure Function — Tool Calling API

Azure Functions implementation of the Capital Markets live data tools for Azure AI Foundry Agent Actions.

## Architecture

```
Azure AI Foundry Agent
  ├── Knowledge (RAG): AI Search multimodal vector index
  └── Actions (Tool Calling): THIS Azure Function ←──┐
       │                                               │
       ├── /tools/market_get_quote          ──→ Yahoo Finance
       ├── /tools/market_get_options_chain   ──→ Yahoo Finance
       ├── /tools/market_get_earnings        ──→ Yahoo Finance
       ├── /tools/market_get_macro           ──→ FRED API
       ├── /tools/market_compare_stocks      ──→ Yahoo Finance
       ├── /tools/market_get_sector_performance ──→ Yahoo Finance
       ├── /tools/market_portfolio_snapshot   ──→ Yahoo Finance
       └── /tools/market_get_news            ──→ Yahoo Finance
```

## Deployment

### Option A: Cloud Shell (Recommended)
```bash
# Upload this folder to Cloud Shell, then:
chmod +x deploy.sh
./deploy.sh
```

### Option B: Azure CLI
```bash
# 1. Create storage + function app
az storage account create -n <your-storage-account> -g <your-resource-group> -l eastus2 --sku Standard_LRS
az functionapp create -n <your-function-app-name> -g <your-resource-group> \
  --storage-account <your-storage-account> \
  --consumption-plan-location eastus2 \
  --runtime python --runtime-version 3.11 --functions-version 4 --os-type Linux

# 2. Deploy code
func azure functionapp publish <your-function-app-name> --python
```

### Option C: VS Code
1. Install Azure Functions extension
2. Open this folder
3. Right-click function_app.py → Deploy to Function App

## Connecting to Foundry Agent

1. Go to Azure AI Foundry → Agents → Your Agent → Actions → Add
2. Select "OpenAPI 3.0 specified tool"
3. Paste contents of `openapi_spec_azure_func.json`
4. Authentication: API Key → Header → `x-functions-key` → paste your function key
5. Save

## Files

| File | Purpose |
|------|---------|
| function_app.py | All 8 HTTP-triggered functions |
| requirements.txt | Python dependencies |
| host.json | Azure Functions host config (routePrefix removed for clean URLs) |
| local.settings.json | Local dev settings (not deployed) |
| openapi_spec_azure_func.json | OpenAPI 3.0.3 spec for Foundry Agent |
| deploy.sh | One-click deployment script |

## Testing Locally

```bash
pip install azure-functions-core-tools
func start
# Then: curl -X POST http://localhost:7071/tools/market_get_quote -H 'Content-Type: application/json' -d '{"ticker":"AAPL"}'
```
