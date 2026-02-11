# Azure NetApp Files to Azure AI Foundry: Zero-Copy RAG Workshop

## Overview
This workshop demonstrates a **prescriptive enterprise approach** for deploying Retrieval‑Augmented Generation (RAG) without data duplication. Customers keep their governed, high‑value financial data in **Azure NetApp Files** as the system of record, expose it through **Microsoft Fabric OneLake**, and enable **Azure AI Foundry agents** to retrieve and reason over that data, without migrating or re‑platforming the source datasets.

The architecture establishes a **Zero‑Copy AI data path**: 
*   **Azure NetApp Files** provides performance, security, and enterprise file semantics
*   **Microsoft Fabric OneLake** virtualizes access using native shortcuts
*   **Azure AI Foundry** orchestrates retrieval, grounding, and agent workflows directly against the virtualized data
  This allows customers to stand up production‑ready RAG experiences faster, reduce data sprawl, and preserve existing governance and operational models.

The outcome is an **AI entry scenario** for regulated and data‑intensive enterprises: accelerate RAG adoption, minimize architectural disruption, and operationalize AI agents on trusted data—without creating new storage silos or brittle ingestion pipelines.

## Architecture
The solution leverages the **Azure NetApp Files object REST API** to expose file‑based data through an **S3‑compatible object interface**, enabling downstream analytics and AI services to access the same data without duplication.

1.  **Storage**: Azure NetApp Files (NFS/SMB) with Object REST API enabled
2.  **Data Access**: Microsoft Fabric OneLake using S3‑compatible shortcuts
3.  **Indexing & Retrieval**: Azure AI Search (OneLake files indexer) for indexing and enrichment, with **Azure AI Foundry agents** using the indexed content for retrieval‑augmented generation
4.  **Orchestration**: Azure AI Foundry agents consuming indexed content for retrieval‑augmented generation

## Repository Contents
*   **`lab_guide.md`**: The step-by-step instructions for the workshop.
*   **`test_data/`**: Dummy financial data (Invoices and CSV logs) for testing.
*   **`generate_data.py`**: Scripts used to generate the test data.

  
<img width="1654" height="929" alt="image" src="https://github.com/user-attachments/assets/5ee874f5-fe55-4bbf-ae2a-2b1d06a5b21c" />

## Video Resources

[![Azure NetApp Files Overview](https://img.youtube.com/vi/sPZs71kWECA/0.jpg)](https://www.youtube.com/watch?v=sPZs71kWECA)
[![Microsoft Fabric Integration](https://img.youtube.com/vi/BWyoOaeomOY/0.jpg)](https://www.youtube.com/watch?v=BWyoOaeomOY)
[![Azure AI Search](https://img.youtube.com/vi/4j94ownixEg/0.jpg)](https://www.youtube.com/watch?v=4j94ownixEg)
[![Azure AI Foundry](https://img.youtube.com/vi/kL_mJUCNiK4/0.jpg)](https://www.youtube.com/watch?v=kL_mJUCNiK4)

## Disclaimer
**educational-only**: This content is provided for educational and enablement purposes to demonstrate art-of-the-possible scenarios with Azure services. It is not intended for production use without further review and hardening. The authors and Microsoft assume no liability for the use of this code or documentation.

## License
This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
