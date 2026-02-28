# Automated Deployment — Zero-Copy RAG Workshop

This folder contains everything needed to deploy the entire Zero-Copy RAG pipeline automatically. After running the deployment script, you can go directly to Azure AI Foundry and start chatting with a grounded AI agent.

## What Gets Deployed

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Azure NetApp   │────▶│  Microsoft       │────▶│  Azure AI        │────▶│  Azure AI        │
│  Files          │     │  Fabric OneLake  │     │  Search          │     │  Foundry Agent   │
│  + Object API   │     │  + Shortcut      │     │  + Vector Index  │     │  + GPT-4o        │
│  + Test Data    │     │  + Lakehouse     │     │  + Skillset      │     │  + Grounding     │
└─────────────────┘     └──────────────────┘     └──────────────────┘     └──────────────────┘
        │                        │
   NFS Volume              Data Gateway VM
   + S3 Bucket            (Windows Server)
```

**Azure resources created:**
- Virtual Network with subnets (default + ANF delegated)
- Azure NetApp Files account, capacity pool, volume, and S3-compatible bucket
- Windows Server VM with On-Premises Data Gateway installed
- Azure AI Search service (Basic tier, with system-managed identity)
- Azure AI Services account with GPT-4o and text-embedding-3-small models
- Azure AI Foundry Hub + Project with AI Search and AI Services connections
- Storage Account and Key Vault (required by AI Foundry Hub)
- All RBAC role assignments

**Fabric resources created:**
- Fabric workspace
- Lakehouse
- S3-compatible connection via Data Gateway
- OneLake shortcut pointing to ANF bucket

**AI Search configuration:**
- OneLake data source
- Vectorization skillset (chunking + embedding)
- Search index with vector and semantic search
- Indexer (runs automatically)

**AI Foundry configuration:**
- Financial Auditor agent grounded on the search index

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

## What Happens During Deployment

| Step | Action | Duration |
|------|--------|----------|
| 1 | Register Azure resource providers | ~1 min |
| 2 | Deploy Bicep template (all Azure infrastructure) | ~15 min |
| 3 | Create ANF bucket + generate credentials | ~2 min |
| 4 | Upload test data to ANF bucket | ~1 min |
| 5 | Install & register Data Gateway on VM | ~5 min |
| 6 | Configure Fabric (workspace, lakehouse, connection, shortcut) | ~2 min |
| 7 | Configure AI Search (data source, index, skillset, indexer) | ~3 min |
| 8 | Create AI Foundry agent | ~1 min |

## After Deployment

1. Open **[Azure AI Foundry](https://ai.azure.com)**
2. Navigate to your project
3. Go to **Agents** and select the **Financial-Auditor-Agent**
4. Start chatting! Try these queries:
   - *"What is the total spend for vendor OfficeMax?"*
   - *"Show me all transactions from Q1 2025."*
   - *"List all invoices over $1000."*
   - *"Summarize Q2 expenses by category."*

## Folder Structure

```
automation/
├── deploy.ps1                 # Main orchestrator (runs everything)
├── main.bicep                 # Main Bicep template (composes modules)
├── main.bicepparam            # Sample parameters file
├── README.md                  # This file
├── modules/
│   ├── networking.bicep       # VNet, subnets, NSG
│   ├── anf.bicep              # NetApp account, pool, volume
│   ├── gateway-vm.bicep       # Windows VM for Data Gateway
│   ├── ai-search.bicep        # Azure AI Search service
│   ├── ai-services.bicep      # AI Services + model deployments
│   └── ai-foundry.bicep       # AI Foundry Hub + Project + connections
├── scripts/
│   ├── 01-register-providers.ps1
│   ├── 02-configure-anf-bucket.ps1
│   ├── 03-upload-data.ps1
│   ├── 04-configure-fabric.ps1
│   ├── 05-configure-ai-search.ps1
│   ├── 06-configure-agent.ps1
│   └── gateway/
│       └── install-gateway.ps1    # Runs ON the VM
└── configs/
    ├── ai-search-index.json       # Search index schema
    └── agent-system-prompt.txt    # Agent system prompt
```

## Advanced Options

### Skip Steps

If you need to re-run only part of the deployment:

```powershell
# Skip infrastructure (already deployed)
./deploy.ps1 ... -SkipInfrastructure

# Skip Fabric configuration (already done)
./deploy.ps1 ... -SkipFabric
```

### Run Individual Scripts

Each step can be run independently:

```powershell
# Register resource providers only
./scripts/01-register-providers.ps1 -SubscriptionId "..."

# Configure ANF bucket only
./scripts/02-configure-anf-bucket.ps1 -SubscriptionId "..." -ResourceGroupName "..." ...
```

## Cleanup

To remove all deployed resources:

```bash
# Delete the Azure resource group (removes all Azure resources)
az group delete --name rg-rag-workshop --yes --no-wait

# Manually delete the Fabric workspace
# Go to app.fabric.microsoft.com → Workspaces → Financial_RAG_Workshop → Delete
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Bicep deployment fails** | Check the Azure portal Activity Log for detailed error messages |
| **ANF bucket creation fails** | Ensure Object REST API preview is enabled on the subscription |
| **Gateway registration fails** | Verify the Service Principal has Fabric admin permissions |
| **Fabric connection fails** | Ensure the gateway VM has network access to the ANF endpoint |
| **Indexer returns 0 documents** | Wait a few minutes and re-run; check that files are visible in the OneLake shortcut |
| **Agent says "I don't know"** | Verify the indexer completed successfully (document count > 0) |
| **Model deployment fails** | Ensure your region supports GPT-4o; check quota availability |

## Differences from the Hands-On Lab

| Aspect | Hands-On Lab | Automation |
|--------|-------------|------------|
| **Approach** | Manual, portal-based | Script-driven, CLI/API-based |
| **Duration** | 2-3 hours | 20-30 minutes |
| **Certificate** | Manual openssl + portal upload | Auto-generated or provided as input |
| **Gateway** | Manual RDP + install + register | VM Custom Script Extension |
| **Fabric** | Portal wizard-based | REST API |
| **AI Search** | Import wizard | REST API with JSON configs |
| **Agent** | Portal-based creation | REST API |
