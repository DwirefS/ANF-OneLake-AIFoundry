# Automated Deployment — Zero-Copy RAG Workshop

This folder contains everything needed to deploy the entire Zero-Copy RAG pipeline automatically — from bare Azure subscription to a fully functional AI agent grounded on enterprise financial data. After running a single deployment script, you can go directly to Azure AI Foundry and start chatting with an agent that answers questions about your data.

> **Complete Deployment Guide:** For the full guide with architecture deep-dive, file-by-file explanations, end-to-end instructions, technical feasibility analysis, and troubleshooting, see **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**.

---

## What This Automation Does

The hands-on lab takes **2-3 hours** of manual, portal-based work across four Azure services and Microsoft Fabric. This automation **reduces that to a single command that runs for ~20-30 minutes** — no portal clicks, no RDP sessions, no manual wizard configurations.

Every step that was previously manual is now automated:

| Lab Step (Manual) | Automation Approach | How It Was Automated |
|---|---|---|
| Create VNet + subnets via Azure Portal | Bicep module (`networking.bicep`) | Infrastructure-as-Code, one `az deployment group create` command |
| Create ANF account, pool, volume via Portal | Bicep module (`anf.bicep`) | Declarative resource definitions with proper subnet delegation |
| Enable Object REST API + create bucket via Portal | PowerShell script (`02-configure-anf-bucket.ps1`) | Azure Management REST API (`PUT .../buckets/{name}`) |
| Generate TLS certificate with `openssl` | PowerShell script (`02-configure-anf-bucket.ps1`) | Auto-generated self-signed cert if not provided; can also accept user-provided cert |
| Generate S3 credentials via Portal | PowerShell script (`02-configure-anf-bucket.ps1`) | REST API call to `generateCredentials` endpoint |
| Upload test data via AWS CLI manually | PowerShell script (`03-upload-data.ps1`) | `aws s3 sync` against S3-compatible endpoint with auto-configured credentials |
| RDP into VM, download gateway, install, register | PowerShell + `az vm run-command` (`install-gateway.ps1`) | Silent install (`/quiet ACCEPTEULA=yes`) + service principal registration via `DataGateway` PS module |
| Create Fabric workspace via Portal | PowerShell script (`04-configure-fabric.ps1`) | Fabric REST API with OAuth2 `client_credentials` flow |
| Create Lakehouse via Fabric Portal | PowerShell script (`04-configure-fabric.ps1`) | Fabric REST API (`POST .../lakehouses`) with async polling |
| Create S3 connection via Fabric Portal wizard | PowerShell script (`04-configure-fabric.ps1`) | Fabric REST API with gateway discovery + connection type detection |
| Create OneLake shortcut via Fabric Portal | PowerShell script (`04-configure-fabric.ps1`) | Fabric REST API (`POST .../shortcuts`) |
| Configure AI Search data source via Import Wizard | PowerShell script (`05-configure-ai-search.ps1`) | AI Search REST API (`PUT .../datasources/...`) |
| Configure AI Search index via Import Wizard | JSON config (`ai-search-index.json`) + PowerShell | AI Search REST API with externalized index schema |
| Configure AI Search skillset via Import Wizard | PowerShell script (`05-configure-ai-search.ps1`) | AI Search REST API with 3-skill pipeline defined in code |
| Configure AI Search indexer via Import Wizard | PowerShell script (`05-configure-ai-search.ps1`) | AI Search REST API with image extraction + Document Intelligence enabled |
| Deploy AI Services + models via Portal | Bicep module (`ai-services.bicep`) | GPT-4o and text-embedding-3-small deployed declaratively |
| Create AI Foundry Hub + Project via Portal | Bicep module (`ai-foundry.bicep`) | Hub, Project, connections, Storage Account, Key Vault — all in Bicep |
| Create AI Agent via AI Foundry Portal | PowerShell script (`06-configure-agent.ps1`) | AI Foundry REST API (`POST .../openai/assistants`) with search tool binding |
| Test agent in Portal playground | PowerShell script (`06-configure-agent.ps1`) | Automated test query with thread creation, message posting, and response polling |

**The only remaining manual prerequisite:** creating a service principal and enabling two Fabric tenant settings (required once per tenant, cannot be automated via API).

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                              DEPLOYMENT TIME (deploy.ps1)                                 │
│                                                                                           │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌────────────┐ │
│  │  Azure NetApp   │────▶│  Microsoft       │────▶│  Azure AI        │────▶│  Azure AI  │ │
│  │  Files          │     │  Fabric OneLake  │     │  Search          │     │  Foundry   │ │
│  │                 │     │                  │     │                  │     │            │ │
│  │  • NFS Volume   │     │  • Workspace     │     │  • OneLake       │     │  • Hub     │ │
│  │  • S3 Bucket    │     │  • Lakehouse     │     │    Data Source   │     │  • Project │ │
│  │  • TLS Cert     │     │  • S3 Connection │     │  • 3-Skill       │     │  • Agent   │ │
│  │  • Credentials  │     │  • OneLake       │     │    Skillset      │     │  • GPT-4o  │ │
│  │  • Test Data    │     │    Shortcut      │     │  • Vector Index  │     │  • Search  │ │
│  │                 │     │                  │     │  • Indexer       │     │    Tool    │ │
│  └────────┬────────┘     └────────┬─────────┘     └──────────────────┘     └────────────┘ │
│           │                       │                                                       │
│      S3-Compatible            Data Gateway VM                                             │
│      Object REST API         (Windows Server)                                             │
│                              Silent Install +                                             │
│                              SP Registration                                              │
└───────────────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                                  QUERY TIME (User in AI Foundry)                          │
│                                                                                           │
│  User Question ──▶ AI Agent (GPT-4o) ──▶ AI Search (vector + semantic) ──▶ Answer + Cite  │
│                                                                                           │
│  Note: At query time, the agent ONLY talks to the AI Search index.                        │
│  It never touches S3, OneLake, or ANF directly. The data was already                      │
│  indexed and vectorized during deployment.                                                │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## End-to-End Data Flow

Understanding how data moves through the system is key to understanding why this architecture works:

### During Deployment (automated)

```
1. ANF NFS Volume                    Files exist on ANF storage (invoices, CSVs)
       │
       ▼
2. ANF Object REST API               S3-compatible endpoint exposes files as objects
       │                              (GetObject, ListObjects — that's all we need)
       ▼
3. Data Gateway VM                    Bridges VNet-isolated Object endpoint to Fabric SaaS
       │                              (installed silently, registered via service principal)
       ▼
4. Fabric OneLake Shortcut           Zero-copy virtualization — files appear in OneLake
       │                              without any data movement or duplication
       ▼
5. AI Search OneLake Indexer          Reads files through OneLake, extracts content
       │
       ▼
6. AI Search Skillset Pipeline        3-skill processing chain (see below)
       │
       ▼
7. AI Search Vector Index             Chunked, vectorized, semantically searchable content
       │
       ▼
8. AI Foundry Agent                   GPT-4o agent with azure_ai_search tool binding
```

### During Query Time (user interaction)

```
User Question → AI Agent (GPT-4o) → AI Search Query → Retrieve Chunks → Generate Answer
```

The agent queries the pre-built AI Search index using vector + semantic search, retrieves the most relevant chunks, and generates a grounded answer with citations. **No S3 operations occur at query time.**

---

## AI Search Skillset Pipeline — 3 Native Built-In Skills

The automation configures a document processing pipeline using **three native Azure AI Search built-in skills**. No custom skills, no external microservices — everything runs through services we already deploy:

```
┌──────────────────────────┐         ┌─────────────────────┐         ┌──────────────────────┐
│  1. Document Intelligence│         │  2. Split Skill     │         │  3. Embedding Skill  │
│     Layout Skill         │         │                     │         │                      │
│                          │         │  Chunks extracted   │         │  Generates 1536-dim  │
│  Built-in AI Search skill│         │  Markdown into      │         │  vectors using       │
│  (Util.DocumentIntel-    │────────▶│  ~2000 char pages   │────────▶│  text-embedding-     │
│   ligenceLayoutSkill)    │         │  with 500 char      │         │  3-small             │
│                          │         │  overlap            │         │                      │
│  Extracts structured     │         │                     │         │  Powered by AI       │
│  content as Markdown:    │         │  Context:           │         │  Services (same      │
│  tables, headings,       │         │  /extractedContent/*│         │  resource)           │
│  key-value pairs, OCR    │         │                     │         │                      │
│                          │         │                     │         │  Context:            │
│  Powered by AI Services  │         │                     │         │  /extractedContent/  │
│  (same multi-service     │         │                     │         │   */chunks/*         │
│   account as embeddings) │         │                     │         │                      │
└──────────────────────────┘         └─────────────────────┘         └──────────────────────┘
```

**Why this pipeline?** Financial documents come in many forms:
- **PDF invoices** with tables, logos, and mixed layouts → Document Intelligence extracts structured Markdown
- **Scanned documents** or image-based PDFs → Document Intelligence handles OCR internally
- **HTML/CSV/text files** → Document Intelligence processes raw file bytes

All three skills are **native Azure AI Search built-in skills** — not custom skills or external services. Document Intelligence Layout runs through the AI Services multi-service account (`kind: AIServices`) we already deploy, using the same endpoint and key as the embedding model. The indexer is configured with `allowSkillsetToReadFileData: true` to provide raw file bytes to the Layout skill.

### Index Schema

The search index (`ai-search-index.json`) stores:
- `chunk_id` — Unique key (auto-generated from projection)
- `parent_id` — Links chunks back to source document
- `chunk` — Text content (searchable with Lucene analyzer)
- `title` — Source filename (filterable)
- `source_url` — Original document path (retrievable for citations)
- `vector` — 1536-dimensional embedding (HNSW algorithm, cosine similarity)

Plus **semantic search** configuration for re-ranking results using the `chunk` content field.

---

## What Gets Deployed

### Azure Resources (via Bicep)

| Resource | Module | Purpose |
|----------|--------|---------|
| Virtual Network + 2 subnets | `networking.bicep` | Default subnet for VM, ANF-delegated subnet for volumes |
| Network Security Group | `networking.bicep` | RDP + HTTPS inbound rules for gateway VM |
| NetApp Account | `anf.bicep` | Container for ANF resources |
| Capacity Pool (2 TiB, Standard) | `anf.bicep` | Storage pool for volumes |
| NFS Volume (100 GiB, NFSv3) | `anf.bicep` | Actual file storage for financial data |
| Windows Server 2022 VM | `gateway-vm.bicep` | Hosts On-Premises Data Gateway software |
| Public IP (Static, Standard SKU) | `gateway-vm.bicep` | Allows gateway to communicate with Fabric SaaS |
| AI Search Service (Basic SKU) | `ai-search.bicep` | Search and indexing with system-assigned managed identity |
| AI Services Account (S0) | `ai-services.bicep` | Multi-service account for GPT-4o, embeddings, Document Intelligence |
| GPT-4o Deployment | `ai-services.bicep` | Chat model for the AI agent |
| text-embedding-3-small Deployment | `ai-services.bicep` | Embedding model for vector generation |
| AI Foundry Hub | `ai-foundry.bicep` | Central hub with AI Services + AI Search connections |
| AI Foundry Project | `ai-foundry.bicep` | Workspace for the AI agent |
| Storage Account | `ai-foundry.bicep` | Required dependency for AI Hub |
| Key Vault | `ai-foundry.bicep` | Required dependency for AI Hub |
| RBAC: Cognitive Services OpenAI User | `ai-services.bicep` | Grants user access to AI Services |

### Azure Resources (via PowerShell REST API)

| Resource | Script | Why Not Bicep? |
|----------|--------|----------------|
| ANF S3 Bucket | `02-configure-anf-bucket.ps1` | Object REST API is in preview; bucket resource type not yet in Bicep |
| S3 Credentials | `02-configure-anf-bucket.ps1` | Generated via POST action, not a declarative resource |
| TLS Certificate | `02-configure-anf-bucket.ps1` | Auto-generated at deploy time via `openssl` |

### Fabric Resources (via REST API)

| Resource | Script | Why REST API? |
|----------|--------|---------------|
| Fabric Workspace | `04-configure-fabric.ps1` | Fabric is SaaS — not deployable via ARM/Bicep |
| Lakehouse | `04-configure-fabric.ps1` | Fabric REST API with async long-running operation handling |
| S3-Compatible Connection | `04-configure-fabric.ps1` | Gateway-bound connection with auto-detected connection type |
| OneLake Shortcut | `04-configure-fabric.ps1` | Points to ANF bucket via S3 protocol through the gateway |

### AI Search Resources (via REST API)

| Resource | Script | Details |
|----------|--------|---------|
| OneLake Data Source | `05-configure-ai-search.ps1` | Connects to Fabric workspace/lakehouse |
| 3-Skill Skillset | `05-configure-ai-search.ps1` | Document Intelligence Layout → Split → Embed |
| Vector + Semantic Index | `05-configure-ai-search.ps1` | Schema loaded from `ai-search-index.json` |
| Indexer | `05-configure-ai-search.ps1` | Image extraction + Document Intelligence enabled |

### AI Foundry Agent (via REST API)

| Resource | Script | Details |
|----------|--------|---------|
| Financial Auditor Agent | `06-configure-agent.ps1` | GPT-4o with `azure_ai_search` tool, semantic query, top_k=5 |
| Verification Test | `06-configure-agent.ps1` | Creates thread, sends test query, validates grounded response |

---

## Automation Techniques Used

This section details the specific engineering decisions made to close the automation loop:

### 1. Bicep for Declarative Infrastructure
All Azure resources that support ARM are deployed via Bicep modules. The main template (`main.bicep`) composes six modules with proper dependency chaining (e.g., AI Foundry Hub depends on AI Services and AI Search outputs). Bicep outputs are captured by the orchestrator and passed to downstream PowerShell scripts.

### 2. Azure REST API for Preview Features
The ANF Object REST API bucket is in preview and not yet available as a Bicep resource type. The script uses the Azure Management REST API directly (`PUT https://management.azure.com/.../buckets/{name}`) with a bearer token from `az account get-access-token`.

### 3. Auto-Generated TLS Certificate
The lab requires manually running `openssl` to generate a certificate. The automation handles this automatically — if no certificate path is provided, `02-configure-anf-bucket.ps1` generates a self-signed cert (`/CN=anf-object-api/O=RAGWorkshop`, 365-day validity, RSA 4096-bit) and uses it for bucket creation. The cert is also passed to the gateway VM for trust store import.

### 4. Silent Gateway Installation via `az vm run-command`
Instead of RDP-ing into the VM:
- The orchestrator (`deploy.ps1`) base64-encodes the gateway install script
- Uses `az vm run-command invoke` to execute it remotely on the VM
- The script downloads the gateway installer, runs it silently (`/quiet ACCEPTEULA=yes`)
- Installs PowerShell 7 if not present (required for the DataGateway module)
- Registers the gateway using `Connect-DataGatewayServiceAccount` with the service principal
- Imports the ANF TLS certificate into the VM's trusted root store

### 5. OAuth2 Client Credentials for Fabric APIs
Fabric is a SaaS service — no ARM/Bicep support. The automation authenticates using an OAuth2 `client_credentials` flow against `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` with scope `https://api.fabric.microsoft.com/.default`. This requires the service principal to have Fabric API permissions (configured as a prerequisite).

### 6. Gateway Auto-Discovery
Instead of requiring the user to provide a gateway ID, `04-configure-fabric.ps1` calls `GET /v1/gateways` to discover the registered gateway automatically. It also auto-detects the S3-compatible connection type by querying `supportedConnectionTypes`.

### 7. Idempotent Resource Creation
Fabric scripts handle `409 Conflict` responses gracefully — if a workspace or lakehouse already exists, the script fetches its ID and continues. This makes the deployment re-runnable without failures.

### 8. Index Projection for Chunked Documents
The skillset uses `indexProjections` to map chunks from `/document/chunks/*` into individual index entries while maintaining a `parent_id` link to the source document. This is done with `projectionMode: generatedKeyAsId` so chunk IDs are auto-generated.

### 9. Automated Agent Verification
After creating the agent, `06-configure-agent.ps1` doesn't just stop — it creates a test thread, sends a sample query ("What is the total spend for vendor OfficeMax across all quarters?"), polls for completion, and prints the agent's response. This verifies the entire pipeline end-to-end: ANF → OneLake → AI Search → Agent → grounded answer.

### 10. Externalized Configuration
The search index schema (`ai-search-index.json`) and agent system prompt (`agent-system-prompt.txt`) are externalized as config files, making them easy to customize without modifying script logic.

---

## Why Only 5-6 S3 Operations Are Enough

ANF's Object REST API supports a limited set of S3 operations compared to AWS S3's hundreds. Here's why that's perfectly sufficient for this scenario:

| Layer | S3 Operations Used | Purpose |
|-------|-------------------|---------|
| **Data upload** (`aws s3 sync`) | `PutObject`, `ListObjects`, `HeadObject` | Upload test files to bucket |
| **OneLake shortcut** | `ListObjects`, `GetObject` | Fabric reads files through S3 protocol |
| **AI Search indexer** | `ListObjects`, `GetObject` (via OneLake) | Indexer reads file content for processing |

**At query time, zero S3 operations occur.** The AI agent queries only the AI Search vector index, which was populated during the indexing phase. This read-heavy, write-once pattern is exactly what ANF's limited S3 API is designed for.

---

## Prerequisites

### 1. Tools Required

| Tool | Purpose | Install |
|------|---------|---------|
| **Azure CLI** | Azure resource management | [Install](https://aka.ms/installazurecli) |
| **PowerShell 7+** | Script execution | [Install](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| **AWS CLI** | Upload data to S3-compatible bucket | [Install](https://aws.amazon.com/cli/) |
| **openssl** | Certificate generation (optional) | Pre-installed on most systems |

### 2. Azure Subscription Requirements

- Azure subscription with **Owner** or **Contributor + User Access Administrator** role
- **Azure NetApp Files Object REST API** preview must be enabled on the subscription ([Request access](https://learn.microsoft.com/en-us/azure/azure-netapp-files/object-rest-api-introduction))
- Region must support GPT-4o (recommended: `eastus2`, `swedencentral`, `westus3`)

### 3. Service Principal

Create a Service Principal for Fabric API access and Data Gateway registration:

```bash
# Create the Service Principal
az ad sp create-for-rbac --name "rag-workshop-sp" --role Contributor \
    --scopes /subscriptions/<SUBSCRIPTION_ID> \
    --query '{appId: appId, password: password, tenant: tenant}' -o json
```

**Required Fabric admin permissions** for the Service Principal:
1. Go to [Fabric Admin Portal](https://app.fabric.microsoft.com/admin-portal)
2. Under **Tenant settings**, enable:
   - "Service principals can use Fabric APIs"
   - "Service principals can create and use gateways"

> **Note:** These two tenant settings are the only manual steps that cannot be automated (Fabric admin portal settings have no API).

### 4. Microsoft Fabric Capacity

You need a Fabric capacity (Trial or paid). Get your capacity ID:
1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. **Settings** → **Admin portal** → **Capacity settings**
3. Copy the capacity ID

### 5. Your User Object ID

```bash
az ad signed-in-user show --query id -o tsv
```

### 6. TLS Certificate (Optional)

The script auto-generates a self-signed certificate if you don't provide one. To provide your own:

```bash
openssl req -x509 -newkey rsa:4096 -keyout private.key -out cert.pem -days 365 -nodes
```

---

## Quick Start

```powershell
cd automation

./deploy.ps1 `
    -SubscriptionId       "00000000-0000-0000-0000-000000000000" `
    -Location             "eastus2" `
    -ResourceGroupName    "rg-rag-workshop" `
    -Prefix               "ragworkshop" `
    -VmAdminPassword      (ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force) `
    -UserObjectId         "00000000-0000-0000-0000-000000000000" `
    -ServicePrincipalAppId "00000000-0000-0000-0000-000000000000" `
    -ServicePrincipalSecret "your-sp-secret" `
    -TenantId             "00000000-0000-0000-0000-000000000000" `
    -FabricCapacityId     "00000000-0000-0000-0000-000000000000"
```

The script takes approximately **20-30 minutes** to complete.

---

## What Happens During Deployment

The orchestrator (`deploy.ps1`) chains all steps, passing outputs from each step to the next:

| Step | Script | Action | Duration |
|------|--------|--------|----------|
| 1 | `01-register-providers.ps1` | Register 5 Azure resource providers (idempotent, skips if already registered) | ~1 min |
| 2 | `deploy.ps1` (inline) | Deploy Bicep template — all Azure infrastructure in one shot | ~15 min |
| 3 | `02-configure-anf-bucket.ps1` | Auto-generate TLS cert, create S3 bucket, generate access credentials | ~2 min |
| 4 | `03-upload-data.ps1` | Upload `test_data/` (invoices + financial statements) to ANF bucket via `aws s3 sync` | ~1 min |
| 5 | `deploy.ps1` (inline) | Install gateway on VM via `az vm run-command` (silent install + SP registration) | ~5 min |
| 6 | `04-configure-fabric.ps1` | Create workspace, lakehouse, discover gateway, create S3 connection, create shortcut | ~2 min |
| 7 | `05-configure-ai-search.ps1` | Create data source, 3-skill skillset, vector index, indexer; run indexer and wait | ~3 min |
| 8 | `06-configure-agent.ps1` | Create AI agent with search tool, run test query to verify grounding | ~1 min |

**Output passing between steps:**
- Step 2 outputs (resource names, endpoints) → Steps 3, 5, 7, 8
- Step 3 outputs (S3 endpoint, credentials, bucket name) → Steps 4, 5, 6
- Step 6 outputs (workspace ID, lakehouse ID) → Step 7
- Step 7 outputs (index name) → Step 8

---

## After Deployment

1. Open **[Azure AI Foundry](https://ai.azure.com)**
2. Navigate to your project
3. Go to **Agents** and select the **Financial-Auditor-Agent**
4. Start chatting! Try these queries:
   - *"What is the total spend for vendor OfficeMax?"*
   - *"Show me all transactions from Q1 2025."*
   - *"List all invoices over $1000."*
   - *"Summarize Q2 expenses by category."*

The agent will search the vector index, retrieve relevant chunks from indexed documents, and provide grounded answers with citations.

---

## Folder Structure

```
automation/
├── deploy.ps1                     # Main orchestrator — chains all 8 steps, passes outputs
├── main.bicep                     # Main Bicep template — composes 6 modules
├── main.bicepparam                # Sample parameters file (uses env vars for secrets)
├── README.md                      # This file
├── DEPLOYMENT_GUIDE.md            # Deep-dive: architecture, feasibility, file reference
├── modules/
│   ├── networking.bicep           # VNet (10.0.0.0/16), default + ANF subnets, NSG
│   ├── anf.bicep                  # NetApp account, capacity pool (2 TiB), NFS volume
│   ├── gateway-vm.bicep           # Windows Server 2022 VM, public IP, NIC
│   ├── ai-search.bicep            # AI Search (Basic), managed identity, semantic search
│   ├── ai-services.bicep          # AI Services (S0), GPT-4o + embedding deployments, RBAC
│   └── ai-foundry.bicep           # Hub, Project, connections, Storage Account, Key Vault
├── scripts/
│   ├── 01-register-providers.ps1  # Registers Microsoft.NetApp, .Search, .CognitiveServices, etc.
│   ├── 02-configure-anf-bucket.ps1# Auto-gen cert, create bucket, generate S3 credentials
│   ├── 03-upload-data.ps1         # Upload test_data/ to ANF bucket via AWS CLI
│   ├── 04-configure-fabric.ps1    # Workspace, lakehouse, gateway discovery, connection, shortcut
│   ├── 05-configure-ai-search.ps1 # Data source, 3-skill skillset, index, indexer
│   ├── 06-configure-agent.ps1     # Create agent, bind search tool, run verification test
│   └── gateway/
│       └── install-gateway.ps1    # Runs ON the VM — silent install + SP registration
└── configs/
    ├── ai-search-index.json       # Index schema (6 fields, HNSW vector, semantic config)
    └── agent-system-prompt.txt    # Financial Auditor role instructions
```

---

## Advanced Options

### Skip Steps

If you need to re-run only part of the deployment:

```powershell
# Skip infrastructure (Bicep already deployed)
./deploy.ps1 ... -SkipInfrastructure

# Skip Fabric configuration (already done)
./deploy.ps1 ... -SkipFabric
```

### Run Individual Scripts

Each step can be run independently (useful for debugging or re-running a failed step):

```powershell
# Register resource providers only
./scripts/01-register-providers.ps1 -SubscriptionId "..."

# Configure ANF bucket only
./scripts/02-configure-anf-bucket.ps1 -SubscriptionId "..." -ResourceGroupName "..." ...

# Re-run AI Search configuration
./scripts/05-configure-ai-search.ps1 -SearchServiceEndpoint "https://..." -SearchAdminKey "..." ...

# Re-create the agent
./scripts/06-configure-agent.ps1 -AiServicesName "..." -ProjectName "..." -IndexName "..." ...
```

### Custom Test Data

Replace the contents of `test_data/` before running the deployment to index your own documents. The pipeline processes PDFs, images, CSVs, and text files.

---

## Cleanup

To remove all deployed resources:

```bash
# Delete the Azure resource group (removes all Azure resources)
az group delete --name rg-rag-workshop --yes --no-wait

# Manually delete the Fabric workspace
# Go to app.fabric.microsoft.com → Workspaces → Financial_RAG_Workshop → Delete
```

> **Note:** Fabric workspaces are SaaS resources not managed by Azure Resource Manager, so they must be deleted separately.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Bicep deployment fails** | Check the Azure portal Activity Log for detailed error messages |
| **ANF bucket creation fails** | Ensure Object REST API preview is enabled on the subscription |
| **Certificate generation fails** | Ensure `openssl` is installed and in your PATH |
| **Gateway registration fails** | Verify the Service Principal has Fabric admin permissions (both tenant settings enabled) |
| **Fabric connection fails** | Ensure the gateway VM has network access to the ANF endpoint (same VNet) |
| **Gateway not discovered** | Wait 30-60 seconds after gateway registration; re-run `04-configure-fabric.ps1` |
| **Indexer returns 0 documents** | Wait a few minutes for OneLake shortcut to sync; re-run the indexer |
| **Agent says "I don't know"** | Verify the indexer completed successfully (`document count > 0` in AI Search portal) |
| **Model deployment fails** | Ensure your region supports GPT-4o; check quota availability in the AI Services portal |
| **OAuth2 token fails** | Verify the service principal secret hasn't expired; re-create if needed |

---

## Differences from the Hands-On Lab

| Aspect | Hands-On Lab (Manual) | Automation |
|--------|----------------------|------------|
| **Approach** | Portal-based, click-by-click | Single script, CLI/API-based |
| **Duration** | 2-3 hours | 20-30 minutes |
| **Certificate** | Manual `openssl` command + portal upload | Auto-generated if not provided |
| **Infrastructure** | Create each resource in Azure Portal | Bicep deploys everything in one shot |
| **ANF Bucket** | Portal wizard to enable Object API | Azure Management REST API |
| **Data Upload** | Manual AWS CLI commands | Scripted `aws s3 sync` with auto-configured credentials |
| **Gateway** | RDP into VM → download → install → register → configure | Silent install via `az vm run-command` + SP registration |
| **Fabric** | Portal wizards for workspace, lakehouse, connection, shortcut | REST API with OAuth2 client_credentials |
| **AI Search** | Import Data wizard (multi-step wizard) | REST API with 3-skill skillset defined in code |
| **AI Agent** | Portal-based creation + manual tool configuration | REST API with automated test verification |
| **Reproducibility** | Must repeat all steps for each deployment | Run the same script with different parameters |
| **Error Handling** | Manual troubleshooting | Script exits on error with descriptive messages |
