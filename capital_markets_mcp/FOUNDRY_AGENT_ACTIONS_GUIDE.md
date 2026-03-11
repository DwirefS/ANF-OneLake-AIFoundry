# Azure AI Foundry Hybrid Agent: Capital Markets MCP Integration Guide

This guide walks you through connecting a Capital Markets MCP server as a live data Action in Azure AI Foundry Agent. The agent will combine AI Search-based RAG (knowledge) with real-time market data from the MCP server to answer complex financial queries.

---

## Section 1: Architecture Overview

The hybrid agent leverages two data sources working in tandem:

```
┌─────────────────────────────────────────────────────────────┐
│              Azure AI Foundry Agent                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Agent Orchestration & LLM Reasoning (GPT-4)         │   │
│  └───────────────────┬──────────────────────────────────┘   │
│                      │                                        │
│      ┌───────────────┴────────────────┐                       │
│      │                                 │                       │
│  ┌───▼─────────────┐        ┌──────────▼──────────┐          │
│  │  RAG (Knowledge)│        │ Actions (Live Data) │          │
│  │                 │        │                      │          │
│  │ AI Search Index │        │ Capital Markets MCP  │          │
│  │ - Docs          │        │ - Stock quotes       │          │
│  │ - Policies      │        │ - Options chains     │          │
│  │ - Reports       │        │ - Earnings data      │          │
│  └─────────────────┘        │ - Macro indicators   │          │
│                              │ - Portfolio snapshot │          │
│                              │ - Sector perf        │          │
│                              │ - News               │          │
│                              └──────────────────────┘          │
│                                                               │
└─────────────────────────────────────────────────────────────┘

Hybrid Query Flow:
─────────────────────────────────────────────────────────────
User Query
    │
    ├─> Agent: "I need context AND real-time data"
    │
    ├─> RAG Retrieval: "What does the policy say?"
    │      └─> Returns: Policy docs, historical analysis
    │
    └─> Action Call: "Get current stock price, options, earnings"
           └─> Returns: Live market data from MCP server

    └─> Final Response: Synthesize both sources
```

**Benefits:**
- **Context**: RAG provides company policies, guidelines, research docs
- **Real-Time**: Actions pull live market data at query time
- **Synthesis**: Agent combines both for informed decisions
- **Flexibility**: Add more actions or knowledge sources independently

---

## Section 2: Prerequisites

Before connecting the Capital Markets MCP server, ensure:

### 2.1 Running MCP Server

The Capital Markets MCP server must be accessible. Three deployment options are covered in Section 3.

**Verify server is running:**
```bash
curl http://localhost:8000/tools/market_get_quote \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"ticker": "AAPL"}'
```

Expected response:
```json
{
  "ticker": "AAPL",
  "price": 195.40,
  "change": 2.15,
  "change_percent": 1.11,
  ...
}
```

### 2.2 Azure AI Foundry Project

- Azure subscription with AI Foundry resource group
- AI Foundry project created and accessible
- Contributor or Owner role on the resource group
- OpenAPI specification ready (provided: `openapi_spec.json`)

### 2.3 AI Search Index (Optional but Recommended)

For RAG functionality:
- AI Search (formerly Cognitive Search) resource deployed
- At least one index created with your knowledge documents
- Search service connection added to Foundry project

### 2.4 Gather Connection Details

You'll need:
- MCP server URL (local: `http://localhost:8000`, production: your public endpoint)
- AI Foundry project name and resource group
- AI Search endpoint and key (if using RAG)

---

## Section 3: Three Deployment Options

### Option A: Local Development (ngrok Tunnel)

**Best for:** Development, testing, short-term demos

**Setup:**

1. Install ngrok:
   ```bash
   # macOS
   brew install ngrok

   # Or download from https://ngrok.com/download
   ```

2. Start your local MCP server:
   ```bash
   python capital_markets_mcp.py --port 8000
   ```

3. Open new terminal, create ngrok tunnel:
   ```bash
   ngrok http 8000
   ```

4. Copy the public URL (e.g., `https://abc123.ngrok.io`)

5. Use this URL in Foundry: Replace `http://localhost:8000` with the ngrok URL in the OpenAPI spec

**Pros:**
- No cloud infrastructure
- Quick to set up
- Instant updates

**Cons:**
- Tunnel expires if closed
- Public URL is temporary
- Not production-grade

---

### Option B: Azure Container Apps (Recommended for Production)

**Best for:** Production workloads, auto-scaling, managed service

**Setup:**

1. Create container registry:
   ```bash
   az acr create \
     --resource-group MyResourceGroup \
     --name mycontainerregistry \
     --sku Basic
   ```

2. Build and push image:
   ```bash
   az acr build \
     --registry mycontainerregistry \
     --image capital-markets-mcp:latest \
     --file Dockerfile .
   ```

3. Create container app:
   ```bash
   az containerapp create \
     --name capital-markets-api \
     --resource-group MyResourceGroup \
     --image mycontainerregistry.azurecr.io/capital-markets-mcp:latest \
     --target-port 8000 \
     --ingress external \
     --registry-server mycontainerregistry.azurecr.io \
     --registry-username <username> \
     --registry-password <password>
   ```

4. Get public URL:
   ```bash
   az containerapp show \
     --name capital-markets-api \
     --resource-group MyResourceGroup \
     --query properties.configuration.ingress.fqdn
   ```

5. Use this URL in Foundry (e.g., `https://capital-markets-api.xxx.eastus.azurecontainerapps.io`)

**Pros:**
- Fully managed
- Auto-scaling
- Production-ready
- HTTPS by default
- Persistent endpoint

**Cons:**
- Requires container image
- Azure costs
- Slightly more setup

**Dockerfile Example:**
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["python", "capital_markets_mcp.py", "--port", "8000"]
```

---

### Option C: Azure App Service

**Best for:** Simple deployments, low-to-medium traffic

**Setup:**

1. Create App Service plan:
   ```bash
   az appservice plan create \
     --name myAppServicePlan \
     --resource-group MyResourceGroup \
     --sku B2
   ```

2. Create App Service:
   ```bash
   az webapp create \
     --name capital-markets-api \
     --resource-group MyResourceGroup \
     --plan myAppServicePlan \
     --runtime "python|3.11"
   ```

3. Deploy code (via git or zip):
   ```bash
   # Deploy from zip file
   az webapp deployment source config-zip \
     --resource-group MyResourceGroup \
     --name capital-markets-api \
     --src deploy.zip
   ```

4. Configure start command in Azure Portal:
   - Go to Configuration → General settings
   - Set Startup command: `gunicorn -w 4 -b 0.0.0.0:8000 app:app`

5. Get URL:
   ```bash
   az webapp show \
     --name capital-markets-api \
     --resource-group MyResourceGroup \
     --query defaultHostName
   ```

**Pros:**
- Easier than containers
- HTTPS included
- Scale up/down via Portal

**Cons:**
- Less flexible than Container Apps
- May be overkill for simple API

---

## Section 4: Step-by-Step Foundry Agent Actions Setup

### 4.1 Navigate to Actions in AI Foundry

1. Open **Azure AI Foundry** (https://ai.azure.com)
2. Select your project
3. Go to **Build** → **Agents** → Select or create an agent
4. Click the **Actions** tab
5. Click **+ Add** → **OpenAPI 3.0 specified tool**

### 4.2 Tool Details (Step 1)

Fill in the tool metadata:

| Field | Value |
|-------|-------|
| **Tool name** | `capital_markets_api` |
| **Tool display name** | `Capital Markets API` |
| **Tool description** | `Real-time market data: quotes, options, earnings, macro indicators, portfolio analytics, and news from Yahoo Finance and FRED` |
| **Authentication type** | `None` (or `API Key` if you add auth) |

Click **Next**.

### 4.3 Define Schema (Step 2)

This is where you paste the OpenAPI spec.

**Option A: Single Multi-Endpoint Spec (Recommended)**

1. Click **Import from JSON**
2. Paste the entire contents of `openapi_spec.json`
3. The system automatically discovers all 8 endpoints:
   - `POST /tools/market_get_quote`
   - `POST /tools/market_get_options_chain`
   - `POST /tools/market_get_earnings`
   - `POST /tools/market_get_macro`
   - `POST /tools/market_compare_stocks`
   - `POST /tools/market_get_sector_performance`
   - `POST /tools/market_portfolio_snapshot`
   - `POST /tools/market_get_news`

4. **Update the server URL:**
   - Find the `servers` section in the spec
   - Replace `http://localhost:8000` with your public endpoint (ngrok, Container Apps, or App Service URL)
   - Example: `https://capital-markets-api.xxx.eastus.azurecontainerapps.io`

5. Review the schema validation
6. Click **Next**

**Option B: Individual Endpoint Specs (If Needed)**

If you prefer to add endpoints one-by-one, create 8 separate OpenAPI specs (one per endpoint). However, this is more tedious.

### 4.4 Review and Create (Step 3)

1. Review the action configuration:
   - Tool name and description
   - All 8 endpoints listed
   - Authentication method
   - Server URL

2. Click **Create**

3. Foundry will register the Capital Markets API as an available Action

### 4.5 Verify Registration

In the agent's Actions tab, you should see:

```
Capital Markets API
├── market_get_quote
├── market_get_options_chain
├── market_get_earnings
├── market_get_macro
├── market_compare_stocks
├── market_get_sector_performance
├── market_portfolio_snapshot
└── market_get_news
```

Each function is now available for the agent to call.

---

## Section 5: Alternative — Custom Function Approach (SDK)

**Best for:** Teams already using Azure AI Agent SDK, custom logic, no HTTP server needed

If you don't want to run a separate HTTP server, you can register Python functions directly via the SDK.

### 5.1 Python Function Registration

```python
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import CodeInterpreterTool, FunctionTool
from azure.identity import DefaultAzureCredential
import json

# Initialize client
client = AIProjectClient.from_config(
    credential=DefaultAzureCredential()
)

# Define your market functions
def market_get_quote(ticker: str) -> dict:
    """Get real-time stock quote for any ticker."""
    # Your implementation: fetch from yfinance, Yahoo Finance API, etc.
    import yfinance as yf
    data = yf.download(ticker, period='1d')
    return {
        "ticker": ticker,
        "price": data['Close'][-1],
        "change": 0.0,
        "volume": data['Volume'][-1],
        # ... return all fields
    }

def market_get_options_chain(ticker: str, expiry_date: str = None) -> dict:
    """Get live options chain near the money."""
    import yfinance as yf
    stock = yf.Ticker(ticker)
    options_dates = stock.options
    # ... fetch and format options data
    return {"calls": [...], "puts": [...]}

# Define other functions similarly...

# Register functions with agent
functions = [
    FunctionTool(market_get_quote),
    FunctionTool(market_get_options_chain),
    FunctionTool(market_get_earnings),
    FunctionTool(market_get_macro),
    FunctionTool(market_compare_stocks),
    FunctionTool(market_get_sector_performance),
    FunctionTool(market_portfolio_snapshot),
    FunctionTool(market_get_news),
]

# Create agent with functions
agent_response = client.agents.create_agent(
    name="Capital Markets Agent",
    model="gpt-4-turbo",
    tools=functions,
    instructions="You are a financial analyst. Use the market tools to provide real-time insights."
)

# Run agent
response = client.agents.create_and_run(
    agent_id=agent_response.id,
    user_message="What's the current price of AAPL and what are the latest earnings trends?"
)

print(response.messages[-1].content)
```

### 5.2 Benefits of SDK Approach

- **No HTTP server**: Functions run in-process
- **Simpler deployment**: Just Python code in Azure Functions or Logic Apps
- **Faster**: No network latency
- **Type-safe**: Full IDE support

### 5.3 When to Use Each

| Approach | Use When |
|----------|----------|
| **OpenAPI Actions** | You have an existing HTTP API, need to call external services, prefer loose coupling |
| **SDK Functions** | Pure Python implementation, simplicity, built into Azure Functions, in-process execution |

For this Capital Markets MCP, **OpenAPI Actions** is recommended because it:
- Decouples the MCP server from the agent
- Allows scaling independently
- Reuses the same server for multiple agents or applications
- Aligns with MCP protocol standards

---

## Section 6: Testing the Hybrid Agent

### 6.1 Example Query 1: Real-Time Price + Historical Context

**Query:**
```
What is the current price of MSFT and how does it compare to analyst
expectations documented in our market research?
```

**Expected behavior:**
1. Agent receives query
2. Agent calls `market_get_quote("MSFT")` → Gets live price, change, P/E, etc.
3. Agent searches RAG index → Retrieves analyst reports on MSFT
4. Agent synthesizes both → Provides current price + historical context

**Response example:**
```
Microsoft (MSFT) is currently trading at $413.50, up 2.1% today.
This aligns with our analyst expectations from the Q1 2026 report,
which projected strong growth in cloud services. The P/E ratio of 32.5
suggests the market values Azure's growth trajectory.
```

### 6.2 Example Query 2: Portfolio Analytics

**Query:**
```
Analyze my portfolio holdings: 100 shares AAPL, 50 shares GOOGL,
75 shares NVDA. What's my daily exposure and how does each holding
compare sector-wise?
```

**Expected behavior:**
1. Agent calls `market_portfolio_snapshot` with holdings data
2. Agent calls `market_compare_stocks(["AAPL", "GOOGL", "NVDA"])` for context
3. Agent calls `market_get_sector_performance()` for sector comparison
4. Agent synthesizes all data

**Response:**
```
Your portfolio is worth $48,230 as of 3:50 PM ET, down 0.3% today (-$145).

Holdings breakdown:
- AAPL (100 sh @ $195): $19,500 (40.4% weight) — Tech sector, 1-day -0.8%
- GOOGL (50 sh @ $165): $8,250 (17.1% weight) — Comms sector, 1-day +1.2%
- NVDA (75 sh @ $148): $11,100 (23.0% weight) — Semis/Tech, 1-day -1.5%

Sector perspective: Your portfolio is heavily weighted to Technology (XLK),
which is currently -1.2% for the day. Consider sector diversification.
```

### 6.3 Example Query 3: Options Strategy

**Query:**
```
I'm interested in selling covered calls on TSLA. What are the latest
options quotes for April expiry?
```

**Expected behavior:**
1. Agent calls `market_get_options_chain("TSLA", "2026-04-17")`
2. Returns all calls/puts with Greeks (delta, theta, IV)
3. Agent formats for decision-making

**Response:**
```
TSLA April 2026 options (underlying: $248.75):

Recommended covered call strikes:
- 250 Call: Bid $8.50 | Ask $8.80 | IV 42% | Delta 0.65 | Theta 0.24
- 255 Call: Bid $6.20 | Ask $6.55 | IV 41% | Delta 0.52 | Theta 0.21
- 260 Call: Bid $4.10 | Ask $4.35 | IV 39% | Delta 0.40 | Theta 0.18

Selling the $255 call nets $6.37/sh annualized income over 6 weeks.
```

### 6.4 Example Query 4: Macro Analysis

**Query:**
```
What are the current Fed funds rate, inflation, and unemployment?
How does this compare to company guidance in our policy documents?
```

**Expected behavior:**
1. Agent calls `market_get_macro(["fed_funds_rate", "cpi_yoy", "unemployment"])`
2. Agent searches RAG for policy docs mentioning rates/inflation
3. Synthesizes comparison

**Response:**
```
Current Economic Snapshot (as of March 11, 2026):
- Federal Funds Rate: 5.25% (up 25bp from prior month)
- CPI YoY: 2.8% (cooling from 3.1%)
- Unemployment: 3.9% (slightly up from 3.8%)

Our company guidance assumes a 4.5% fed rate and 2.5% inflation.
We're currently slightly above both projections, which may pressure
near-term margins but could ease by Q3 if trends continue.
```

### 6.5 Testing Checklist

Before deploying to production:

- [ ] All 8 tool endpoints are registered in Foundry Actions
- [ ] Server URL is correct (public endpoint, not localhost)
- [ ] Agent can invoke each tool independently (test via chat)
- [ ] Agent synthesizes RAG + Action data correctly
- [ ] Error handling works (invalid ticker, network timeout)
- [ ] Response latency is acceptable (<5 sec per query)
- [ ] No authentication errors (CORS, headers, etc.)

---

## Section 7: Resource Locks (Preventing Accidental Deletion)

### 7.1 The Problem

With Contributor role, you can create and manage resources, but you **cannot** create resource locks. This is a critical limitation for production environments.

### 7.2 The Solution: Resource Lock with Owner Role

A resource lock prevents accidental deletion. To apply a CanNotDelete lock:

**Option A: Via Azure CLI (if you have Owner role)**

```bash
az lock create \
  --name Protect<your-resource-group> \
  --lock-type CanNotDelete \
  --resource-group <your-resource-group> \
  --notes "Protect demo environment from accidental deletion"
```

**Verify lock was created:**
```bash
az lock list --resource-group <your-resource-group>
```

**Expected output:**
```
[
  {
    "id": "/subscriptions/xxx/resourceGroups/<your-resource-group>/providers/Microsoft.Authorization/locks/Protect<your-resource-group>",
    "name": "Protect<your-resource-group>",
    "type": "Microsoft.Authorization/locks",
    "level": "CanNotDelete",
    "notes": "Protect demo environment from accidental deletion"
  }
]
```

**Option B: Via Azure Portal (if you have Owner role)**

1. Go to your resource group (e.g., `<your-resource-group>`)
2. Left sidebar → **Locks**
3. Click **+ Add**
4. Fill in:
   - **Lock name**: `Protect<your-resource-group>`
   - **Lock type**: `Delete`
   - **Notes**: `Protect demo environment from accidental deletion`
5. Click **OK**

### 7.3 Understanding Lock Levels

| Lock Type | Effect | Role Required |
|-----------|--------|---------------|
| **CanNotDelete** | Authorized users can read and modify, but not delete | Owner |
| **ReadOnly** | Authorized users can only read, no modifications | Owner |

### 7.4 Removing a Lock

If you need to delete the resource later:

**CLI:**
```bash
az lock delete \
  --name Protect<your-resource-group> \
  --resource-group <your-resource-group>
```

**Portal:**
1. Go to Locks tab
2. Select the lock
3. Click Delete

### 7.5 Who Can Create Locks?

Only **Subscription Owner** or **Owner** at the resource group level. If you don't have Owner role:

1. Contact your subscription owner
2. Ask them to run the CLI command above
3. Or request Owner role for your account (security review required)

---

## Section 8: Troubleshooting

### 8.1 Network Connectivity Issues

**Problem:** Agent cannot reach the MCP server (timeout, connection refused)

**Diagnosis:**
```bash
# Test connectivity from your local machine
curl -v http://localhost:8000/tools/market_get_quote \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"ticker": "AAPL"}'

# From the Foundry environment, check:
# - Server URL in OpenAPI spec
# - Firewall rules (inbound 8000 or 443)
# - VNet settings (if on private network)
```

**Solutions:**
- Verify MCP server is running: `python capital_markets_mcp.py`
- Check server logs for errors
- Verify public URL is correct (ngrok/Container Apps/App Service)
- Check firewall allows inbound traffic on port 8000 or 443
- If using VPN/VNet, ensure Foundry can reach the server subnet

### 8.2 CORS Errors

**Problem:** Agent receives CORS error when calling tool

**Symptom in logs:**
```
Access-Control-Allow-Origin header missing
CORS policy blocks request
```

**Solution:** Add CORS headers to MCP server

**Flask example:**
```python
from flask_cors import CORS
from flask import Flask

app = Flask(__name__)
CORS(app, resources={r"/tools/*": {"origins": "*"}})

@app.route('/tools/market_get_quote', methods=['POST'])
def quote():
    # ... your code
```

**FastAPI example:**
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### 8.3 Authentication Failures

**Problem:** "401 Unauthorized" or "403 Forbidden"

**Causes:**
- Missing API key (if configured)
- Invalid credentials passed to external APIs (Yahoo Finance, FRED)
- Firewall rule blocking Foundry IP

**Solutions:**
1. Verify OpenAPI spec auth method matches server implementation
2. Check API keys for external services (yfinance, FRED)
3. Ensure Foundry has network access (firewall, NSG rules)
4. Test with curl from Foundry environment:
   ```bash
   curl https://your-server.azurecontainerapps.io/tools/market_get_quote \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"ticker": "AAPL"}'
   ```

### 8.4 Tool Schema Validation Errors

**Problem:** Foundry rejects the OpenAPI spec with validation error

**Common issues:**
- Invalid JSON syntax in `openapi_spec.json`
- Missing required fields (operationId, requestBody, responses)
- Mismatched parameter types
- Invalid server URL format

**Diagnosis:**
1. Validate JSON syntax:
   ```bash
   python -m json.tool openapi_spec.json
   ```

2. Use an OpenAPI validator:
   ```bash
   npm install -g openapi-enforcer-cli
   openapi-enforcer validate openapi_spec.json
   ```

3. Check Foundry error message — it typically points to the problematic field

**Solution:**
- Fix JSON syntax errors
- Ensure all endpoints have `operationId`, `requestBody`, `responses`
- Match schema types to actual server responses
- Test with a simpler spec first, add complexity gradually

### 8.5 Tool Not Appearing in Agent

**Problem:** After adding action, tools don't show up in agent

**Causes:**
- Action creation failed silently
- Tool schema has validation errors
- Insufficient permissions

**Solutions:**
1. Check action was created:
   ```bash
   az ai agent action list --resource-group MyResourceGroup
   ```

2. Re-try adding the action, watch for error messages
3. Check Foundry activity log (Portal → Activity Log)
4. Verify you have Contributor+ role on the project
5. Try adding a simpler action first (single endpoint)

### 8.6 Slow Response Times

**Problem:** Agent takes >10 seconds to respond

**Causes:**
- MCP server is slow
- Network latency (geographic distance)
- External API throttling (Yahoo Finance, FRED)
- Agent is calling multiple tools

**Solutions:**
- Profile MCP server response times:
  ```bash
  time curl http://localhost:8000/tools/market_get_quote \
    -X POST \
    -d '{"ticker": "AAPL"}'
  ```

- Cache results (implement Redis caching in MCP)
- Use Container Apps auto-scaling
- Request quota increase from external APIs
- Optimize agent prompt to reduce unnecessary tool calls

### 8.7 Invalid Response Format

**Problem:** "Tool returned invalid JSON" or type mismatch

**Causes:**
- MCP server response doesn't match OpenAPI schema
- Missing required fields in response
- Wrong data type (string vs number)

**Solution:**
1. Test tool directly:
   ```bash
   curl http://localhost:8000/tools/market_get_quote \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"ticker": "AAPL"}'
   ```

2. Compare response structure to OpenAPI `responses` schema
3. Ensure all required fields are present
4. Fix data types (e.g., price should be number, not string)
5. Update OpenAPI spec if server response changed

### 8.8 Debugging Workflow

When troubleshooting, follow this sequence:

```
1. Is the server running?
   → Test with curl from local machine

2. Is the server reachable from Foundry?
   → Test from Foundry console (if available)
   → Check firewall/NSG rules

3. Does the server respond correctly?
   → Compare response to OpenAPI schema
   → Check logs for errors

4. Is the OpenAPI spec valid?
   → Validate JSON syntax
   → Use OpenAPI validator tool

5. Can Foundry parse the spec?
   → Check Foundry error messages
   → Try simpler spec

6. Can agent call the tool?
   → Test via agent chat
   → Check agent logs
```

---

## Summary

You now have:

1. **OpenAPI Specification** (`openapi_spec.json`) — Valid, production-ready spec with 8 endpoints
2. **Deployment Options** — Local (ngrok), Container Apps, App Service
3. **Integration Steps** — Register tools in Foundry Actions in ~5 minutes
4. **Testing Approach** — Hybrid queries combining RAG + live data
5. **SDK Alternative** — Python function registration without HTTP server
6. **Resource Protection** — Lock strategy for production environments
7. **Troubleshooting Guide** — Solutions for common issues

**Next Steps:**
- [ ] Deploy MCP server (Option A, B, or C)
- [ ] Update server URL in `openapi_spec.json`
- [ ] Add Capital Markets API as Action in Foundry
- [ ] Test with example queries (Section 6)
- [ ] Request Owner role for resource locks (Section 7)
- [ ] Set up monitoring and logging

For additional help, refer to the troubleshooting section or consult Azure AI documentation.
