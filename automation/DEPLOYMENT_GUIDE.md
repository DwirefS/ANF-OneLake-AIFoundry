# Zero-Copy RAG Workshop — Complete Deployment Guide

This document provides **end-to-end instructions** for deploying the automated Zero-Copy RAG pipeline using the fully automated `deploy.ps1` script. It includes architecture details, comprehensive prerequisites, step-by-step deployment instructions, verification procedures, operational notes, and real-world troubleshooting based on enterprise deployment validation.

**Last Updated:** 2026-03-04
**Status:** Production-Ready (Validated for Enterprise Environments)
**Scope:** Fully Automated Deployment via PowerShell

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

**Total Azure resources created:** ~16 resources (VNet, 3 subnets including AzureBastionSubnet, NSG, Bastion Host, Bastion PIP, VM, PIP optional, NIC, NetApp account, pool, volume, AI Search, AI Services, 2 model deployments, Storage Account, Key Vault, AI Hub, AI Project)

**Total Fabric resources created:** 4 (workspace, lakehouse, connection, shortcut)

**Key Enterprise Note:** This deployment includes Azure Bastion for secure access to the gateway VM. The script supports environments with "Do Not Allow Public IPs" Azure Policy by making public IP resources optional.

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

### Known Limitations and Enterprise Considerations

| Concern | Impact | Mitigation |
|---------|--------|------------|
| Object REST API is in **preview** | API surface could change; silent failures if network features not Standard | Pin to API version 2025-03-01-preview; always deploy with `networkFeatures: Standard` |
| Self-signed TLS certificate | Expires after 365 days; must be trusted by all clients | Script auto-generates; set calendar reminder for renewal; import cert on all S3 clients |
| **Fabric capacity is REQUIRED** | Free tier does NOT support On-Premises Data Gateway | Use Trial F SKU or paid capacity; guest users cannot start trials |
| ANF bucket creation silent failures | PUT returns 201 but GET returns NoBucketFound | Always check Activity Log after bucket creation; verify network features are Standard, UID≠0 |
| AI Search document size limits | Very large files (>16MB) may fail to index | Use Document Intelligence skill for complex PDFs; keep files under 16MB |
| OneLake shortcut metadata caching | New files on ANF may not appear immediately | Re-run indexer after adding new files; shortcut may cache for 5+ minutes |
| Fabric Trial capacity limits | Limited compute and storage (shared resources) | Use paid capacity for production; Trial works for workshop (60 days) |
| Agent networking | Foundry agents don't support private AI Search endpoints | Keep AI Search public for workshop; use standard agent setup with VNet for production |
| Model deployment quota | GPT-4o has regional quota limits (250K TPM per region) | Check quota before deployment; try eastus2, swedencentral, or westus3 |
| Guest user limitations | Guest users cannot start Fabric trials; cannot be Fabric capacity admins (Lesson 7, 37) | Use native tenant member account; ask admin to provision capacity |
| Enterprise RBAC policies | Group-inherited roles don't always appear in CLI; may lack UAA role | Use Portal for role verification; pass `deployRbac: false` if lacking UAA |
| "Do Not Allow Public IPs" policy | Blocks all public IP resources (VMs, Bastion PIPs) | Use `deployPublicIp: false`, `deployBastion: true`; access via Bastion |
| App registration restrictions | Enterprise policy may block SP creation | Ask Application Administrator to create SP with Contributor role |
| Managed identity in Fabric UI | Fabric "Add people" panel doesn't support service principals | Use Fabric REST API to assign roles: `POST /v1/workspaces/{id}/roleAssignments` |

---

## 4. File-by-File Reference

### Infrastructure as Code (Bicep)

#### `main.bicep` — Main Orchestrator Template
**What it does:** Composes all Bicep modules into a single deployment. Defines top-level parameters and wires module outputs as inputs to dependent modules.

**Key design decisions:**
- Uses module composition (not monolithic template) for readability and reusability
- AI Services deploys before AI Foundry (Foundry needs resource IDs)
- ANF module depends on networking module (needs delegated subnet ID)
- All outputs are surfaced for PowerShell scripts
- Includes enterprise-friendly conditionals for RBAC and public IP restrictions

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | — | Azure region (must support GPT-4o: eastus2, swedencentral, westus3) |
| `prefix` | string | `ragworkshop` | Name prefix for all resources (3-15 chars, lowercase, max 15 for Windows computer name) |
| `vmAdminUsername` | string | `azureuser` | Gateway VM admin username |
| `vmAdminPassword` | securestring | — | Gateway VM admin password (min 12 chars, complexity required) |
| `userObjectId` | string | — | Your Azure AD object ID (use `az ad signed-in-user show --query id -o tsv`) |
| `anfPoolSizeTiB` | int | `2` | ANF capacity pool size (minimum 2 TiB for Standard tier; 1 TiB for Flexible) |
| `anfVolumeQuotaGiB` | int | `100` | ANF volume quota in GiB |
| `deployRbac` | bool | `true` | Set to `false` if you lack User Access Administrator role (Code Change 1) |
| `deployPublicIp` | bool | `true` | Set to `false` if subscription has "Do Not Allow Public IPs" policy (Code Change 2) |
| `deployBastion` | bool | `true` | Set to `true` to deploy Azure Bastion for RDP access when public IP is blocked (Code Change 6) |

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
- **Capacity Pool** (`{prefix}-pool`): Standard or Flexible service level
- **Volume** (`anf-finance-vol`): 100 GiB NFS volume with **Standard network features** (Code Change 3)

**Critical: Network Features**
- Volume MUST be created with `networkFeatures: 'Standard'` for Object REST API (S3-compatible bucket access) to work
- Default is Basic, which causes silent bucket creation failures (Lesson 11)
- If already deployed with Basic, upgrade via: `az netappfiles volume update ... --network-features Standard` (takes 15-30 minutes)

**Why NFSv3:** Simpler protocol, widely compatible. NFSv4.1 adds Kerberos authentication which is unnecessary for this workshop.

**Note:** The S3-compatible bucket is NOT created by Bicep — it's created by PowerShell script `02-configure-anf-bucket.ps1` because bucket creation requires preview REST API and TLS certificate upload, which Bicep doesn't support cleanly.

---

#### `modules/gateway-vm.bicep` — Data Gateway VM
**What it does:** Creates a Windows Server VM that will host the On-Premises Data Gateway (OPDG).

**Resources created:**
- **Public IP** (`{prefix}-gateway-pip`): Optional, Static, Standard SKU — skipped if `deployPublicIp: false` (Code Change 2)
- **NIC** (`{prefix}-gateway-nic`): Connected to the default subnet
- **VM** (`{prefix}-gateway-vm`): Windows Server 2022+ Datacenter, Standard_D2s_v3

**Why this VM exists:** Microsoft Fabric requires a Data Gateway to access private VNet-isolated S3 endpoints. The gateway bridges connectivity between OneLake and the ANF Object REST API. ANF itself does not require a gateway.

**Enterprise Considerations:**
- If subscription has "Do Not Allow Public IPs" policy, set `deployPublicIp: false` — use Azure Bastion for RDP instead (Code Change 6)
- Windows computer name is auto-derived from prefix, guaranteed ≤15 chars to comply with Windows NETBIOS limits (Code Change 5, Lesson 18)
- If prefix + "gw" exceeds 15 chars, computer name is automatically truncated

**Gateway software installation:** NOT done by Bicep. Happens later via `install-gateway.ps1` using `az vm run-command invoke` (Code Change 7, Lesson 19).

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
**What it does:** Creates the AI Foundry (now called Microsoft Foundry) workspace hierarchy and connects it to AI Search and AI Services (Lesson 52).

**Resources created:**
- **Storage Account** (`{prefix}hubstore`): Required dependency (stores experiment data, logs)
- **Key Vault** (`{prefix}-hub-kv`): Required dependency (stores secrets, connection strings)
- **AI Hub** (`{prefix}-hub`): Top-level workspace (kind: `Hub`) with system-assigned managed identity
- **AI Services Connection**: Links Hub to AI Services account (AAD auth)
- **AI Search Connection**: Links Hub to AI Search service (AAD auth)
- **AI Project** (`{prefix}-project`): Working project (kind: `Project`) under the Hub

**Important Notes:**
- Portal branding shows "Microsoft Foundry" but URL remains ai.azure.com (Lesson 52)
- Hub-level connections are inherited by all projects (shared connections at Hub layer)
- Managed identities for AI Search must be added via Fabric REST API, NOT the Fabric UI (Lesson 44)
- Two-level hierarchy: Hub owns shared resources; Project is where agents/evaluations/experiments live

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
1. Generates a self-signed X.509 certificate using `openssl` (if not provided)
2. Base64-encodes the certificate (Code Change 4: Lesson 13)
3. Creates the bucket via ARM REST API (`PUT .../volumes/{vol}/buckets/{bucket}`)
4. Generates access credentials via REST API (Code Change 4: Lesson 16)
5. Returns endpoint URL, access key, secret key, certificate path

**Critical Fixes (Code Change 4):**
- **UID/GID must be 1000, NOT 0** (Lesson 15): Root (UID 0) is a system user in ONTAP, rejected silently. Bucket creation returns 201 "Accepted" but GET returns `NoBucketFound`
- **generateCredentials requires `keyPairExpiryDays` parameter** (Lesson 16): Pass `{"keyPairExpiryDays": 365}`, not empty body
- **Certificate must be base64-encoded combined PEM** (Lesson 13): Concatenate cert + key, then base64 encode

**Debugging bucket creation failures:**
- Bucket PUT returns 201 "Accepted" even if it will fail asynchronously
- Check Azure Activity Log (Lesson 17): `az monitor activity-log list --resource-group <rg> --offset 1h --query "[?contains(operationName.value,'bucket')]" -o table`
- Look for `Started → Accepted → Failed` sequence; actual error is in `statusMessage`

**Why REST API instead of Bicep:** Bucket resource is preview-only. Bicep doesn't cleanly support inline certificate content and requires base64 encoding, which is easier in PowerShell.

---

#### `scripts/03-upload-data.ps1` — Upload Test Data
**What it does:** Uploads the `test_data/invoices/` and `test_data/financial_statements/` directories to the ANF S3 bucket using the AWS CLI's `s3 sync` command.

**Uses `--no-verify-ssl`** because the ANF endpoint uses a self-signed certificate. In production, you'd import the certificate to the system trust store instead.

**The test data includes:**
- 10 HTML invoices from vendors (OfficeMax, Azure Cloud Services, WeWork, Dell, Staffing Agency)
- 2 CSV financial statements (Q1 and Q2 2025 expenses, ~50 transactions each)

---

#### `scripts/gateway/install-gateway.ps1` — Gateway Installation
**What it does:** Runs ON the gateway VM (not on your local machine). Installs the On-Premises Data Gateway and imports the ANF TLS certificate.

**Code Change 7 (Major Rewrite):**
- Original script relied on Service Principal registration (blocked in enterprise tenants — Lesson 4)
- New script uses `az vm run-command invoke` for reliable remote execution (Lesson 19)
- Registration is now **interactive** — requires RDP into VM and manual gateway sign-in via OPDG UI

**Steps (New Approach):**
1. **InstallOPDG action:**
   - Downloads gateway installer from Microsoft
   - Runs silent installation (`/quiet ACCEPTEULA=yes`)
   - Verifies `PBIEgwService` Windows service is running
   - Cleans up installer file
2. **ImportCert action:**
   - Uses TcpClient/SslStream to retrieve self-signed cert from ANF endpoint IP
   - Imports cert to LocalMachine\Root (Trusted Root Certification Authorities)
   - Verifies import via certificate thumbprint
3. **All action:** Runs both InstallOPDG and ImportCert sequentially

**After Installation (Manual Steps — RDP Required):**
1. RDP into gateway VM via Azure Bastion (if public IP blocked — Lesson 26-29)
2. Open **On-Premises Data Gateway Configurator** (should auto-launch post-install)
3. Click **Sign in** and authenticate with your Azure work account
4. Select the **correct tenant** if you belong to multiple tenants (Lesson 38)
5. Enter gateway name (e.g., `ANF-Gateway`)
6. Verify status shows **"Online"** and **"Microsoft Fabric: Default environment - Ready"** (Lesson 38)

**How it's invoked:** The main `deploy.ps1` script runs this on the VM using `az vm run-command invoke` (no RDP needed for install itself; RDP only needed for the registration UI step).

---

#### `scripts/04-configure-fabric.ps1` — Configure Microsoft Fabric
**What it does:** Creates all Fabric resources using the Fabric REST API.

**Steps:**
1. Authenticates to Fabric using the Service Principal (OAuth2 client_credentials flow)
2. Creates workspace `Financial_RAG_Workshop` (or finds existing) with capacity assignment
3. Creates lakehouse `FinDataLake` (or finds existing)
4. Discovers the registered Data Gateway (must be online and Fabric-ready)
5. Creates an S3-compatible connection using the gateway + ANF credentials
6. Creates a OneLake shortcut `anf_shortcut` pointing to the ANF bucket

**⚠️ CRITICAL ENTERPRISE BLOCKERS (Lessons 35-36):**
- **Fabric capacity is REQUIRED** (F SKU trial or paid) — free tier does NOT support gateways
- **Guest users cannot start trials** (Lesson 37) — ask tenant admin to provision capacity
- **Gateway must be Online and Fabric-Ready** — if offline, shortcut creation fails silently

**Why Fabric REST API:** Fabric is SaaS, not deployable via ARM/Bicep. The only automation path is Fabric REST API (`api.fabric.microsoft.com/v1/...`).

**Authentication:** Uses OAuth2 client credentials with Service Principal. SP must have Fabric API permissions (enabled in tenant settings by Fabric admin).

---

#### `scripts/05-configure-ai-search.ps1` — Configure AI Search
**What it does:** Creates the search data source, skillset (with Document Intelligence), index, and indexer — then runs the indexer and waits for completion.

**Resources created via REST API:**
1. **Data Source** (`onelake-datasource`): Type `onelake`, pointing to Fabric workspace/lakehouse/shortcut, with managed identity authentication

2. **Skillset** (`rag-workshop-skillset`): A 3-skill pipeline using native Azure AI Search built-in skills:

   ```
   Document → Document Intelligence Layout → Split → Embedding → Index
   ```

   | Skill | OData Type | Purpose |
   |-------|------------|---------|
   | **Document Intelligence Layout** | `Microsoft.Skills.Util.DocumentIntelligenceLayoutSkill` | Built-in AI Search skill. Extracts structured content (tables, key-value pairs, headings) as Markdown from PDFs, Office docs, images, and HTML. OCR is internal. Uses AI Services account. |
   | **Text Splitter** | `Microsoft.Skills.Text.SplitSkill` | Chunks extracted Markdown into ~2000 character pages with 500 char overlap |
   | **Embedding** | `Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill` | Generates 1536-dim vectors using `text-embedding-3-small`. **IMPORTANT (Lesson 49):** Use "Microsoft Foundry" Kind, NOT "Azure OpenAI". |

   **All three skills are native Azure AI Search built-in skills** — no external microservices or custom code needed. Document Intelligence Layout runs through the AI Services multi-service account.

3. **Index** (`rag-workshop-index`): Fields include `chunk` (searchable text), `vector` (1536-dim HNSW), `title`, `source_url`, `parent_id`. Semantic search enabled.

4. **Indexer** (`rag-workshop-indexer`): Runs once, extracts content/metadata, provides raw file bytes to skillset (`allowSkillsetToReadFileData: true`), passes content through 3-skill pipeline. Uses managed identity for OneLake auth.

**After creation:** The script runs the indexer and polls for completion (up to 5 minutes). It reports document count. Check Activity Log if indexer fails (Lesson 17, 44).

**Enterprise RBAC Note (Lesson 44):** The AI Search managed identity must be added to the Fabric workspace as Contributor. The Fabric UI "Add people" panel does NOT support managed identities — use the Fabric REST API:
```
POST https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/roleAssignments
Body: { "principal": { "id": "<MI-ObjectID>", "type": "ServicePrincipal" }, "role": "Contributor" }
```

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

Run these on the machine where you will execute the deployment (your local workstation, Azure Cloud Shell, or CI/CD pipeline):

```bash
# 1. Azure CLI
# macOS
brew install azure-cli
# Windows
winget install Microsoft.AzureCLI
# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 2. PowerShell 7+ (REQUIRED for the deploy.ps1 script)
# macOS
brew install powershell/tap/powershell
# Windows — already included or install from:
# https://aka.ms/install-powershell
# Linux
sudo apt-get install -y powershell

# 3. AWS CLI (for S3 data upload)
# Azure Cloud Shell NOTE: AWS CLI is NOT pre-installed. Install via:
pip install awscli --user --quiet
# Then add to PATH: $env:PATH = "$HOME/.local/bin:$env:PATH"
# Or on local machine:
# macOS: brew install awscli
# Windows: winget install Amazon.AWSCLI
# Linux: sudo apt-get install -y awscli

# 4. openssl (usually pre-installed; only needed if not providing your own cert)
openssl version
```

**⚠️ Cloud Shell Note:** Azure Cloud Shell ships with Azure CLI and PowerShell but does **NOT** include AWS CLI by default. Install it via `pip` as shown above, or skip data upload and upload test data manually to the ANF bucket from the gateway VM.

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

**IMPORTANT ENTERPRISE NOTE:** Your user may lack sufficient RBAC role assignment permissions, which is common in enterprise environments where roles are group-inherited.

```bash
# Check your role on the subscription (need Contributor minimum)
# NOTE: If this returns empty, use the Azure Portal instead
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) \
    --scope /subscriptions/$(az account show --query id -o tsv) \
    --query '[].roleDefinitionName' -o table
```

**Alternative (Recommended for Enterprise):** Open the Azure Portal → **Subscriptions** → **Access control (IAM)** → **View my access**. This shows all roles including those inherited through groups.

**Required minimum:** Contributor role on the subscription. If you lack **User Access Administrator** role:
- The Bicep deployment will skip the `Cognitive Services OpenAI User` RBAC assignment (pass `-DeployRbac $false`)
- Manually assign the role after deployment via the portal, or ask your admin to pre-assign it

### D. Ensure Object REST API Preview is Enabled

The Azure NetApp Files Object REST API is in **Public Preview**. Two preview features must be registered on your subscription:

1. **`ANFEnableObjectRESTAPI`** — Enables Object REST API on NetApp accounts
2. **`ANFEnableS3ReadOnly`** — Enables read-only S3 access (pending in most subscriptions)

**To verify/enable:**
1. Go to [Azure Portal → Subscriptions → Preview features](https://portal.azure.com/#view/Microsoft_Azure_Resources/PreviewFeaturesBladeV2/~/listPreviewFeatures)
2. Search for "ANFEnableObjectRESTAPI" — should show "Registered"
3. Search for "ANFEnableS3ReadOnly" — may show "Pending" (this is OK)
4. If either is missing, request access through the Azure Portal or contact Azure Support

**If not already registered:** The deployment will still create the volume (Lesson 11: silent failure), but bucket creation will fail silently (GET returns `NoBucketFound` even though bucket creation returned "Accepted"). To fix, update the volume after deployment: `az netappfiles volume update --resource-group <rg> --account-name <account> --pool-name <pool> --volume-name <volume> --network-features Standard`

### E. Create a Service Principal

The Service Principal is used for two purposes:
1. **Fabric REST API** authentication (creating workspace, lakehouse, connection, shortcut)
2. **Data Gateway** registration on the VM

**⚠️ ENTERPRISE BLOCKER (Lesson 4):** Many enterprise tenants have the Azure AD policy **"Users can register applications"** set to **No**. If you cannot create an app registration in the portal or via CLI, ask your tenant admin to create the Service Principal for you.

```bash
# Create the Service Principal (requires Application Administrator or Global Administrator role)
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

**If app registration fails:** Contact your Azure AD admin and provide them with the Service Principal name (`rag-workshop-sp`). Ask them to create it with **Contributor** role on your subscription.

### F. Grant Fabric Admin Permissions to the Service Principal

**⚠️ ENTERPRISE BLOCKER (Lesson 4, 7):** Guest users cannot create Fabric capacity trials. If you're a guest in your organization's Azure AD tenant, ask your tenant admin to pre-provision Fabric capacity and assign your account as a capacity admin.

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Click the **gear icon** (top right) → **Admin portal** (requires Fabric admin role)
3. Under **Tenant settings**, find and enable:
   - **"Service principals can use Fabric APIs"** → Enable, add your SP to the allowed group (or allow entire organization)
   - **"Service principals can create and use gateways"** → Enable

**If you cannot access Admin portal:** Ask your Fabric admin to enable these settings for you.

### G. Get Your Fabric Capacity ID

**⚠️ ENTERPRISE REQUIREMENT (Lesson 35-37):** Fabric capacity (Trial F SKU or paid) is **REQUIRED** for this lab. The free Fabric tier does NOT support the On-Premises Data Gateway, which is essential for the OneLake shortcut to ANF.

1. Start a Fabric Trial (if available):
   - Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
   - Profile icon (top right) → **Start trial** (if available)
   - Accept the Fabric capacity trial
   - Wait 5-10 minutes for capacity to activate

2. Get your Capacity ID:
   - Gear icon → **Admin portal** → **Capacity settings** → Select your capacity
   - Copy the **Capacity ID** (a GUID, e.g., `10858519-429f-40e3-8d49-ffb8c3820ca8`)

**If "Start trial" is unavailable:**
- You are a guest user in this tenant (cannot start trials — see Lesson 37)
- Ask your tenant admin to create Fabric capacity (F2 or higher SKU) and assign it to your account
- Or use the ARM API to get the capacity ID from an existing capacity: `az rest --method get --url "https://api.fabric.microsoft.com/v1/capacities" --resource "https://api.fabric.microsoft.com"`

**If you only have access to Free tier:** You cannot complete this lab without capacity. The gateway dropdown will be empty and shortcuts cannot be created.

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

# Standard deployment (most cases)
./deploy.ps1 `
    -SubscriptionId                "<YOUR_SUBSCRIPTION_ID>" `
    -Location                      "eastus2" `
    -ResourceGroupName             "rg-rag-workshop" `
    -Prefix                        "ragworkshop" `
    -VmAdminPassword               (ConvertTo-SecureString "<YOUR_VM_PASSWORD>" -AsPlainText -Force) `
    -VmAdminUsername               "azureuser" `
    -UserObjectId                  "<YOUR_USER_OBJECT_ID>" `
    -ServicePrincipalAppId         "<YOUR_SP_APP_ID>" `
    -ServicePrincipalSecret        "<YOUR_SP_SECRET>" `
    -TenantId                      "<YOUR_TENANT_ID>" `
    -FabricCapacityId              "<YOUR_FABRIC_CAPACITY_ID>"

# Enterprise deployment (with policy restrictions)
./deploy.ps1 `
    -SubscriptionId                "<YOUR_SUBSCRIPTION_ID>" `
    -Location                      "eastus2" `
    -ResourceGroupName             "rg-rag-workshop" `
    -Prefix                        "ragworkshop" `
    -VmAdminPassword               (ConvertTo-SecureString "<YOUR_VM_PASSWORD>" -AsPlainText -Force) `
    -VmAdminUsername               "azureuser" `
    -UserObjectId                  "<YOUR_USER_OBJECT_ID>" `
    -ServicePrincipalAppId         "<YOUR_SP_APP_ID>" `
    -ServicePrincipalSecret        "<YOUR_SP_SECRET>" `
    -TenantId                      "<YOUR_TENANT_ID>" `
    -FabricCapacityId              "<YOUR_FABRIC_CAPACITY_ID>" `
    -DeployRbac                    $false `
    -DeployPublicIp                $false

# Parameters explained:
# -DeployRbac false                  Use if you lack User Access Administrator role (assign role manually after)
# -DeployPublicIp false              Use if subscription has "Do Not Allow Public IPs" policy (requires Bastion)
# -SkipInfrastructure                Skip Bicep deployment if already deployed
# -SkipFabric                        Skip Fabric configuration if already configured
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

| Step | Duration | Enterprise Notes |
|------|----------|------------------|
| Resource provider registration | ~1 minute | If not already registered |
| Bicep deployment | ~15-20 minutes | ANF volume creation is slowest part; network features upgrade takes 15-30 min if needed |
| ANF bucket + credential creation | ~2-3 minutes | If network features need upgrade, add 15+ min; check Activity Log for silent failures |
| Data upload | ~1 minute | Cloud Shell: install AWS CLI first (`pip install awscli --user --quiet`) |
| Gateway install | ~5 minutes | Runs via `az vm run-command invoke` (no RDP needed for install) |
| Gateway registration | ~5 minutes (manual) | Requires RDP via Bastion; interactive OPDG Configurator sign-in |
| Fabric configuration | ~3-5 minutes | Depends on Fabric capacity activation; guest user trials may be blocked |
| AI Search indexing | ~3-5 minutes | Check Activity Log if indexer fails; AI Search MI must be added to Fabric workspace |
| Agent creation + test | ~2 minutes | First query may not trigger knowledge tool; try broader query first |
| **Total (automated)** | **~30-45 minutes** | Plus manual gateway registration (5 min) if using interactive sign-in |

### Important Notes for Enterprise Deployments

1. **Bicep Redeployment:** If full deployment fails partway, do NOT re-run the full `main.bicep`. Instead, deploy only the failed module independently to avoid cascading validation errors on already-deployed resources (Lesson 10).

2. **ANF Network Features Upgrade:** If volume deployed with Basic networking features, upgrade to Standard takes 15-30+ minutes as a background operation. Check `provisioningState` repeatedly. Bucket creation will silently fail until upgrade completes.

3. **Bucket Creation Silent Failure Pattern:** PUT returns 201 "Accepted" even when bucket creation will fail. Always check Activity Log immediately after bucket creation:
   ```
   az monitor activity-log list --resource-group <rg> --offset 1h \
     --query "[?contains(operationName.value,'bucket')].{op:operationName.value,status:status.value,msg:properties.statusMessage}" -o table
   ```

4. **Gateway Registration Requirements:** Interactive registration via RDP is required. The script installs OPDG via remote execution, but:
   - You MUST RDP into the VM via Azure Bastion (if no public IP)
   - Open OPDG Configurator and click **Sign in**
   - Authenticate with your Azure account (select correct tenant if multi-tenant)
   - Enter gateway name and verify status shows **"Online"** and **"Microsoft Fabric: Ready"**
   - Without proper registration, the gateway will be invisible to Fabric even if online

5. **Fabric Capacity Requirement:** The entire OneLake → AI Search → Agent flow requires Fabric capacity (F SKU trial or paid). Free tier does NOT support On-Premises Data Gateway. If you only have free tier, the gateway dropdown will remain empty and shortcuts cannot be created.

6. **AI Search Managed Identity Assignment:** The AI Search managed identity must be added to the Fabric workspace as Contributor. The Fabric UI "Add people" panel does NOT support service principals — use the REST API:
   ```
   az rest --method post --url "https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/roleAssignments" \
     --body '{"principal":{"id":"<MI-ObjectID>","type":"ServicePrincipal"},"role":"Contributor"}'
   ```

7. **Azure Bastion Single-Session Limit:** If using Azure Bastion Developer tier (deployed with this script), only one RDP session is allowed at a time. Complete all VM tasks in one session before disconnecting.

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

### Pre-Deployment Blockers (Fix These First)

| Issue | Impact | Solution |
|-------|--------|----------|
| Cannot create app registration | Service Principal cannot be created | Enterprise policy blocks app registration. Ask tenant admin to create SP (`rag-workshop-sp` with Contributor role) |
| Lack User Access Administrator role | RBAC assignment will fail | Pass `-DeployRbac $false` to Bicep. Manually assign `Cognitive Services OpenAI User` role after deployment via portal |
| "Do Not Allow Public IPs" policy | VM creation fails with RequestDisallowedByPolicy | Pass `-DeployPublicIp $false` and `-DeployBastion $true`. Use Azure Bastion for RDP access |
| No Fabric capacity trial option | Cannot complete lab without Fabric F SKU | You are a guest user. Ask tenant admin to create Fabric capacity (F2+ SKU) and assign to your account |
| Object REST API preview not enabled | Bucket creation fails silently (GET returns NoBucketFound) | Request `ANFEnableObjectRESTAPI` feature flag enrollment via Azure Preview Features blade |
| AWS CLI not installed (Cloud Shell) | Data upload fails with "aws: command not found" | Install in Cloud Shell: `pip install awscli --user --quiet && $env:PATH = "$HOME/.local/bin:$env:PATH"` |

### Bicep Deployment Failures

| Error | Cause | Fix |
|-------|-------|-----|
| `RequestDisallowedByPolicy` on PublicIP resource | "Do Not Allow Public IPs" Azure Policy | Pass `deployPublicIp: false` to deploy.ps1 |
| `AuthorizationFailed` on RBAC role assignment | User lacks User Access Administrator role | Pass `deployRbac: false`; assign role manually after deployment |
| `SubnetDelegationNotFound` | ANF subnet delegation missing | Verify subnet has delegation to `Microsoft.NetApp/volumes` |
| `CapacityPoolSizeTooSmall` | Minimum 2 TiB for Standard tier | Use Standard (2 TiB min) or Flexible (1 TiB min) |
| `QuotaExceeded` | Regional quota for VM or models (GPT-4o) | Try different region or request quota increase. GPT-4o available in: eastus2, swedencentral, westus3 |
| `InvalidModelVersion` | Model version unavailable in region | Check Azure OpenAI model availability for your region |

### ANF Bucket Issues (Silent Failures!)

| Error | Cause | Fix |
|-------|-------|-----|
| **Bucket PUT returns 201 but GET returns NoBucketFound** | Network features not Standard (Lesson 11) | Patch volume: `az netappfiles volume update ... --network-features Standard` (takes 15-30 min) |
| **Bucket PUT returns 201 but Activity Log shows Failed** | UID/GID 0 (root) rejected (Lesson 15) | Check Activity Log: `az monitor activity-log list --resource-group <rg> --offset 1h --query "[?contains(operationName.value,'bucket')]"` |
| **Bucket creation: "Could not extract Private Key from PEM"** | Certificate is cert-only, missing private key (Lesson 12) | Combine cert + key: `cat cert.pem private.key > combined.pem`. Base64 encode before REST API call. |
| **Bucket creation: certificate FQDN mismatch** | FQDN doesn't match cert CN (Lesson 21) | Regenerate cert with correct CN: `openssl req -x509 ... -subj "/CN=anf-workshop"` |
| `403 Forbidden` on S3 operations | Wrong access key/secret | Regenerate credentials via portal or script; verify User ID is 1000 not 0 |
| `FeatureNotEnabled` | Object REST API preview not enrolled | Request enrollment via Azure Preview Features blade |

### Gateway Issues

| Error | Cause | Fix |
|-------|-------|-----|
| **Gateway dropdown empty in Fabric connection dialog** | Fabric free tier (no capacity) — gateway requires F SKU (Lessons 35-36) | Create/use Fabric Trial or paid capacity (F2+). Gateways do NOT work on free tier. |
| Gateway shows "Offline" in Fabric | Service crashed or auth failed | RDP via Bastion; check Windows Services for `PBIEgwService` (running?); restart service |
| OPDG registration fails | SP permissions missing or wrong tenant | Sign in with correct account; verify tenant; check Fabric admin settings for "Service principals can create/use gateways" |
| **Computer name exceeds 15 chars** | Windows NETBIOS limit (Lesson 18) | Prefix+13 chars max. Script auto-truncates via `take('${prefix}gw', 15)` |
| `--no-wait` deployment silently fails | Error hidden; only visible in deployment group list (Lesson 19) | Re-run without `--no-wait` to see actual error. Check `az deployment group list` for status. |
| RDP access denied (no public IP) | "Do Not Allow Public IPs" policy (Lesson 26) | Use Azure Bastion (Developer tier, single-session — see Lesson 29) |

### Fabric Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `403` on workspace creation | SP not authorized for Fabric APIs | Fabric admin must enable "Service principals can use Fabric APIs" in tenant settings |
| Shortcut shows empty | Gateway offline or S3 endpoint unreachable | Verify gateway is **Online** and **Fabric-Ready** in OPDG Configurator. Verify ANF endpoint URL matches bucket FQDN. |
| S3 connection fails with DNS error | FQDN not resolvable (private endpoint) | Add hosts file entry on gateway VM: `echo "10.0.2.4 anf-workshop" >> C:\Windows\System32\drivers\etc\hosts` (Lesson 24) |
| "Cannot add managed identity via Add people" | Fabric UI doesn't support service principals (Lesson 44) | Use Fabric REST API: `POST /v1/workspaces/{id}/roleAssignments` with `"type": "ServicePrincipal"` |

### AI Search Issues

| Error | Cause | Fix |
|-------|-------|-----|
| Indexer returns 0 documents | OneLake shortcut is empty or MI not authorized (Lesson 44) | Verify shortcut has files; add Search MI as Contributor to Fabric workspace via REST API |
| Indexer `403 Unauthorized` | Managed identity not granted access to Fabric workspace | Add AI Search MI to workspace: `az rest --method post --url "https://api.fabric.microsoft.com/v1/workspaces/{id}/roleAssignments" ...` |
| Embedding skill fails with "No access to subscription" | "Azure OpenAI" Kind selected (Lesson 49) | **Change Kind from "Azure OpenAI" to "Microsoft Foundry"**. Select your Foundry project and `text-embedding-3-small` deployment. |
| **Vectorization wizard: scenario selection missing** | New UI step not documented (Lesson 46) | Select **"RAG"** as target scenario in the first wizard step |
| **Vectorization: "Lakehouse URL" field invalid format** | Lakehouse URL not in correct format (Lesson 47) | Use full format: `https://msit.powerbi.fabric.microsoft.com/groups/{workspaceGuid}/lakehouses/{lakehouseGuid}` (copy from Fabric UI address bar) |

### Agent Issues

| Error | Cause | Fix |
|-------|-------|-----|
| Agent: "I don't have access to data" | AI Search connection not configured | Verify AI Search connection exists in AI Hub; ensure connection is added to project |
| Agent: "Please provide the financial data" on first query | Knowledge tool not triggered for very specific queries (Lesson 64) | Try a broader query first ("What financial documents are available?") to establish context, then ask specific questions |
| Agent: Returns generic response without citations | Index is empty or AI Search not connected | Check index document count (should be > 0); verify indexer completed successfully |
| **"Azure OpenAI" Kind doesn't find deployments** | Kind should be "Microsoft Foundry" (Lesson 49) | Change to "Microsoft Foundry"; select your Foundry project |
| `401 Unauthorized` on agent requests | Token expired or wrong resource scope | Run `az login` again; verify token resource is `https://ai.azure.com` not `https://management.azure.com` |
| Portal branding shows "Microsoft Foundry" but guide says "Azure AI Foundry" | Rebranding occurred (Lesson 52) | Both names are correct; URL remains ai.azure.com |

---

## 9a. Code Changes Applied (Enterprise Validation)

This deployment includes 7 code changes based on real-world deployment validation in enterprise environments:

### Code Change 1: Made RBAC Assignment Conditional
**Files:** `modules/ai-services.bicep`, `main.bicep`
**Issue:** Deployer may lack User Access Administrator role (common in enterprises where roles are group-inherited — Lesson 4)
**Fix:** Added `deployRbac` parameter (default `true`). When `false`, skips the `Cognitive Services OpenAI User` role assignment. Assign manually via portal after deployment.
**Use:** Pass `-DeployRbac $false` when you lack UAA role

### Code Change 2: Made Public IP Optional
**Files:** `modules/gateway-vm.bicep`, `main.bicep`
**Issue:** Enterprise subscriptions often have "Do Not Allow Public IPs" Azure Policy (Lesson 9)
**Fix:** Added `deployPublicIp` parameter (default `true`). When `false`, skips Public IP and NIC public IP association. VM is still deployable but requires Bastion or VPN for RDP.
**Use:** Pass `-DeployPublicIp $false` when policy blocks public IPs

### Code Change 3: Added Standard Network Features to ANF Volume
**File:** `modules/anf.bicep`
**Issue:** ANF Object REST API requires Standard network features; default is Basic, causing silent bucket creation failures (Lesson 11)
**Fix:** Added `networkFeatures: 'Standard'` to volume properties. Silent failure: bucket PUT returns 201 "Accepted" but GET returns `NoBucketFound`. Always check Activity Log after bucket creation.
**Impact:** Essential for S3-compatible bucket access

### Code Change 4: Fixed ANF Bucket Creation and Credential Generation
**File:** `scripts/02-configure-anf-bucket.ps1`
**Issues Fixed:**
- **Lesson 15:** UID 0 (root) rejected by ONTAP — changed to configurable parameter (default 1000)
- **Lesson 16:** `generateCredentials` requires `keyPairExpiryDays` parameter — fixed empty body to `{"keyPairExpiryDays": 365}`
- **Lesson 13:** Certificate must be base64-encoded combined PEM — added encoding step
- **Lesson 17:** Added Activity Log checking for debugging async bucket failures

### Code Change 5: Made Computer Name Prefix-Aware
**File:** `modules/gateway-vm.bicep`
**Issue:** Windows computer name has 15-char NETBIOS limit; `az vm create` defaults to resource name (Lesson 18)
**Fix:** Added `var computerName = take('${prefix}gw', 15)` — guarantees ≤15 chars
**Impact:** Prevents `InvalidParameter` errors on VM creation

### Code Change 6: Added Azure Bastion Deployment
**Files:** `modules/networking.bicep`, `main.bicep`
**Issue:** Without public IPs (due to policy), need alternative RDP access for gateway VM
**Fix:** Added conditional Bastion Host deployment with `deployBastion` parameter (default `true`). Creates AzureBastionSubnet, PIP, and Bastion Basic SKU.
**Note:** Bastion Developer tier supports only 1 session at a time (Lesson 29)

### Code Change 7: Rewrote Gateway Installation Script
**File:** `scripts/gateway/install-gateway.ps1`
**Major Changes:**
- Removed Service Principal-based registration (blocked in enterprise tenants — Lesson 4)
- Uses `az vm run-command invoke` for reliable remote execution (Lesson 19)
- Registration now interactive — requires RDP via Bastion and manual OPDG Configurator sign-in
- Added certificate import via TcpClient/SslStream (Lesson 39) — imports self-signed cert from ANF endpoint
- Added action parameters: `InstallOPDG`, `ImportCert`, or `All`

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
