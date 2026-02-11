# Workshop Walkthrough

I have prepared a complete content package for your **Azure NetApp Files to Azure AI Foundry Workshop**. This package enables you to demonstrate a sophisticated "Zero-Copy" RAG architecture to financial customers.

## Architecture Overview

The following diagram illustrates the data flow users will build:

```mermaid
graph LR
    subgraph On-Premises/VNet
    ANF[("Azure NetApp Files")] <--> Gateway[("Data Gateway")]
    end
    
    subgraph "Fabric & AI"
    Gateway --> OneLake[("OneLake Shortcut")]
    OneLake --> Indexer["AI Search Indexer"]
    Indexer --> VectorDB[("Vector Store")]
    VectorDB <--> Agent["AI Foundry Agent"]
    end
```

## Included Artifacts

### 1. The Lab Guide (`lab_guide.md`)
*   **Path**: [lab_guide.md](file:///Users/dwirefs/.gemini/antigravity/brain/a59cccc5-2ee2-43ef-94f7-912d14d9b49f/lab_guide.md)
*   **Status**: **End-to-End Comprehensive**.
*   **Key Enhancements**:
    *   **Module 0: Environment Setup**: Starts at the very beginning with registering Resource Providers (`Microsoft.NetApp`, `Microsoft.Search`, etc.) and assigning Subscription-level RBAC roles.
    *   **Dependency-Aware**: Explicitly lists prerequisites for each step (e.g., creating a Fabric Workspace before a Lakehouse, creating an OpenAI resource before indexing).
    *   **Granular IAM Steps**: Details exactly where to assign permissions (e.g., assigning "Member" role to the Search Service Managed Identity in the Fabric Workspace).
    *   **Specific Configurations**: Corrected ANF Object Access steps (Certificates, Buckets) and AI Search OneLake connection paths.

### 2. Dummy Data Suite (`test_data/`)
*   **Path**: [test_data](file:///Users/dwirefs/.gemini/antigravity/brain/a59cccc5-2ee2-43ef-94f7-912d14d9b49f/test_data)
*   **Status**: **Ready**.
*   **Contents**:
    *   `invoices/`: 10 HTML invoices representing unstructured vendor bills.
    *   `financial_statements/`: 2 CSV files representing structured ERP transaction logs.

## How to use this
1.  **Distribute**: Send the `lab_guide.md` and `test_data` folder to your workshop participants.
2.  **Pre-Flight**: ensure their subscriptions are whitelisted for the ANF Object Access preview interactively.
3.  **Run**: Follow the guide Module-by-Module. The new "Practical Testing" section in Module 5 provides a strong "wow" moment for the demo.
