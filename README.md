# Azure NetApp Files to Azure AI Foundry: Zero-Copy RAG Workshop

## Overview
This repository contains the lab guide and resources for building an **Enterprise RAG (Retrieval-Augmented Generation)** pipeline. The workshop demonstrates a "Zero-Copy" architecture where financial data stored in **Azure NetApp Files (ANF)** is exposed to **Azure AI Foundry** agents via **Microsoft Fabric OneLake**, without manual data migration.

## Architecture
The solution leverages the **ANF Object REST API** to project files as S3 objects, which are then virtualized in OneLake and indexed by Azure AI Search.

1.  **Storage**: Azure NetApp Files (NFS/SMB) with Object REST API enabled.
2.  **Integration**: Microsoft Fabric OneLake via S3-Compatible Shortcuts.
3.  **Intelligence**: Azure AI Search (OneLake Indexer) and Azure AI Foundry Agents.

## Repository Contents
*   **`lab_guide.md`**: The step-by-step instructions for the workshop.
*   **`test_data/`**: Dummy financial data (Invoices and CSV logs) for testing.
*   **`generate_data.py`**: Scripts used to generate the test data.

## Disclaimer
**educational-only**: This content is provided for educational and enablement purposes to demonstrate art-of-the-possible scenarios with Azure services. It is not intended for production use without further review and hardening. The authors and Microsoft assume no liability for the use of this code or documentation.

## License
This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
