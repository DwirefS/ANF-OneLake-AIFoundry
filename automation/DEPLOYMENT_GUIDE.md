# Zero-Copy RAG Workshop — Complete Deployment Guide

This document provides **end-to-end instructions** for deploying the automated Zero-Copy RAG pipeline, including architecture details, file-by-file explanations, prerequisites, deployment steps, post-deployment verification, and technical notes.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [How the Data Flows](#2-how-the-data-flows)
3. [Technical Feasibility Notes](#3-technical-feasibility-notes)
4. [File-by-File Reference](#4-file-by-file-reference)
5. [Pre-Deployment: Prerequisites Checklist](#5-pre-deployment-prerequisites-checklist)
6. [Deployment: Step-by-Step Instructions](#6-deployment-step-by-step-instructions)
7. [Post-Deployment: Verification and First Use](#7-post-deployment-verification-and-first-use)
8. [Operational Notes](#8-operational-notes)
9. [Troubleshooting Reference](#9-troubleshooting-reference)
10. [Cleanup](#10-cleanup)

---

## 1. Architecture Overview

The automation deploys a complete **four-layer pipeline** that enables Azure AI Foundry agents to answer questions grounded on enterprise financial data stored in Azure NetApp Files — without copying the data out of its authoritative storage location.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WHAT GETS DEPLOYED                                  │
│                                                                             │
│  LAYER 1: STORAGE                                                           │
│  ┌─────────────────────────────────────┐                                    │
│  │  Azure NetApp Files                 │                                    │
│  │  ├── NetApp Account                 │                                    │
│  │  ├── Capacity Pool (Standard, 2TiB) │                                    │
│  │  ├── NFS Volume (100 GiB)           │                                    │
│  │  └── S3-Compatible Bucket           │  ← Test data uploaded here         │
│  │      (Object REST API)              │                                    │
│  └─────────────────────────────────────┘                                    │
│                    │ HTTPS (S3 protocol)                                     │
│                    ▼                                                         │
│  LAYER 2: INTEGRATION                                                       │
│  ┌─────────────────────────────────────┐                                    │
│  │  Windows VM (Data Gateway)          │  ← Bridges VNet to Fabric          │
│  │  └── On-Premises Data Gateway       │                                    │
│  └────────────────┬────────────────────┘                                    │
│                    │                                                         │
│  ┌────────────────▼────────────────────┐                                    │
│  │  Microsoft Fabric                   │                                    │
│  │  ├── Workspace                      │                                    │
│  │  ├── Lakehouse                      │                                    │
│  │  ├── S3-Compatible Connection       │  ← Uses gateway + ANF credentials  │
│  │  └── OneLake Shortcut               │  ← Virtual view of ANF data        │
│  └─────────────────────────────────────┘                                    │
│                    │ OneLake API                                             │
│                    ▼                                                         │
│  LAYER 3: INDEXING                                                          │
│  ┌─────────────────────────────────────┐                                    │
│  │  Azure AI Search (Basic)            │                                    │
│  │  ├── OneLake Data Source             │  ← Points to Fabric lakehouse     │
│  │  ├── Skillset                       │  ← Chunks text + generates vectors │
│  │  │   ├── SplitSkill (2000 chars)    │                                    │
│  │  │   └── AzureOpenAIEmbeddingSkill  │  ← Uses text-embedding-3-small    │
│  │  ├── Search Index                   │  ← Vector + semantic + keyword     │
│  │  └── Indexer                        │  ← Runs once, re-runnable          │
│  └─────────────────────────────────────┘                                    │
│                    │ Search queries                                          │
│                    ▼                                                         │
│  LAYER 4: INTELLIGENCE                                                      │
│  ┌─────────────────────────────────────┐                                    │
│  │  Azure AI Foundry                   │                                    │
│  │  ├── AI Services (GPT-4o + embed)   │                                    │
│  │  ├── Hub (+ Storage, Key Vault)     │                                    │
│  │  ├── Project                        │                                    │
│  │  │   ├── AI Search Connection       │                                    │
│  │  │   └── AI Services Connection     │                                    │
│  │  └── Financial Auditor Agent        │  ← Ready to chat                   │
│  └─────────────────────────────────────┘                                    │
│                                                                             │
│  NETWORKING                                                                 │
│  ┌─────────────────────────────────────┐                                    │
│  │  VNet (10.0.0.0/16)                 │                                    │
│  │  ├── default subnet (10.0.0.0/24)   │  ← Gateway VM lives here          │
│  │  │   └── NSG (allow RDP + HTTPS)    │                                    │
│  │  └── anf-subnet (10.0.1.0/24)      │  ← ANF delegated subnet            │
│  └─────────────────────────────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Total Azure resources created:** ~15 resources (VNet, NSG, VM, PIP, NIC, NetApp account, pool, volume, AI Search, AI Services, 2 model deployments, Storage Account, Key Vault, AI Hub, AI Project)

**Total Fabric resources created:** 4 (workspace, lakehouse, connection, shortcut)

---

## 2. How the Data Flows

### At Deployment Time (one-time setup)

```
test_data/               S3 PutObject          ANF Volume
(invoices + CSVs)  ─────────────────────▶  /finance-data bucket
                          via AWS CLI

ANF Bucket               S3 ListObjects        OneLake
(finance-data)     ◀─────────────────────  Shortcut reads via
                         + GetObject           Data Gateway

OneLake Shortcut         OneLake API           AI Search Index
(anf_shortcut)     ─────────────────────▶  Indexer extracts text,
                         GetObject             chunks it, generates
                                               vector embeddings
```

### At Query Time (every user interaction)

```
User Question            AI Foundry             AI Search
"What did OfficeMax  ───────────────────▶  Vector + semantic
 charge in Q1?"          Agent sends            hybrid search
                         search query

AI Search Index          Retrieved chunks       AI Foundry Agent
(vector store)     ─────────────────────▶  GPT-4o generates
                         with citations         grounded answer

                                                User sees answer
                                           ◀──  with document citations
```

**Key point:** At query time, the agent talks ONLY to Azure AI Search. It never reaches back to ANF, OneLake, or S3. The search index already contains all the extracted text and vectors from the indexing step.

### What S3 Operations Are Actually Used

| Operation | When | By Whom | Purpose |
|-----------|------|---------|---------|
| `PutObject` | Deployment | AWS CLI script | Upload test data to ANF bucket |
| `ListObjects` | Deployment | OneLake / AI Search indexer | Enumerate files in the bucket |
| `GetObject` | Deployment | OneLake / AI Search indexer | Read file contents for indexing |
| `HeadObject` | Deployment | OneLake | Get file metadata |
| `ListBuckets` | Deployment | OneLake shortcut creation | Discover available buckets |

That's it. All five operations ANF supports. The other 100+ S3 operations (multipart upload, versioning, lifecycle policies, replication, tagging, ACLs, etc.) are irrelevant for this read-heavy RAG pipeline.

---

## 3. Technical Feasibility Notes

### Will This Scenario Work?

**Yes.** Every layer in this pipeline is a documented, supported integration pattern. Microsoft published a specific integration article for the ANF Object REST API → OneLake → AI Search path.

### Why the Limited S3 API Surface Is Sufficient

Azure NetApp Files Object REST API supports approximately 6 core S3 operations: `GetObject`, `PutObject`, `DeleteObject`, `HeadObject`, `ListObjects`/`ListObjectsV2`, and `ListBuckets`.

For this RAG scenario, the S3 layer is used for exactly two purposes:
1. **Data upload** (one-time): `PutObject` to load test data
2. **Data reading** (indexing): `GetObject` + `ListObjects` for the AI Search indexer to read files through OneLake

The vast majority of S3's 200+ API actions exist for enterprise object storage management (versioning, lifecycle, replication, encryption management, access policies, etc.). None of those are needed for a read-oriented data virtualization pipeline.

### Document Intelligence and Complex Document Handling

The skillset pipeline uses the **Document Intelligence Layout** skill — a **native built-in Azure AI Search skill** (`#Microsoft.Skills.Util.DocumentIntelligenceLayoutSkill`). This is not a custom skill or external microservice. It runs through the same AI Services multi-service account we deploy in `ai-services.bicep`.

This matters because in real enterprise scenarios, you'd encounter:

- Scanned PDF invoices (image-based, no selectable text)
- Complex tables in financial reports
- Forms with key-value pairs (invoice numbers, dates, totals)
- Multi-column layouts

The Document Intelligence Layout skill uses AI models specifically trained on document layouts to:
1. **Extract tables** as structured Markdown (preserving rows/columns)
2. **Identify key-value pairs** (e.g., "Invoice Number: INV-3832")
3. **Determine reading order** in multi-column layouts
4. **Convert complex layouts** to clean Markdown with proper heading hierarchy
5. **Handle images within documents** — OCR is performed internally by the Layout model

The skill processes the raw file bytes (via `allowSkillsetToReadFileData = true` on the indexer) and outputs structured Markdown. This output is then chunked by the Split skill and vectorized by the Embedding skill.

**No additional Azure resource needed:** The AI Services multi-service account (kind: `AIServices`) already includes Document Intelligence capabilities. The skillset references it via the `cognitiveServices` key — the same account used for embeddings.

### Where Copies Exist (and Why)

The "zero-copy" label refers to the storage layer. However, Azure AI Search **does** create a copy:
- Extracted text is materialized in the search index
- Vector embeddings are stored in the index
- This is by design — fast retrieval requires a purpose-built index

This is not data duplication in the traditional sense. The search index is a derived, query-optimized representation, not a second copy of the source files.

### Known Limitations and Edge Cases

| Concern | Impact | Mitigation |
|---------|--------|------------|
| Object REST API is in **preview** | API surface could change | Pin to specific API version; test before production |
| Self-signed TLS certificate | Gateway must trust it; expires after 365 days | Script auto-generates; set calendar reminder for renewal |
| AI Search document size limits | Very large files (>16MB) may fail to index | Use reasonably sized files; add Document Intelligence skill for complex PDFs |
| OneLake shortcut metadata caching | New files on ANF may not appear immediately | Re-run the indexer after adding new files |
| Fabric Trial capacity limits | Limited compute and storage | Use paid capacity for production; Trial works for workshop |
| Agent networking | Foundry agents don't support private AI Search endpoints (current limitation) | Keep AI Search public for workshop; use standard agent setup with VNet for production |
| Model deployment quota | GPT-4o has regional quota limits | Check quota before deployment; use alternative region if needed |
| Gateway registration requires PowerShell 7 | DataGateway module doesn't work on PowerShell 5.x | VM script installs PS7 if needed |

---

## 4. File-by-File Reference

### Infrastructure as Code (Bicep)

#### `main.bicep` — Main Orchestrator Template
**What it does:** Composes all Bicep modules into a single deployment. Defines the top-level parameters (location, prefix, VM credentials, user ID) and wires module outputs as inputs to dependent modules.

**Key design decisions:**
- Uses module composition (not a monolithic template) for readability
- AI Services module deploys before AI Foundry (Foundry needs the resource IDs)
- ANF module depends on networking module (needs the delegated subnet ID)
- All outputs are surfaced for use by the PowerShell scripts

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | — | Azure region (must support GPT-4o) |
| `prefix` | string | `ragworkshop` | Name prefix for all resources (3-15 chars, lowercase) |
| `vmAdminUsername` | string | `azureuser` | Gateway VM admin username |
| `vmAdminPassword` | securestring | — | Gateway VM admin password |
| `userObjectId` | string | — | Your Azure AD object ID (for RBAC) |
| `anfPoolSizeTiB` | int | `2` | ANF capacity pool size |
| `anfVolumeQuotaGiB` | int | `100` | ANF volume quota |

#### `main.bicepparam` — Sample Parameters File
**What it does:** Provides a sample parameter file that reads sensitive values from environment variables (`VM_ADMIN_PASSWORD`, `USER_OBJECT_ID`). Edit this file or pass parameters directly on the command line.

---

#### `modules/networking.bicep` — Virtual Network
**What it does:** Creates the network foundation for all resources.

**Resources created:**
- **NSG** (`{prefix}-gateway-nsg`): Allows inbound RDP (3389) and HTTPS (443) for the gateway VM
- **VNet** (`{prefix}-vnet`): Address space `10.0.0.0/16`
  - `default` subnet (`10.0.0.0/24`): For the gateway VM
  - `anf-subnet` (`10.0.1.0/24`): Delegated to `Microsoft.NetApp/volumes` — required for ANF

**Why the ANF subnet delegation matters:** Azure NetApp Files requires a dedicated subnet delegated to the NetApp resource provider. No other resources can be placed in this subnet.

---

#### `modules/anf.bicep` — Azure NetApp Files
**What it does:** Creates the storage foundation — the authoritative system of record for enterprise data.

**Resources created:**
- **NetApp Account** (`{prefix}-netapp`)
- **Capacity Pool** (`{prefix}-pool`): Standard service level, minimum 2 TiB
- **Volume** (`anf-finance-vol`): 100 GiB NFS volume with NFSv3 protocol

**Why NFSv3:** Simpler protocol, widely compatible, sufficient for this use case. NFSv4.1 adds Kerberos authentication which is unnecessary for this workshop.

**Note:** The S3-compatible bucket is NOT created here — it's created by the PowerShell script (`02-configure-anf-bucket.ps1`) because bucket creation requires the preview REST API and certificate upload, which Bicep doesn't cleanly support.

---

#### `modules/gateway-vm.bicep` — Data Gateway VM
**What it does:** Creates a Windows Server VM that will host the On-Premises Data Gateway.

**Resources created:**
- **Public IP** (`{prefix}-gateway-pip`): Static, Standard SKU — for RDP access and internet connectivity
- **NIC** (`{prefix}-gateway-nic`): Connected to the default subnet
- **VM** (`{prefix}-gateway-vm`): Windows Server 2022 Datacenter, Standard_D2s_v3

**Why this VM exists:** Microsoft Fabric requires a Data Gateway to access private/VNet-isolated S3-compatible endpoints. The gateway software runs as a Windows service and bridges connectivity between OneLake and the ANF Object REST API endpoint. Azure NetApp Files itself does not require a gateway.

**The gateway software is NOT installed by Bicep.** Installation happens in a later step via the `install-gateway.ps1` script executed through `az vm run-command`.

---

#### `modules/ai-search.bicep` — Azure AI Search
**What it does:** Creates the search service that will index and store vectors.

**Resources created:**
- **Search Service** (`{prefix}-search`): Basic SKU with system-assigned managed identity, semantic search enabled

**Why Basic tier:** Basic is the minimum tier that supports semantic search, which improves retrieval quality for RAG. Standard tier works too but costs more.

**The managed identity** is critical — it's used to authenticate to the Fabric workspace when the indexer reads data from OneLake.

---

#### `modules/ai-services.bicep` — Azure AI Services + Models
**What it does:** Creates the AI runtime and deploys the language and embedding models.

**Resources created:**
- **AI Services Account** (`{prefix}-ai-services`): Multi-service account (kind: `AIServices`), Standard S0 tier
- **GPT-4o Deployment** (`gpt-4o`): The language model used by the agent for reasoning
- **Embedding Deployment** (`text-embedding-3-small`): The embedding model used during indexing to generate vector representations

**Why sequential deployment:** Azure enforces that model deployments within the same account must be created one at a time. The embedding deployment has an explicit `dependsOn` on the GPT-4o deployment.

**RBAC:** This module also creates a `Cognitive Services OpenAI User` role assignment for the user — required for the user to interact with the models through the Foundry portal.

---

#### `modules/ai-foundry.bicep` — AI Foundry Hub + Project
**What it does:** Creates the AI Foundry workspace hierarchy and connects it to AI Search and AI Services.

**Resources created:**
- **Storage Account** (`{prefix}hubstore`): Required dependency for the AI Hub (stores experiment data, logs)
- **Key Vault** (`{prefix}-hub-kv`): Required dependency for the AI Hub (stores secrets, connection strings)
- **AI Hub** (`{prefix}-hub`): The top-level workspace (kind: `Hub`) with system-assigned managed identity
- **AI Services Connection**: Links the Hub to the AI Services account (AAD auth)
- **AI Search Connection**: Links the Hub to the AI Search service (AAD auth)
- **AI Project** (`{prefix}-project`): The working project (kind: `Project`) under the Hub

**Why Hub + Project:** AI Foundry uses a two-level hierarchy. The Hub owns shared resources (connections, compute). The Project is where agents, evaluations, and experiments live. Connections defined at the Hub level are inherited by all Projects.

---

### PowerShell Scripts

#### `deploy.ps1` — Main Orchestrator
**What it does:** This is the single script you run. It chains all deployment steps in order, passing outputs from each step as inputs to the next.

**Execution flow:**
```
1. Validate prerequisites (Azure CLI, AWS CLI, etc.)
2. Set Azure subscription context
3. Call 01-register-providers.ps1
4. Create resource group + deploy Bicep template
5. Extract Bicep outputs (resource names, IDs, endpoints)
6. Call 02-configure-anf-bucket.ps1 → get endpoint, access key, secret key
7. Call 03-upload-data.ps1 → upload test_data/ to ANF bucket
8. Run install-gateway.ps1 on the VM via az vm run-command
9. Call 04-configure-fabric.ps1 → get workspace ID, lakehouse ID
10. Retrieve AI Search admin key and AI Services key via Azure CLI
11. Call 05-configure-ai-search.ps1 → get index name
12. Call 06-configure-agent.ps1 → get agent ID
13. Print success banner with portal URL
```

**Parameters:** See the [Quick Start](#6-deployment-step-by-step-instructions) section below.

**Skip flags:**
- `-SkipInfrastructure`: Skip Bicep deployment (use if already deployed)
- `-SkipFabric`: Skip Fabric configuration (use if already configured)

---

#### `scripts/01-register-providers.ps1` — Register Resource Providers
**What it does:** Ensures all five required Azure resource providers are registered on the subscription.

**Providers registered:**
- `Microsoft.NetApp` — Azure NetApp Files
- `Microsoft.Search` — Azure AI Search
- `Microsoft.CognitiveServices` — Azure AI Services / OpenAI
- `Microsoft.MachineLearningServices` — Azure AI Foundry
- `Microsoft.Fabric` — Microsoft Fabric

**Idempotent:** If a provider is already registered, it's skipped.

---

#### `scripts/02-configure-anf-bucket.ps1` — Create ANF Object Bucket
**What it does:** Creates the S3-compatible bucket on the ANF volume and generates access credentials.

**Steps:**
1. If no certificate is provided, generates a self-signed X.509 certificate using `openssl`
2. Reads the certificate PEM content
3. Creates the bucket via the Azure ARM REST API (`PUT .../volumes/{vol}/buckets/{bucket}`)
4. Generates access credentials (access key + secret key) via REST API
5. Returns the endpoint URL, access key, secret key, and certificate path

**Why REST API instead of Bicep:** The ANF bucket creation with certificate upload works most reliably through the REST API. The bucket resource is preview-only and requires the certificate content inline.

---

#### `scripts/03-upload-data.ps1` — Upload Test Data
**What it does:** Uploads the `test_data/invoices/` and `test_data/financial_statements/` directories to the ANF S3 bucket using the AWS CLI's `s3 sync` command.

**Uses `--no-verify-ssl`** because the ANF endpoint uses a self-signed certificate. In production, you'd import the certificate to the system trust store instead.

**The test data includes:**
- 10 HTML invoices from vendors (OfficeMax, Azure Cloud Services, WeWork, Dell, Staffing Agency)
- 2 CSV financial statements (Q1 and Q2 2025 expenses, ~50 transactions each)

---

#### `scripts/gateway/install-gateway.ps1` — Gateway Installation
**What it does:** Runs ON the gateway VM (not on your local machine). Installs and registers the On-Premises Data Gateway.

**Steps:**
1. Downloads the gateway installer from Microsoft
2. Runs silent installation (`/quiet ACCEPTEULA=yes`)
3. Installs PowerShell 7 if not present (DataGateway module requires PS7+)
4. Installs the `DataGateway` PowerShell module
5. Authenticates using the Service Principal (`Connect-DataGatewayServiceAccount`)
6. Registers the gateway (`Install-DataGateway -RegionKey`)
7. Optionally imports the ANF TLS certificate to the Windows trusted root store

**How it's invoked:** The main `deploy.ps1` script runs this on the VM using `az vm run-command invoke`, which executes PowerShell commands remotely on the VM without needing RDP.

---

#### `scripts/04-configure-fabric.ps1` — Configure Microsoft Fabric
**What it does:** Creates all Fabric resources using the Fabric REST API.

**Steps:**
1. Authenticates to Fabric using the Service Principal (OAuth2 client_credentials flow)
2. Creates workspace `Financial_RAG_Workshop` (or finds existing)
3. Creates lakehouse `FinDataLake` (or finds existing)
4. Discovers the registered Data Gateway
5. Creates an S3-compatible connection using the gateway + ANF credentials
6. Creates a OneLake shortcut `anf_shortcut` pointing to the ANF bucket

**Why Fabric REST API:** Fabric is a SaaS service. It cannot be deployed via ARM/Bicep. The only automation path is the Fabric REST API (`api.fabric.microsoft.com/v1/...`).

**Authentication:** Uses OAuth2 client credentials flow with the Service Principal. The SP must have Fabric API permissions granted by the Fabric admin.

---

#### `scripts/05-configure-ai-search.ps1` — Configure AI Search
**What it does:** Creates the search data source, skillset (with Document Intelligence), index, and indexer — then runs the indexer and waits for completion.

**Resources created via REST API:**
1. **Data Source** (`onelake-datasource`): Type `onelake`, pointing to the Fabric workspace and lakehouse, scoped to the shortcut folder
2. **Skillset** (`rag-workshop-skillset`): A 3-skill pipeline using native built-in Azure AI Search skills:

   ```
   Document → Document Intelligence Layout → Split → Embedding → Index
   ```

   | Skill | OData Type | Purpose |
   |-------|------------|---------|
   | **Document Intelligence Layout** | `Microsoft.Skills.Util.DocumentIntelligenceLayoutSkill` | Built-in AI Search skill. Extracts structured content (tables, key-value pairs, headings) as Markdown from PDFs, Office docs, images, and HTML. Handles OCR internally. |
   | **Text Splitter** | `Microsoft.Skills.Text.SplitSkill` | Chunks the extracted Markdown into ~2000 character pages with 500 character overlap |
   | **Embedding** | `Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill` | Generates 1536-dimensional vectors for each chunk using `text-embedding-3-small` |

   **All three skills are native Azure AI Search built-in skills.** Document Intelligence Layout runs through the AI Services multi-service account (same resource used for embeddings). No external microservices or custom skills needed.

   **Index projections**: Maps parent documents to child chunks with parent-child key relationships (`projectionMode: generatedKeyAsId`)

3. **Index** (`rag-workshop-index`): Fields include `chunk` (searchable text), `vector` (1536-dim HNSW), `title`, `source_url`, and `parent_id`. Configured with semantic search.
4. **Indexer** (`rag-workshop-indexer`): Runs once, extracts content and metadata, provides raw file bytes to the skillset (`allowSkillsetToReadFileData: true`), passes content through the 3-skill pipeline

**After creation:** The script runs the indexer and polls for completion (up to 5 minutes). It reports the number of documents indexed.

---

#### `scripts/06-configure-agent.ps1` — Create AI Foundry Agent
**What it does:** Creates a GPT-4o agent in AI Foundry that is grounded on the AI Search index.

**Steps:**
1. Gets an access token for AI Foundry (`az account get-access-token --resource https://ai.azure.com`)
2. Reads the agent system prompt from `configs/agent-system-prompt.txt`
3. Creates the agent via REST API (`POST /assistants`) with:
   - Model: `gpt-4o`
   - Tool: `azure_ai_search` pointing to the index
   - Instructions: Financial Auditor system prompt
4. Creates a test thread and sends a sample query ("What is the total spend for vendor OfficeMax?")
5. Polls for the response and displays it

---

### Configuration Files

#### `configs/ai-search-index.json` — Search Index Schema
**What it contains:** The JSON schema definition for the AI Search index, including:
- `chunk_id` (key field, auto-generated)
- `parent_id` (links chunks to source documents)
- `chunk` (the actual text content, searchable with Lucene analyzer)
- `title` (source file name)
- `source_url` (source file path for citations)
- `vector` (1536-dimensional HNSW vector with cosine similarity)
- Semantic search configuration on the `chunk` field

#### `configs/agent-system-prompt.txt` — Agent System Prompt
**What it contains:** The instructions given to the GPT-4o agent:
- Role: Financial Auditor
- Behavior: Always cite document names, calculate totals from CSV rows
- Data context: Describes the invoices and financial statements available

---

## 5. Pre-Deployment: Prerequisites Checklist

Complete ALL of the following before running the deployment script.

### A. Install Required Tools

Run these on the machine where you will execute the deployment (your local workstation or a cloud shell):

```bash
# 1. Azure CLI
# macOS
brew install azure-cli
# Windows
winget install Microsoft.AzureCLI
# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 2. PowerShell 7+
# macOS
brew install powershell/tap/powershell
# Windows — already included or install from:
# https://aka.ms/install-powershell
# Linux
sudo apt-get install -y powershell

# 3. AWS CLI (for S3 data upload)
# macOS
brew install awscli
# Windows
winget install Amazon.AWSCLI
# Linux
sudo apt-get install -y awscli

# 4. openssl (usually pre-installed; only needed if not providing your own cert)
openssl version
```

### B. Azure Login and Subscription

```bash
# Log in to Azure
az login

# Verify your subscription
az account show --query '{subscriptionId:id, name:name}' -o table

# If you have multiple subscriptions, set the correct one:
az account set --subscription "<SUBSCRIPTION_ID>"
```

### C. Verify Subscription Permissions

```bash
# Check your role on the subscription (need Owner or Contributor + User Access Admin)
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) \
    --scope /subscriptions/$(az account show --query id -o tsv) \
    --query '[].roleDefinitionName' -o table
```

### D. Ensure Object REST API Preview is Enabled

The Azure NetApp Files Object REST API is in **Public Preview**. Your subscription must be approved.

1. Go to [Azure NetApp Files Object REST API documentation](https://learn.microsoft.com/en-us/azure/azure-netapp-files/object-rest-api-introduction)
2. Follow the enrollment process
3. Verify enrollment status in the Azure portal under your subscription's "Preview features"

### E. Create a Service Principal

The Service Principal is used for two purposes:
1. **Fabric REST API** authentication (creating workspace, lakehouse, connection, shortcut)
2. **Data Gateway** registration on the VM

```bash
# Create the Service Principal
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "rag-workshop-sp" \
    --role Contributor \
    --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID> \
    --query '{appId: appId, password: password, tenant: tenant}' -o json)

# Extract values
SP_APP_ID=$(echo $SP_OUTPUT | jq -r '.appId')
SP_SECRET=$(echo $SP_OUTPUT | jq -r '.password')
TENANT_ID=$(echo $SP_OUTPUT | jq -r '.tenant')

# Save these securely! The secret is only shown once.
echo "Service Principal App ID: $SP_APP_ID"
echo "Service Principal Secret: $SP_SECRET"
echo "Tenant ID: $TENANT_ID"
```

### F. Grant Fabric Admin Permissions to the Service Principal

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Click the **gear icon** → **Admin portal**
3. Under **Tenant settings**, find and enable:
   - **"Service principals can use Fabric APIs"** → Enable, add your SP to the allowed group (or allow entire organization)
   - **"Service principals can create and use gateways"** → Enable

### G. Get Your Fabric Capacity ID

1. In the Fabric Admin portal → **Capacity settings**
2. Select your capacity (Trial or paid)
3. Copy the **Capacity ID** (a GUID)

If you don't have a capacity, you can start a Fabric Trial:
1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. You'll be prompted to start a free trial

### H. Get Your User Object ID

```bash
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
echo "User Object ID: $USER_OBJECT_ID"
```

### I. Choose a Region

The deployment region must support **GPT-4o**. Recommended regions:

| Region | GPT-4o | Notes |
|--------|--------|-------|
| `eastus2` | Yes | Recommended |
| `swedencentral` | Yes | Good for EU |
| `westus3` | Yes | Alternative US |

### J. Gather All Parameters

Before running the script, have these values ready:

```
Subscription ID:           ________________________________________
Location:                  ________________________________________
Service Principal App ID:  ________________________________________
Service Principal Secret:  ________________________________________
Tenant ID:                 ________________________________________
User Object ID:            ________________________________________
Fabric Capacity ID:        ________________________________________
VM Admin Password:         ________________________________________ (min 12 chars, complexity required)
```

---

## 6. Deployment: Step-by-Step Instructions

### Where to Run

Run the deployment from any machine with the prerequisite tools installed:
- Your local workstation (macOS, Windows, Linux)
- Azure Cloud Shell (PowerShell mode)
- A CI/CD pipeline (Azure DevOps, GitHub Actions)

### Clone the Repository

```bash
git clone https://github.com/DwirefS/ANF-OneLake-AIFoundry.git
cd ANF-OneLake-AIFoundry/automation
```

### Run the Deployment

```powershell
# Switch to PowerShell if not already
pwsh

# Run the deployment
./deploy.ps1 `
    -SubscriptionId       "<YOUR_SUBSCRIPTION_ID>" `
    -Location             "eastus2" `
    -ResourceGroupName    "rg-rag-workshop" `
    -Prefix               "ragworkshop" `
    -VmAdminPassword      (ConvertTo-SecureString "<YOUR_VM_PASSWORD>" -AsPlainText -Force) `
    -VmAdminUsername      "azureuser" `
    -UserObjectId         "<YOUR_USER_OBJECT_ID>" `
    -ServicePrincipalAppId "<YOUR_SP_APP_ID>" `
    -ServicePrincipalSecret "<YOUR_SP_SECRET>" `
    -TenantId             "<YOUR_TENANT_ID>" `
    -FabricCapacityId     "<YOUR_FABRIC_CAPACITY_ID>"
```

### What You'll See

The script outputs progress for each step:

```
  ╔══════════════════════════════════════════════════════════════════╗
  ║   Zero-Copy RAG Workshop — Automated Deployment                ║
  ╚══════════════════════════════════════════════════════════════════╝

=== Validating Prerequisites ===
  Subscription: 00000000-...
  Location: eastus2

=== Step 1: Registering Resource Providers ===
  Microsoft.NetApp already registered.
  Microsoft.Search already registered.
  ...

=== Step 2: Deploying Azure Infrastructure (Bicep) ===
  Creating resource group 'rg-rag-workshop'...
  Deploying Bicep template (this may take 15-20 minutes)...
  Infrastructure deployed successfully.

=== Step 3: Configuring ANF Object REST API Bucket ===
  No certificate provided. Generating self-signed certificate...
  Certificate generated.
  Creating ANF bucket 'finance-data'...
  Bucket created successfully.
  Generating bucket access credentials...
  Credentials generated successfully.

=== Step 4: Uploading Test Data to ANF Bucket ===
  Uploading invoices/...
  Uploading financial_statements/...
  Data upload complete.

=== Step 5: Installing Data Gateway on VM ===
  Running gateway installation on VM...

=== Step 6: Configuring Microsoft Fabric ===
  Creating Fabric workspace 'Financial_RAG_Workshop'...
  Creating Lakehouse 'FinDataLake'...
  Creating S3-compatible connection...
  Creating OneLake shortcut 'anf_shortcut'...

=== Step 7: Configuring Azure AI Search ===
  Creating OneLake data source...
  Creating vectorization skillset...
  Creating search index...
  Creating indexer...
  Running indexer...
  Waiting for indexer to complete...
    Indexer status: inProgress (10s)
    Indexer status: inProgress (20s)
    Indexer status: success (30s)
  Indexer completed. Documents indexed: 12

=== Step 8: Creating AI Foundry Agent ===
  Creating agent 'Financial-Auditor-Agent' with AI Search grounding...
  Agent created.

  Running a test query to verify grounding...
  Agent Response:
  Based on the financial data, OfficeMax had the following charges...

  ╔══════════════════════════════════════════════════════════════════╗
  ║   DEPLOYMENT COMPLETE                                          ║
  ╚══════════════════════════════════════════════════════════════════╝
```

### Expected Duration

| Step | Duration |
|------|----------|
| Resource provider registration | ~1 minute |
| Bicep deployment | ~15 minutes (ANF volume creation is the slowest part) |
| ANF bucket + credential creation | ~2 minutes |
| Data upload | ~1 minute |
| Gateway install + registration | ~5 minutes |
| Fabric configuration | ~2 minutes |
| AI Search indexing | ~3 minutes |
| Agent creation + test | ~1 minute |
| **Total** | **~25-30 minutes** |

---

## 7. Post-Deployment: Verification and First Use

### Step 1: Verify in Azure Portal

1. Go to [portal.azure.com](https://portal.azure.com)
2. Open resource group `rg-rag-workshop`
3. Verify you see: NetApp account, VM, AI Search, AI Services, AI Hub, AI Project, VNet, Storage Account, Key Vault

### Step 2: Verify in Fabric

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Open workspace `Financial_RAG_Workshop`
3. Open lakehouse `FinDataLake`
4. Under **Files**, verify `anf_shortcut` folder is visible
5. Expand it — you should see `invoices/` and `financial_statements/` folders

### Step 3: Verify AI Search Index

1. Go to Azure portal → your AI Search service
2. Click **Indexes** → select `rag-workshop-index`
3. Verify document count is > 0 (should be ~12 documents / chunks)
4. Try a search: click **Search explorer**, type `OfficeMax`, confirm results appear

### Step 4: Chat with the Agent

1. Go to [ai.azure.com](https://ai.azure.com)
2. Select your project (`{prefix}-project`)
3. Go to **Agents** in the left menu
4. Select **Financial-Auditor-Agent**
5. In the chat pane, try these queries:

| Query | Expected Behavior |
|-------|-------------------|
| "What is the total spend for vendor OfficeMax?" | Searches CSV data, sums amounts, cites source file |
| "Show me all transactions from Q1 2025." | Lists transactions from Q1_2025_Expenses.csv |
| "List all invoices and their amounts." | References HTML invoices with vendor names and totals |
| "What categories had the highest spending?" | Aggregates by category across both CSV files |
| "Summarize Q2 expenses by vendor." | Groups Q2 transactions by vendor with totals |

### Step 5: Verify the Zero-Copy Claim

To prove data is NOT copied:
1. Add a new file to the ANF bucket (e.g., upload a new invoice via AWS CLI or Cyberduck)
2. Re-run the AI Search indexer (Azure portal → Indexer → Run)
3. Wait 1-2 minutes
4. Ask the agent about the new file — it should appear in responses
5. The new file was never "migrated" — it was indexed in-place through the virtualization chain

---

## 8. Operational Notes

### Re-Running the Indexer

If you add new data to the ANF volume:

```bash
# Option 1: Via Azure CLI
az search indexer run \
    --resource-group rg-rag-workshop \
    --service-name ragworkshop-search \
    --name rag-workshop-indexer

# Option 2: Via Azure portal
# AI Search → Indexers → rag-workshop-indexer → Run
```

### Updating the Agent System Prompt

Edit `configs/agent-system-prompt.txt`, then re-run the agent creation script:

```powershell
./scripts/06-configure-agent.ps1 `
    -AiServicesName "ragworkshop-ai-services" `
    -ProjectName "ragworkshop-project" `
    -IndexName "rag-workshop-index" `
    -SearchServiceName "ragworkshop-search" `
    -SubscriptionId "<...>" `
    -ResourceGroupName "rg-rag-workshop"
```

### RDP into the Gateway VM

If you need to troubleshoot the gateway:

```bash
# Get the VM public IP
az vm show -g rg-rag-workshop -n ragworkshop-gateway-vm \
    --show-details --query publicIps -o tsv
```

Use an RDP client to connect with the admin credentials you provided.

### Certificate Renewal

The auto-generated TLS certificate expires after 365 days. To renew:

1. Generate a new certificate
2. Update the ANF bucket certificate via Azure portal or REST API
3. Import the new certificate on the gateway VM's trusted root store
4. Verify the OneLake shortcut still works

---

## 9. Troubleshooting Reference

### Bicep Deployment Failures

| Error | Cause | Fix |
|-------|-------|-----|
| `SubnetDelegationNotFound` | ANF subnet delegation missing | Check `networking.bicep` creates the delegation properly |
| `CapacityPoolSizeTooSmall` | Pool size below minimum | Use minimum 2 TiB |
| `QuotaExceeded` | Regional quota for VM size or models | Try a different region or request quota increase |
| `ResourceProviderNotRegistered` | Provider not registered | Run `01-register-providers.ps1` first |
| `InvalidModelVersion` | Model version not available in region | Check available versions in your region |

### ANF Bucket Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `FeatureNotEnabled` | Object REST API not approved | Request preview access for your subscription |
| Certificate errors | Malformed PEM or wrong format | Regenerate with the openssl command shown above |
| `403 Forbidden` on S3 operations | Wrong access key/secret | Regenerate credentials via portal |

### Gateway Issues

| Error | Cause | Fix |
|-------|-------|-----|
| Gateway shows "Offline" | Service not running or auth failed | RDP into VM, check gateway service in Windows Services |
| Registration fails | SP doesn't have Fabric permissions | Check Fabric Admin portal settings |
| PowerShell module not found | PS7 not installed | Install via `https://aka.ms/install-powershell.ps1` |

### Fabric Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `403` on workspace creation | SP not authorized for Fabric APIs | Enable SP access in Fabric Admin portal |
| Shortcut shows empty | Gateway offline or wrong endpoint | Verify gateway status; verify ANF endpoint URL |
| Connection test fails | Network path blocked | Ensure VM can reach ANF IP on port 443 |

### AI Search Issues

| Error | Cause | Fix |
|-------|-------|-----|
| Indexer returns 0 documents | Shortcut empty or wrong path | Verify OneLake shortcut has files; check `container.query` path |
| Indexer `403` error | MI not authorized on Fabric workspace | Add Search MI as Contributor on workspace |
| Embedding skill fails | Wrong AI Services endpoint or key | Verify `ai-services` endpoint and key |

### Agent Issues

| Error | Cause | Fix |
|-------|-------|-----|
| "I don't have access to data" | Search connection not configured | Verify AI Search connection in AI Hub |
| Agent returns hallucinated data | Index is empty or misconfigured | Check index document count; re-run indexer |
| `401 Unauthorized` | Token expired or wrong resource | Re-run `az login`; verify token resource is `https://ai.azure.com` |

---

## 10. Cleanup

### Remove All Azure Resources

```bash
# Delete the resource group (this removes ALL Azure resources)
az group delete --name rg-rag-workshop --yes --no-wait
```

### Remove Fabric Resources

Fabric resources are NOT in the Azure resource group. Remove them separately:

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Navigate to **Workspaces**
3. Find `Financial_RAG_Workshop`
4. Click **...** → **Delete workspace**

### Remove the Service Principal

```bash
az ad sp delete --id "<SP_APP_ID>"
```

### Remove the Gateway Registration

If the gateway VM is deleted but the gateway registration persists in Fabric:

1. Go to Fabric → **Settings** → **Manage connections and gateways**
2. Find the gateway and delete it
