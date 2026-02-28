# ============================================================================
# Step 6: Create Azure AI Foundry Agent with AI Search Grounding
# Uses AI Foundry REST API
# ============================================================================

param(
    [Parameter(Mandatory)][string]$AiServicesName,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$IndexName,
    [Parameter(Mandatory)][string]$SearchServiceName,
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$AgentName = 'Financial-Auditor-Agent',
    [string]$ModelDeployment = 'gpt-4o'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Step 6: Creating AI Foundry Agent ===" -ForegroundColor Cyan

# --- Get access token for AI Foundry ---
$token = az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv

$projectEndpoint = "https://${AiServicesName}.services.ai.azure.com/api/projects/${ProjectName}"

$agentHeaders = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = 'application/json'
}

$apiVersion = '2025-05-01'

# --- Read system prompt ---
$systemPromptPath = Join-Path $PSScriptRoot '..' 'configs' 'agent-system-prompt.txt'
if (Test-Path $systemPromptPath) {
    $systemPrompt = Get-Content $systemPromptPath -Raw
} else {
    $systemPrompt = @"
You are a Financial Auditor AI Agent.
Use the attached financial data to answer questions accurately.
Always cite the document name and specific data points.
If data is in a CSV, calculate totals by summing the relevant rows.
If you cannot find the answer in the provided data, say so clearly.
"@
}

# --- Build the connection resource ID for AI Search ---
$searchConnectionName = 'ai-search-connection'
$connectionResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/${ProjectName}/connections/$searchConnectionName"

# --- Create the agent ---
Write-Host "  Creating agent '$AgentName' with AI Search grounding..." -ForegroundColor Yellow

$agentBody = @{
    name         = $AgentName
    instructions = $systemPrompt
    model        = $ModelDeployment
    tools        = @(
        @{
            type            = 'azure_ai_search'
            azure_ai_search = @{
                index_name   = $IndexName
                query_type   = 'semantic'
                top_k        = 5
            }
        }
    )
} | ConvertTo-Json -Depth 10

$agent = Invoke-RestMethod -Uri "$projectEndpoint/openai/assistants?api-version=$apiVersion" `
    -Method Post -Headers $agentHeaders -Body $agentBody

$agentId = $agent.id
Write-Host "  Agent created: $agentId" -ForegroundColor Green

# --- Create a test thread and run a sample query ---
Write-Host "`n  Running a test query to verify grounding..." -ForegroundColor Yellow

# Create thread
$thread = Invoke-RestMethod -Uri "$projectEndpoint/openai/threads?api-version=$apiVersion" `
    -Method Post -Headers $agentHeaders -Body '{}' -ContentType 'application/json'
$threadId = $thread.id

# Add message
$messageBody = @{
    role    = 'user'
    content = 'What is the total spend for vendor OfficeMax across all quarters?'
} | ConvertTo-Json

Invoke-RestMethod -Uri "$projectEndpoint/openai/threads/$threadId/messages?api-version=$apiVersion" `
    -Method Post -Headers $agentHeaders -Body $messageBody

# Run the thread
$runBody = @{
    assistant_id = $agentId
} | ConvertTo-Json

$run = Invoke-RestMethod -Uri "$projectEndpoint/openai/threads/$threadId/runs?api-version=$apiVersion" `
    -Method Post -Headers $agentHeaders -Body $runBody

# Poll for completion
$maxWait = 60
$elapsed = 0
do {
    Start-Sleep -Seconds 5
    $elapsed += 5
    $runStatus = Invoke-RestMethod -Uri "$projectEndpoint/openai/threads/$threadId/runs/$($run.id)?api-version=$apiVersion" `
        -Headers $agentHeaders
} while ($runStatus.status -in @('queued', 'in_progress') -and $elapsed -lt $maxWait)

if ($runStatus.status -eq 'completed') {
    $messages = Invoke-RestMethod -Uri "$projectEndpoint/openai/threads/$threadId/messages?api-version=$apiVersion" `
        -Headers $agentHeaders
    $response = ($messages.data | Where-Object { $_.role -eq 'assistant' } | Select-Object -First 1).content[0].text.value
    Write-Host "`n  Agent Response:" -ForegroundColor Green
    Write-Host "  $response" -ForegroundColor White
} else {
    Write-Host "  Test query status: $($runStatus.status)" -ForegroundColor Yellow
}

Write-Host "`n  Agent is ready for use in AI Foundry portal." -ForegroundColor Green

return @{
    AgentId    = $agentId
    AgentName  = $AgentName
    PortalUrl  = "https://ai.azure.com"
}
