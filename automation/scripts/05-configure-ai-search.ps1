# ============================================================================
# Step 5: Configure Azure AI Search (Data Source, Index, Skillset, Indexer)
# Uses AI Search REST API
# ============================================================================

param(
    [Parameter(Mandatory)][string]$SearchServiceEndpoint,
    [Parameter(Mandatory)][string]$SearchAdminKey,
    [Parameter(Mandatory)][string]$FabricWorkspaceId,
    [Parameter(Mandatory)][string]$LakehouseId,
    [Parameter(Mandatory)][string]$AiServicesEndpoint,
    [Parameter(Mandatory)][string]$AiServicesKey,
    [string]$ShortcutName = 'anf_shortcut',
    [string]$IndexName = 'rag-workshop-index',
    [string]$ConfigsPath
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 5: Configuring Azure AI Search ===" -ForegroundColor Cyan

if (-not $ConfigsPath) {
    $ConfigsPath = Join-Path $PSScriptRoot '..' 'configs'
}

$searchHeaders = @{
    'api-key'      = $SearchAdminKey
    'Content-Type' = 'application/json'
}

$apiVersion = '2024-07-01'

# --- Step 5.1: Create Data Source ---
Write-Host "  Creating OneLake data source..." -ForegroundColor Yellow

$datasourceBody = @{
    name        = 'onelake-datasource'
    type        = 'onelake'
    credentials = @{
        connectionString = "ResourceId=$FabricWorkspaceId"
    }
    container   = @{
        name  = $LakehouseId
        query = $ShortcutName
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$SearchServiceEndpoint/datasources/onelake-datasource?api-version=$apiVersion" `
    -Method Put -Headers $searchHeaders -Body $datasourceBody
Write-Host "  Data source created." -ForegroundColor Green

# --- Step 5.2: Create Skillset (Integrated Vectorization) ---
Write-Host "  Creating vectorization skillset..." -ForegroundColor Yellow

$skillsetBody = @{
    name        = 'rag-workshop-skillset'
    description = 'Skillset for chunking and vectorizing financial documents'
    skills      = @(
        @{
            '@odata.type' = '#Microsoft.Skills.Text.SplitSkill'
            name          = 'text-splitter'
            description   = 'Split text into chunks'
            context       = '/document'
            inputs        = @(
                @{ name = 'text'; source = '/document/content' }
            )
            outputs       = @(
                @{ name = 'textItems'; targetName = 'chunks' }
            )
            textSplitMode    = 'pages'
            maximumPageLength = 2000
            pageOverlapLength = 500
        }
        @{
            '@odata.type' = '#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill'
            name          = 'embedding'
            description   = 'Generate embeddings for each chunk'
            context       = '/document/chunks/*'
            modelName     = 'text-embedding-3-small'
            resourceUri   = $AiServicesEndpoint
            apiKey        = $AiServicesKey
            deploymentId  = 'text-embedding-3-small'
            inputs        = @(
                @{ name = 'text'; source = '/document/chunks/*' }
            )
            outputs       = @(
                @{ name = 'embedding'; targetName = 'vector' }
            )
        }
    )
    indexProjections = @{
        selectors = @(
            @{
                targetIndexName  = $IndexName
                parentKeyFieldName = 'parent_id'
                sourceContext     = '/document/chunks/*'
                mappings         = @(
                    @{ name = 'chunk'; source = '/document/chunks/*' }
                    @{ name = 'vector'; source = '/document/chunks/*/vector' }
                    @{ name = 'title'; source = '/document/metadata_storage_name' }
                    @{ name = 'source_url'; source = '/document/metadata_storage_path' }
                )
            }
        )
        parameters = @{
            projectionMode = 'generatedKeyAsId'
        }
    }
} | ConvertTo-Json -Depth 20

Invoke-RestMethod -Uri "$SearchServiceEndpoint/skillsets/rag-workshop-skillset?api-version=$apiVersion" `
    -Method Put -Headers $searchHeaders -Body $skillsetBody
Write-Host "  Skillset created." -ForegroundColor Green

# --- Step 5.3: Create Index ---
Write-Host "  Creating search index '$IndexName'..." -ForegroundColor Yellow

$indexConfig = Get-Content (Join-Path $ConfigsPath 'ai-search-index.json') -Raw
$indexConfig = $indexConfig -replace '\{INDEX_NAME\}', $IndexName

Invoke-RestMethod -Uri "$SearchServiceEndpoint/indexes/$IndexName`?api-version=$apiVersion" `
    -Method Put -Headers $searchHeaders -Body $indexConfig
Write-Host "  Index created." -ForegroundColor Green

# --- Step 5.4: Create Indexer ---
Write-Host "  Creating indexer..." -ForegroundColor Yellow

$indexerBody = @{
    name             = 'rag-workshop-indexer'
    dataSourceName   = 'onelake-datasource'
    targetIndexName  = $IndexName
    skillsetName     = 'rag-workshop-skillset'
    parameters       = @{
        configuration = @{
            dataToExtract = 'contentAndMetadata'
            parsingMode   = 'default'
        }
    }
    fieldMappings = @(
        @{
            sourceFieldName = 'metadata_storage_path'
            targetFieldName = 'source_url'
            mappingFunction = @{
                name = 'base64Encode'
            }
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$SearchServiceEndpoint/indexers/rag-workshop-indexer?api-version=$apiVersion" `
    -Method Put -Headers $searchHeaders -Body $indexerBody
Write-Host "  Indexer created." -ForegroundColor Green

# --- Step 5.5: Run the indexer ---
Write-Host "  Running indexer..." -ForegroundColor Yellow
Invoke-RestMethod -Uri "$SearchServiceEndpoint/indexers/rag-workshop-indexer/run?api-version=$apiVersion" `
    -Method Post -Headers $searchHeaders

# --- Wait for indexer to complete ---
Write-Host "  Waiting for indexer to complete..." -ForegroundColor Yellow
$maxWaitSeconds = 300
$elapsed = 0

do {
    Start-Sleep -Seconds 10
    $elapsed += 10
    $status = Invoke-RestMethod -Uri "$SearchServiceEndpoint/indexers/rag-workshop-indexer/status?api-version=$apiVersion" `
        -Headers $searchHeaders
    $execStatus = $status.lastResult.status
    Write-Host "    Indexer status: $execStatus ($elapsed`s)" -ForegroundColor Gray
} while ($execStatus -eq 'inProgress' -and $elapsed -lt $maxWaitSeconds)

if ($execStatus -eq 'success') {
    $docCount = $status.lastResult.itemCount
    Write-Host "  Indexer completed. Documents indexed: $docCount" -ForegroundColor Green
} else {
    Write-Warning "  Indexer status: $execStatus. Check Azure portal for details."
}

return @{
    IndexName = $IndexName
}
