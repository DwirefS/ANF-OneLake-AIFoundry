# Azure NetApp Files to Azure AI Foundry: Zero-Copy RAG Workshop

## Overview & Architecture
This lab demonstrates how **Azure AI Foundry** can ground AI agents on **enterprise file data stored in Azure NetApp Files** using **Microsoft Fabric OneLake shortcuts**, enabling a zero‑copy AI data path without ETL, data duplication, or re‑platforming.
The solution architecture uses:

*   **Azure NetApp Files** as the authoritative system of record for unstructured file data
*   **Object REST API** (S3‑compatible access) to expose file data for analytics and AI consumption
*   **Microsoft Fabric OneLake shortcuts** to virtualize Azure NetApp Files data
*   **Azure AI Search** to index virtualized data
*   **Azure AI Foundry** to build and run agents grounded on that data

This lab is intended for education, enablement, and design validation. It illustrates a supported architectural pattern, but it is not a production‑hardened reference architecture.

### What this lab demonstrates

*   How enterprise file data can remain in place on Azure NetApp Files while being consumed by analytics and AI services
*   How OneLake shortcuts enable virtualized access to file data without copying it
*   How Azure AI Foundry agents can be grounded on enterprise data through Azure AI Search
*   How Azure NetApp Files participates as a first‑class data foundation for AI workloads on Azure

### The "Zero-Copy" Data Flow
1.  **Storage**: Financial docs in ANF (NFS/SMB) are exposed via **Object REST API** (S3-compatible).
2.  **Integration**: **Microsoft Fabric OneLake** shortcuts virtualize this data.
3.  **Indexing**: **Azure AI Search** indexes the virtualized data directly from OneLake.
4.  **Consumption**: **Azure AI Foundry** agents use the index to answer questions.

```mermaid
graph TD
    subgraph Storage [Storage Layer]
        ANF[("Azure NetApp Files\n(NFS/SMB Volume)")]
        ObjAPI["Object REST API\n(S3-Compatible Endpoint)"]
        ANF <--> ObjAPI
    end

    subgraph Integration [Integration Layer]
        Gateway["On-Premises\nData Gateway"]
        OneLake[("Microsoft Fabric\nOneLake")]
        Shortcut["OneLake Shortcut\n(S3-Compatible)"]
        
        ObjAPI -.->|HTTPS S3 Protocol| Gateway
        Gateway --> Shortcut
        Shortcut --> OneLake
    end

    subgraph Intelligence [Intelligence Layer]
        Indexer["OneLake Indexer"]
        AISearch[("Azure AI Search\n(Vector Store)")]
        Agent["Azure AI Foundry\nAgent (GPT-4)"]
        
        OneLake --> Indexer
        Indexer -->|Extract & Vectorize| AISearch
        AISearch <-->|retrieval| Agent
    end

    User("Financial Analyst") <-->|Chat| Agent
```

---

## Prerequisites & Environment Setup

This lab is designed to be approachable for customers and partners with general familiarity with Azure. The lab emphasizes solution flow and architectural intent, while calling out external documentation where deeper service‑level setup or advanced configuration may be required.

**Goal**: Prepare your Azure subscription and user account with all necessary providers and permissions.

## 1. Validate Azure Subscription Requirements
**Goal**: Ensure your Azure subscription is ready to run the lab without permission or provider issues.
1.  **Login**:
    *   Open a browser and go to **https://portal.azure.com**
    *   Sign in with your Azure work account.
2.  **Verify Subscription Role**:
    *   In the Azure portal, search for **Subscriptions**.
    *   Select the subscription you will use for the lab.
    *   Select **Access control (IAM)**.
    *   Confirm your user has **Owner** or **Contributor + User Access Administrator**.
3.  **Register Resource Providers**:
    *   From your subscription page, select Resource providers.
    *   Ensure the following providers are Registered:
        *   Microsoft.NetApp
        *   Microsoft.Search
        *   Microsoft.CognitiveServices
        *   Microsoft.MachineLearningServices (required for Azure AI Foundry)
        *   Microsoft.Fabric (required for OneLake / Fabric)
    *   If any show **Not registered**, select the resource provider and click **Register**.

## 2. Configure Azure NetApp Files
**Goal**: Create an Azure NetApp Files volume and enable S3‑compatible (Object REST API) access.
*   **Waitlist Approval**: The "Object REST API" features for Azure NetApp Files are in Public Preview. Ensure your subscription is whitelisted.
*   **Client Tool**: Instally a tool like **Cyberduck** or **S3 Browser** on your local machine to verify S3 connectivity.

### 2.1 Create NetApp Account and Capacity Pool

1. In the Azure portal, search for **Azure NetApp Files**.
2. Click **+ Create**.
    *   **Name**: Workshop-NetApp-Account
    *   **Region**: Choose a supported region (e.g., East US)
3. After creation, open the NetApp account.
4. Select **Capacity pools** → **+ Add pool**.
    *   **Name**: Workshop-Pool
    *   **Service level**: Standard
    *   **Size**: 1 TiB (minimum)
5. Click **Create**.

### 2.2 Create a Volume

1. In the NetApp account, select Volumes → + Add volume.
2. Configure the volume:
    *   **Name**: anf-finance-vol
    *   **Quota**: 100 GiB
    *   **Virtual network**: Select a VNet
    *   **Subnet**: Select a delegated subnet (Microsoft.NetApp/volumes)
    *   **Protocol**: NFS (NFSv3 recommended for this lab)
3. Click **Review + Create** → **Create**.

### 2.3 Enable Object (S3‑Compatible) Access

Note: Object REST API for Azure NetApp Files is in Public Preview. Ensure your subscription is approved.

1. Generate a Certificate (should this be uisng the portal?)
    *   Open a terminal/command prompt.
    *   Run: `openssl req -x509 -newkey rsa:4096 -keyout private.key -out cert.pem -days 365 -nodes`
    *   Save `cert.pem`.
2. Enable Object Access
    *   In the Azure portal, open your volume `anf-finance-vol`.
    *   Navigate to Object access / Buckets (blade name may vary).
    *   If prompted, click **Enable Object Access**.
3. Create a Bucket
    *   Click **+ Add Bucket**.
    *   Name: `finance-data`.
    *   Path: `/` (Root or applicable path).
    *   **Upload Certificate**: Upload the `cert.pem` file you generated.
    *   Click **Create**.
4. Capture Credentials
    *   Select View credentials (or Generate keys).
    *   Copy and save to a secure location:
        *   `Endpoint URL` (e.g., `https://10.0.0.4`)
        *   `Access Key`
        *   `Secret Key`

### 2.4 Download Lab Data
*   Download the `test_data` folder from this repository to your local machine.

### 2.5 Upload Lab Data

1. Install a client such as Cyberduck or S3 Browser.
2. Create a new S3 connection:
    *   **Endpoint**: `ANF Object endpoint`
    *   **Access key** / **Secret key**: From previous step
    *   Enable **Path‑style addressing** if prompted.
3. Upload the following folders to the bucket root:
    *   `invoices/`
    *   `financial_statements/`

---

## 3. Create a OneLake Shortcut to Azure NetApp Files

**Goal**: Virtualize Azure NetApp Files data into Microsoft Fabric OneLake without copying it.

### 3.1 Deploy On-Premises Data Gateway  (Required for Private S3-Compatible Endpoints)
1.  Create a **Windows VM** in the same VNet as your Azure NetApp Files volume:
    *   Size: Standard_D2s_v3 (Recommended)
2.  RDP into the VM.
3.  Download and install [On-premises data gateway (Standard mode)](https://aka.ms/gateway-installer).
4.  Sign in with your Azure Work Account and **Register a new gateway**:
    *   **Name**: ANF-Gateway
5.  Verify the gateway shows **Online**.

### 3.2 Create Fabric Workspace
1.  Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com).
2.  Select **Workspaces** → **+ New workspace**.
    *   **Name**: `Financial_RAG_Workshop`  
    *   **License mode**: Trial or Fabric capacity
3.  Click **Create**.

### 3.3 Create Connection and OneLake Shortcut
1.  In Fabric, open Settings (gear icon) → Manage connections and gateways.
2.  Select **+ New connection** → **Amazon S3 Compatible**.
    *   **Gateway**: `ANF-Gateway`
    *   **Server**: ANF endpoint IP
    *   **Authentication**: Access key / Secret key
3.  Create the connection.
4.  Create a Lakehouse:
    *   **Workspace** → **+ New item** → **Lakehouse**
    *   **Name**: `FinDataLake`
5.  Create Shortcut:
    *   Open Lakehouse, right-click **Files**
    *   Click **New shortcut**
    *   **Source**: `Amazon S3 Compatible`
    *   **Connection**: Select the ANF connection created in step 3.3.1
    *   **Bucket**: `finance-data`
    *   **Name**: `anf_shortcut`
6.  Verify folders are visible under the shortcut.

---

## 4. Index OneLake Data Using Azure AI Search

**Goal**: Make OneLake data searchable and usable for RAG.

### 4.1 Create Azure AI Search Service
1.  Azure portal → **Create a resource** → **Azure AI Search**.
2.  Select:
    *   **Tier**: Basic (Required for Semantic Search) or Standard.
3.  After creation:
    *   Go to **Identity** → Enable **System‑assigned managed identity**.

### 4.2 Assign Permissions
1.  Open your Fabric workspace (`Financial_RAG_Workshop`).
2.  Select **Manage access**.
3.  Add the **Azure AI Search Managed Identity** (search by service name) as a **Member** or **Contributor**.

### 4.3 Import and Vectorize Data
1.  Open Azure AI Search → **Import and vectorizing data**.
2.  **Source**: OneLake (Microsoft Fabric).
3.  **Connection**:
    *   Select "Microsoft Fabric".
    *   **Workspace** (`Financial_RAG_Workshop`)
    *   **Lakehouse** (`FinDataLake`).
    *   **Path**: `Files/anf_shortcut`.
4.  Configure Vectorization
    *   Kind: **Azure OpenAI**.
    *   *Dependency*: Use the Azure OpenAI resource created in Module 4 (or create one now).
    *   Select the Embedding model.
5.  Configure Index Settings:
    *   **Content**: Searchable.
    *   **Metadata_storage_path**: **Retrievable** (Must be checked!).
6.  Create and run the indexer.

---

## 5. Connect OneLake to Azure AI Foundry

**Goal**: Enable Foundry to ground agents on indexed enterprise data.

### 5.1 Create Azure AI Services Resource (The "Root" Resource)
1.  **Azure Portal** > **Create a resource** > **Azure AI services** (Multi-service account).
2.  **Configure**:
    *   **Name**: `Workshop-AI-Services`.
    *   **Region**: **East US 2** (or `Sweden Central`, `West US 3` - regions with GPT-4o).
    *   **Pricing Tier**: Standard S0.
3.  **Deploy Model**:
    *   Go to **Model deployments** (in the resource blade).
    *   Click **Manage Deployments** (opens Azure OpenAI Studio).
    *   **Deploy**: `gpt-4o` (or `gpt-4`). Name it `gpt-4o`.
    *   **Deploy**: `text-embedding-3-small`. Name it `text-embedding-3-small`.

### 5.2 Assign User Permissions

1.  Go to the `Workshop-AI-Services` resource > **Access control (IAM)**.
2.  **Add role assignment**.
    *   Role: **Cognitive Services OpenAI User** (allows you to run inference/chat).
    *   Members: Select **Your User Account**.
3.  **Review + assign**.

### 5.3 Create Foundry Project
1.  Go to [ai.azure.com](https://ai.azure.com).
2.  Click **+ Create Project**.
3.  **Project Details**:
    *   Name: `Finance-RAG-Project`.
    *   **Hub**: Click "Create new hub".
    *   Hub Name: `Finance-Hub`.
    *   **Resource Group**: Use your existing one.
4.  **Connect Resources**:
    *   **Azure OpenAI**: Select `Workshop-AI-Services`.
    *   **Azure AI Search**: Select the service created in Step 4.
5.  **Create**.

---

## 6. Run and Validate a Grounded Agent

**Goal**: Confirm the agent answers questions using ANF‑hosted data.

### 6.1 Configure Data Source (The RAG Link)
1.  In your Project > Left Menu > **Data** (or "Indexes").
2.  **+ New connection** > **Azure AI Search**.
3.  System will detect your connected service. Select the **Index** created in Step 4.

### 6.2 Create & Test Agent
1.  Left Menu > **Agents**, create agent
    *   **Deploy Model**: Select the `gpt-4o` deployment you created in step 5.1.
    *   **Add Knowledge**: Select the Search Index connection.
4.  **System Prompt**:
    ```text
    You are a Financial Auditor. 
    Use the attached financial data to answer questions. 
    Always cite the document name. 
    If data is in a CSV, calculate totals by summing rows.
    ```
5.  **Test**:
    *   *"What is the total spend for vendor 'OfficeMax'?"*
    *   *"Show me all transactions from Q1 2025."*

---

## 7. Troubleshooting

*   **Gateway Error**: Ensure the gateway VM has outbound 443 access to the ANF IP.
*   **OneLake Shortcut Empty**: Verify the bucket name in the shortcut settings matches the ANF bucket exactly.
*   **Indexer Error (403)**: Re-check Module 5.2. The Search Service Managed Identity MUST have permission on the Fabric Workspace/Item.
*   **Agent "I don't know"**: Check "Strictness" (set to 3) and ensure the Indexer ran successfully (is document count > 0?).
*   **Permissions Error in Foundry**: Ensure you assigned yourself **Cognitive Services OpenAI User** in Module 6.2.
