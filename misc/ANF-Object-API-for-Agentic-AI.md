# Azure NetApp Files Object REST API for Agentic AI

A technical analysis of how Azure NetApp Files (ANF) Object REST API — with its focused set of S3-compatible operations — serves as a data foundation for modern agentic AI architectures, including RAG pipelines, MCP data sources, LangChain document loaders, and direct agent tool access.

---

## Table of Contents

1. [The ANF Object REST API — What It Supports](#1-the-anf-object-rest-api--what-it-supports)
2. [Why 5-6 Operations Are Enough for AI](#2-why-5-6-operations-are-enough-for-ai)
3. [Pattern 1: RAG Pipeline via Azure AI PaaS Ecosystem](#3-pattern-1-rag-pipeline-via-azure-ai-paas-ecosystem)
4. [Pattern 2: MCP Data Source for AI Agents](#4-pattern-2-mcp-data-source-for-ai-agents)
5. [Pattern 3: LangChain / LlamaIndex Document Loaders](#5-pattern-3-langchain--llamaindex-document-loaders)
6. [Pattern 4: AI Agent Custom Function Tools](#6-pattern-4-ai-agent-custom-function-tools)
7. [Pattern 5: Semantic Kernel Plugins](#7-pattern-5-semantic-kernel-plugins)
8. [Pattern 6: Direct SDK Access from Agentic Frameworks](#8-pattern-6-direct-sdk-access-from-agentic-frameworks)
9. [Operation-by-Operation Mapping Across All Patterns](#9-operation-by-operation-mapping-across-all-patterns)
10. [What You Cannot Do (And Why It Does Not Matter)](#10-what-you-cannot-do-and-why-it-does-not-matter)
11. [TLS and Networking Considerations](#11-tls-and-networking-considerations)
12. [Summary: ANF as the Enterprise Data Layer for AI](#12-summary-anf-as-the-enterprise-data-layer-for-ai)

---

## 1. The ANF Object REST API — What It Supports

Azure NetApp Files Object REST API (currently in preview) exposes NFS/SMB volume data through an S3-compatible HTTPS endpoint. The supported operations are:

| # | S3 Operation | HTTP Method | Description |
|---|-------------|-------------|-------------|
| 1 | `ListBuckets` | `GET /` | List all buckets on the volume |
| 2 | `ListObjectsV2` | `GET /{bucket}?list-type=2` | List objects in a bucket with optional prefix filtering |
| 3 | `GetObject` | `GET /{bucket}/{key}` | Download an object's content |
| 4 | `PutObject` | `PUT /{bucket}/{key}` | Upload an object |
| 5 | `DeleteObject` | `DELETE /{bucket}/{key}` | Delete an object |
| 6 | `HeadObject` | `HEAD /{bucket}/{key}` | Get object metadata without downloading content |

By comparison, AWS S3 supports over 200 API actions. This naturally raises the question: are 5-6 operations enough for modern agentic AI workloads?

**The answer is yes — and this document explains why across every relevant AI integration pattern.**

---

## 2. Why 5-6 Operations Are Enough for AI

The core insight is that AI workloads interact with data as **content consumers**, not as **storage platform administrators**. The S3 API's 200+ operations exist primarily for:

- **Storage management**: versioning, lifecycle policies, replication, cross-region copy
- **Access control**: bucket policies, ACLs, presigned URLs, CORS configuration
- **Enterprise features**: encryption key management, inventory reports, analytics
- **Optimization**: multipart upload orchestration, S3 Select (in-place query), Glacier tiering

None of these are needed when an AI system wants to:
1. **Discover** what files are available → `ListObjectsV2`
2. **Read** a file's content → `GetObject`
3. **Check** if a file exists or get its metadata → `HeadObject`
4. **Write** results back (optional) → `PutObject`

That is the complete surface area for AI data access. Every pattern below — RAG, MCP, LangChain, function tools, Semantic Kernel — uses only these operations.

---

## 3. Pattern 1: RAG Pipeline via Azure AI PaaS Ecosystem

This is the pattern implemented in the Zero-Copy RAG Workshop (`automation/` folder in this repository).

### Architecture

```
ANF Volume (NFS/SMB)
    │
    ▼ Object REST API (S3-compatible)
ANF Bucket
    │
    ▼ S3 Protocol (ListObjects, GetObject)
On-Premises Data Gateway
    │
    ▼ Bridges VNet to Fabric SaaS
Microsoft Fabric OneLake Shortcut (zero-copy virtualization)
    │
    ▼ OneLake Indexer
Azure AI Search
    │ Document Intelligence Layout → Split → Embedding
    ▼
Vector + Semantic Index
    │
    ▼ azure_ai_search tool
Azure AI Foundry Agent (GPT-4o)
    │
    ▼
Grounded Answers with Citations
```

### S3 Operations Used

| Stage | Operation | Purpose |
|-------|-----------|---------|
| Data upload | `PutObject` | Upload financial documents to ANF bucket |
| Data upload | `ListObjectsV2` | Verify uploaded files |
| OneLake shortcut | `ListObjectsV2` | Fabric discovers available files |
| OneLake shortcut | `GetObject` | Fabric reads file content on demand |
| AI Search indexer | `ListObjectsV2` | Indexer enumerates files to process (via OneLake) |
| AI Search indexer | `GetObject` | Indexer reads file content for skill processing (via OneLake) |

### Why This Works with Limited Operations

The key insight: **at query time, the AI agent never touches S3**. The agent queries only the pre-built AI Search vector index. The S3 operations occur only during:
1. Initial data upload (one-time)
2. Indexer runs (periodic, read-heavy)

This is a **write-once, read-many, query-the-index** pattern. ANF's operations are more than sufficient.

### What Azure AI Services Are Involved

All native Azure PaaS — no external services:
- **Azure NetApp Files** — Storage with S3-compatible Object REST API
- **Microsoft Fabric OneLake** — Data virtualization via shortcuts
- **Azure AI Search** — Indexing, vectorization, hybrid retrieval
- **Azure AI Services** — GPT-4o (chat), text-embedding-3-small (vectors), Document Intelligence (layout extraction)
- **Azure AI Foundry** — Agent orchestration with grounded search tool

---

## 4. Pattern 2: MCP Data Source for AI Agents

The Model Context Protocol (MCP) is an open protocol for providing context and tools to AI models. MCP servers expose data sources that agents can query at runtime.

### How S3 MCP Servers Work

Existing MCP servers for S3 (e.g., community `mcp-server-s3` implementations) expose tools like:

```
list_buckets()      → calls ListBuckets
list_objects()      → calls ListObjectsV2
read_object()       → calls GetObject
write_object()      → calls PutObject (optional)
```

That is the complete tool surface. No other S3 operations are needed.

### ANF as an MCP Data Source

Since ANF's Object REST API is S3-compatible, an MCP server for ANF is identical to an S3 MCP server — just pointed at a different endpoint:

```python
import boto3
from mcp.server import Server

# Configure boto3 to talk to ANF instead of AWS
s3_client = boto3.client(
    's3',
    endpoint_url='https://<anf-volume-ip>',        # ANF Object REST API endpoint
    aws_access_key_id='<anf-access-key>',
    aws_secret_access_key='<anf-secret-key>',
    verify=False                                     # Self-signed cert handling
)

server = Server("anf-data-source")

@server.tool("list_buckets")
async def list_buckets():
    """List all available data buckets on ANF."""
    response = s3_client.list_buckets()
    return [b['Name'] for b in response['Buckets']]

@server.tool("list_files")
async def list_files(bucket: str, prefix: str = ""):
    """List files in a bucket, optionally filtered by prefix."""
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    return [
        {"key": obj['Key'], "size": obj['Size'], "modified": str(obj['LastModified'])}
        for obj in response.get('Contents', [])
    ]

@server.tool("read_file")
async def read_file(bucket: str, key: str):
    """Read the content of a file from ANF storage."""
    obj = s3_client.get_object(Bucket=bucket, Key=key)
    content = obj['Body'].read()
    # For text files, decode; for binary, base64 encode
    try:
        return content.decode('utf-8')
    except UnicodeDecodeError:
        import base64
        return base64.b64encode(content).decode('ascii')

@server.tool("get_file_info")
async def get_file_info(bucket: str, key: str):
    """Get metadata about a file without downloading it."""
    response = s3_client.head_object(Bucket=bucket, Key=key)
    return {
        "size": response['ContentLength'],
        "type": response.get('ContentType', 'unknown'),
        "modified": str(response['LastModified'])
    }

@server.tool("save_file")
async def save_file(bucket: str, key: str, content: str):
    """Write content back to ANF storage."""
    s3_client.put_object(Bucket=bucket, Key=key, Body=content.encode('utf-8'))
    return {"status": "saved", "key": key}
```

### S3 Operations Used by MCP

| MCP Tool | S3 Operation | ANF Support |
|----------|-------------|-------------|
| `list_buckets` | `ListBuckets` | Supported |
| `list_files` | `ListObjectsV2` | Supported |
| `read_file` | `GetObject` | Supported |
| `get_file_info` | `HeadObject` | Supported |
| `save_file` | `PutObject` | Supported |

**100% coverage.** No missing operations.

### How an Agent Uses This

With ANF exposed as an MCP data source, an AI agent can:

1. **Discover data**: "What files are available?" → agent calls `list_files`
2. **Read on demand**: "Show me invoice INV-3832" → agent calls `read_file`
3. **Selective access**: Agent decides which files to read based on the user's question, rather than having everything pre-indexed
4. **Write results**: Agent generates a summary report and saves it back → `save_file`

This is complementary to the RAG pattern — RAG pre-indexes everything for fast retrieval, while MCP gives agents on-demand access to specific files when needed.

---

## 5. Pattern 3: LangChain / LlamaIndex Document Loaders

Both LangChain and LlamaIndex provide S3 document loaders that work with any S3-compatible endpoint.

### LangChain

```python
from langchain_community.document_loaders import S3DirectoryLoader, S3FileLoader

# Load all documents from an ANF bucket
loader = S3DirectoryLoader(
    bucket='finance-data',
    prefix='invoices/',
    endpoint_url='https://<anf-volume-ip>',
    aws_access_key_id='<anf-access-key>',
    aws_secret_access_key='<anf-secret-key>',
    verify_ssl=False
)

docs = loader.load()
# Under the hood: ListObjectsV2 to enumerate, GetObject to download each file

# Load a single specific file
single_loader = S3FileLoader(
    bucket='finance-data',
    key='invoices/inv-3832.html',
    endpoint_url='https://<anf-volume-ip>',
    aws_access_key_id='<anf-access-key>',
    aws_secret_access_key='<anf-secret-key>',
    verify_ssl=False
)

doc = single_loader.load()
# Under the hood: GetObject only
```

### LlamaIndex

```python
from llama_index.readers.s3 import S3Reader

reader = S3Reader(
    bucket='finance-data',
    prefix='financial_statements/',
    s3_endpoint_url='https://<anf-volume-ip>',
    aws_access_key_id='<anf-access-key>',
    aws_secret_access_key='<anf-secret-key>',
)

documents = reader.load_data()
# Same pattern: ListObjectsV2 + GetObject
```

### S3 Operations Used

| Framework | Operations Used | ANF Support |
|-----------|----------------|-------------|
| LangChain `S3DirectoryLoader` | `ListObjectsV2`, `GetObject` | Both supported |
| LangChain `S3FileLoader` | `GetObject` | Supported |
| LlamaIndex `S3Reader` | `ListObjectsV2`, `GetObject` | Both supported |

### Use Case: Build Your Own RAG Pipeline

With LangChain/LlamaIndex, you can build a custom RAG pipeline that reads directly from ANF:

```python
from langchain_community.document_loaders import S3DirectoryLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_openai import AzureOpenAIEmbeddings
from langchain_community.vectorstores import FAISS

# 1. Load documents from ANF
loader = S3DirectoryLoader(bucket='finance-data', ...)
docs = loader.load()

# 2. Chunk
splitter = RecursiveCharacterTextSplitter(chunk_size=2000, chunk_overlap=500)
chunks = splitter.split_documents(docs)

# 3. Embed and store in vector DB
embeddings = AzureOpenAIEmbeddings(model="text-embedding-3-small", ...)
vectorstore = FAISS.from_documents(chunks, embeddings)

# 4. Query
retriever = vectorstore.as_retriever(search_kwargs={"k": 5})
results = retriever.invoke("What is the total spend for OfficeMax?")
```

This gives you full control over the chunking, embedding, and retrieval strategy, while ANF's `ListObjectsV2` and `GetObject` handle all the data access.

---

## 6. Pattern 4: AI Agent Custom Function Tools

Azure AI Foundry agents, OpenAI Assistants, and other agent frameworks support custom function/tool calling. You can expose ANF data as a callable tool that the agent invokes when it needs document content.

### Azure AI Foundry Agent with Custom ANF Tool

```python
import boto3

# ANF S3 client
s3 = boto3.client('s3',
    endpoint_url='https://<anf-volume-ip>',
    aws_access_key_id='<anf-access-key>',
    aws_secret_access_key='<anf-secret-key>',
    verify=False
)

# Define function tools for the agent
tools = [
    {
        "type": "function",
        "function": {
            "name": "list_available_documents",
            "description": "List all available financial documents in enterprise storage",
            "parameters": {
                "type": "object",
                "properties": {
                    "folder": {
                        "type": "string",
                        "description": "Folder prefix to filter, e.g. 'invoices/' or 'financial_statements/'"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_document",
            "description": "Read the full content of a specific financial document",
            "parameters": {
                "type": "object",
                "properties": {
                    "file_path": {
                        "type": "string",
                        "description": "Path to the file, e.g. 'invoices/inv-3832.html'"
                    }
                },
                "required": ["file_path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "check_document_exists",
            "description": "Check if a specific document exists and get its size",
            "parameters": {
                "type": "object",
                "properties": {
                    "file_path": {
                        "type": "string",
                        "description": "Path to the file"
                    }
                },
                "required": ["file_path"]
            }
        }
    }
]

# Tool handlers
def handle_tool_call(tool_name, arguments):
    if tool_name == "list_available_documents":
        prefix = arguments.get("folder", "")
        response = s3.list_objects_v2(Bucket='finance-data', Prefix=prefix)
        return [obj['Key'] for obj in response.get('Contents', [])]

    elif tool_name == "read_document":
        obj = s3.get_object(Bucket='finance-data', Key=arguments['file_path'])
        return obj['Body'].read().decode('utf-8')

    elif tool_name == "check_document_exists":
        try:
            response = s3.head_object(Bucket='finance-data', Key=arguments['file_path'])
            return {"exists": True, "size_bytes": response['ContentLength']}
        except s3.exceptions.ClientError:
            return {"exists": False}
```

### How the Agent Uses These Tools

```
User: "What vendor had the highest total spend in Q1 2025?"

Agent thinking:
  1. I need to find financial statement files → calls list_available_documents(folder="financial_statements/")
  2. Returns: ["financial_statements/q1_2025_expenses.csv", "financial_statements/q2_2025_expenses.csv"]
  3. I need Q1 data → calls read_document(file_path="financial_statements/q1_2025_expenses.csv")
  4. Returns: CSV content with vendor, amount, category columns
  5. Agent parses the CSV, sums by vendor, identifies the highest

Agent response: "Based on the Q1 2025 expense report, Dell Computers had the highest
total spend at $47,250 across 3 transactions..."
```

The agent decides at runtime which files to read. It does not need to see all files — it discovers, selects, and reads on demand. ANF's `ListObjectsV2`, `GetObject`, and `HeadObject` cover everything.

---

## 7. Pattern 5: Semantic Kernel Plugins

Microsoft Semantic Kernel (the AI orchestration SDK used in many Azure AI solutions) supports plugins that can be registered as agent tools.

### ANF S3 Plugin for Semantic Kernel

```csharp
using Amazon.S3;
using Microsoft.SemanticKernel;

public class AnfStoragePlugin
{
    private readonly IAmazonS3 _s3Client;

    public AnfStoragePlugin()
    {
        var config = new AmazonS3Config
        {
            ServiceURL = "https://<anf-volume-ip>",
            ForcePathStyle = true
        };
        _s3Client = new AmazonS3Client("<access-key>", "<secret-key>", config);
    }

    [KernelFunction("list_documents")]
    [Description("List available documents in enterprise storage")]
    public async Task<string> ListDocumentsAsync(
        [Description("Folder prefix to filter")] string prefix = "")
    {
        // Uses ListObjectsV2 — supported by ANF
        var request = new ListObjectsV2Request { BucketName = "finance-data", Prefix = prefix };
        var response = await _s3Client.ListObjectsV2Async(request);
        var files = response.S3Objects.Select(o => o.Key);
        return string.Join("\n", files);
    }

    [KernelFunction("read_document")]
    [Description("Read the content of a specific document")]
    public async Task<string> ReadDocumentAsync(
        [Description("File path")] string filePath)
    {
        // Uses GetObject — supported by ANF
        var response = await _s3Client.GetObjectAsync("finance-data", filePath);
        using var reader = new StreamReader(response.ResponseStream);
        return await reader.ReadToEndAsync();
    }
}

// Register with Semantic Kernel
var kernel = Kernel.CreateBuilder()
    .AddAzureOpenAIChatCompletion("gpt-4o", endpoint, apiKey)
    .Build();

kernel.Plugins.AddFromObject(new AnfStoragePlugin(), "storage");
```

### S3 Operations Used

| Plugin Method | S3 Operation | ANF Support |
|--------------|-------------|-------------|
| `ListDocumentsAsync` | `ListObjectsV2` | Supported |
| `ReadDocumentAsync` | `GetObject` | Supported |
| (optional) `SaveDocumentAsync` | `PutObject` | Supported |

---

## 8. Pattern 6: Direct SDK Access from Agentic Frameworks

Beyond the patterns above, several agentic AI frameworks provide or support S3-compatible storage access:

### AutoGen / AG2

Microsoft AutoGen agents can use custom tools. The same `boto3` pattern from Pattern 4 applies — register `list_objects`, `get_object` as callable tools.

### CrewAI

CrewAI agents support custom tools that can be implemented with `boto3` for S3-compatible access to ANF.

### OpenAI Assistants API (via Code Interpreter)

When using Code Interpreter, you can upload files from ANF to the assistant's sandbox:

```python
# Read from ANF, then upload to assistant
obj = s3.get_object(Bucket='finance-data', Key='invoices/inv-3832.html')
content = obj['Body'].read()

# Upload to OpenAI file storage for Code Interpreter
file = client.files.create(file=content, purpose="assistants")
```

This uses `GetObject` — supported by ANF.

### Azure AI Agent Service (File Search)

Azure AI Agent Service supports a `file_search` tool. Files can be pulled from ANF and uploaded to the agent's vector store:

```python
# Read files from ANF and add to agent's vector store
for key in list_objects(bucket='finance-data'):
    content = s3.get_object(Bucket='finance-data', Key=key)['Body'].read()
    # Upload to agent's file search vector store
    client.files.create(file=content, purpose="assistants")
```

Again, only `ListObjectsV2` and `GetObject` needed.

---

## 9. Operation-by-Operation Mapping Across All Patterns

This matrix shows which ANF Object REST API operations are used by each AI integration pattern:

| S3 Operation | RAG Pipeline | MCP Server | LangChain | Function Tools | Semantic Kernel | File Upload |
|-------------|:---:|:---:|:---:|:---:|:---:|:---:|
| `ListBuckets` | | Yes | | Optional | | |
| `ListObjectsV2` | Yes | Yes | Yes | Yes | Yes | Yes |
| `GetObject` | Yes | Yes | Yes | Yes | Yes | Yes |
| `HeadObject` | | Yes | | Optional | | |
| `PutObject` | Yes | Optional | | Optional | Optional | |
| `DeleteObject` | | Optional | | Optional | | |

**Key takeaway:** `ListObjectsV2` and `GetObject` are the only two operations universally required across all patterns. ANF supports both. The other operations add optional capabilities (metadata checking, write-back, cleanup) that ANF also supports.

---

## 10. What You Cannot Do (And Why It Does Not Matter)

ANF's Object REST API does not support these S3 operations. Here is why none of them are needed for agentic AI:

| Missing S3 Feature | What It Does | Why Agents Don't Need It |
|---|---|---|
| **Presigned URLs** | Generate temporary download links | Agents read content directly via `GetObject`; they don't generate browser-facing download links |
| **Multipart Upload** | Upload large files in parts | Agents typically write small outputs (summaries, reports). Large file ingestion uses standard `PutObject` or `aws s3 sync` |
| **Versioning** | Track file version history | Agents read current state. Version history is a storage management concern |
| **Lifecycle Policies** | Auto-archive/delete old files | Storage management, not agent functionality |
| **Bucket Policies / ACLs** | Fine-grained access control per object | Security is managed at the ANF/Azure RBAC level |
| **S3 Select** | Run SQL-like queries inside objects | Agents read full files and reason over them in context. In-place query is an optimization, not a requirement |
| **Cross-Region Replication** | Replicate objects across regions | Infrastructure concern, not agent concern |
| **Inventory Reports** | Bulk object metadata listing | `ListObjectsV2` is sufficient for agent-scale discovery |
| **Object Lock / Legal Hold** | Immutability and compliance | Governance concern, not agent concern |
| **Event Notifications** | Trigger on object changes | Can be solved at the Azure level (Event Grid on ANF volume changes) |
| **Server-Side Encryption Config** | Manage encryption keys | ANF handles encryption at the volume level — transparent to agents |

**None of these gaps affect an agent's ability to discover, read, or write data.**

---

## 11. TLS and Networking Considerations

When connecting AI frameworks to ANF's Object REST API, there are practical considerations:

### Self-Signed TLS Certificates

ANF Object REST API uses TLS certificates that may be self-signed (especially in the current preview). Frameworks need to handle this:

| Framework | How to Handle |
|-----------|--------------|
| **boto3 (Python)** | `verify=False` or `verify='/path/to/ca-bundle.crt'` |
| **AWS SDK (.NET)** | Custom `HttpClientHandler` with certificate callback |
| **AWS CLI** | `--no-verify-ssl` flag |
| **LangChain** | `verify_ssl=False` parameter on S3 loaders |
| **Node.js AWS SDK** | `NODE_TLS_REJECT_UNAUTHORIZED=0` or custom agent |

For production, import the ANF certificate into the trusted certificate store of the machine running the agent/MCP server.

### VNet-Isolated Endpoints

ANF volumes are VNet-bound. The AI agent or MCP server must be able to reach the ANF endpoint:

- **Same VNet**: Direct access (ideal for VM-hosted agents)
- **Different VNet**: VNet peering
- **External/SaaS services**: On-Premises Data Gateway (the pattern used in this workshop for Fabric)
- **Container-hosted agents**: Deploy in a VNet-integrated Azure Container Apps or AKS

### Endpoint URL Format

```
https://<volume-ip-address>
```

The IP address comes from the ANF volume's mount target. It is stable for the lifetime of the volume.

---

## 12. Summary: ANF as the Enterprise Data Layer for AI

Azure NetApp Files Object REST API, despite supporting only 5-6 S3 operations, provides **complete coverage** for every modern agentic AI data access pattern:

```
                    ┌──────────────────────────────────────────┐
                    │        ANF Object REST API               │
                    │     ListBuckets  |  ListObjectsV2        │
                    │     GetObject    |  HeadObject            │
                    │     PutObject    |  DeleteObject          │
                    └──────────┬───────────────────────────────┘
                               │
          ┌────────────────────┼────────────────────────┐
          │                    │                        │
    ┌─────▼──────┐     ┌──────▼───────┐     ┌──────────▼──────────┐
    │  Indexed   │     │   Direct     │     │    Framework        │
    │  Access    │     │   Access     │     │    Integration      │
    │            │     │              │     │                     │
    │  OneLake → │     │  MCP Server  │     │  LangChain Loaders  │
    │  AI Search │     │  Function    │     │  LlamaIndex Reader  │
    │  → Agent   │     │  Tools       │     │  Semantic Kernel    │
    │            │     │  Custom SDK  │     │  AutoGen / CrewAI   │
    └────────────┘     └──────────────┘     └─────────────────────┘

    Pre-indexed,         On-demand,            Programmatic,
    fast retrieval       agent-driven          framework-native
    via vector search    file access           document loading
```

### Why ANF Is Uniquely Positioned

1. **Dual-protocol access**: The same files are accessible via NFS/SMB (for traditional applications) and S3 (for AI agents). No data duplication needed.

2. **Enterprise-grade storage**: Sub-millisecond latency, up to 4.5 GiB/s throughput, snapshots, replication — all the enterprise features without compromising on AI accessibility.

3. **Zero-copy architecture**: Data stays in one place. Whether accessed via a RAG pipeline, an MCP server, a LangChain loader, or a custom agent tool — the files are read from ANF, not copied to a new store.

4. **Governed data foundation**: Data governance, access control, and compliance stay at the storage layer (Azure RBAC, ANF export policies, VNet isolation). AI agents access data through controlled endpoints with credentials.

5. **Future-proof**: As new agentic AI patterns emerge (new MCP tools, new orchestration frameworks, new agent architectures), they will need the same fundamental operations: list files, read files, optionally write files. ANF's Object REST API covers all of these.

### The Bottom Line

The hundreds of S3 operations that ANF does not support exist for **storage platform management** — versioning, lifecycle, replication, encryption management, bucket policies. These are infrastructure concerns, not AI agent concerns.

For AI agents, data access is simple: find files, read files, sometimes write files. ANF's 5-6 operations are not a limitation — they are exactly the right surface area for a focused, secure, enterprise data access layer that serves as the foundation for modern agentic AI architectures.
