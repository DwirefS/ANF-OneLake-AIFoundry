// ============================================================================
// Azure AI Foundry Module
// Creates Hub dependencies (Storage, Key Vault), Hub, and Project
// Also creates connections to AI Search and AI Services
// ============================================================================

@description('Azure region')
param location string

@description('Resource name prefix')
param prefix string

@description('AI Services resource ID')
param aiServicesId string

@description('AI Services resource name')
param aiServicesName string

@description('AI Search resource ID')
param searchServiceId string

@description('AI Search resource name')
param searchServiceName string

@description('AI Search endpoint')
param searchServiceEndpoint string

// --- Storage Account (required by AI Hub) ---
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: replace('${prefix}hubstore', '-', '')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// --- Key Vault (required by AI Hub) ---
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${prefix}-hub-kv'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// --- AI Foundry Hub ---
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: '${prefix}-hub'
  location: location
  kind: 'Hub'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Finance RAG Hub'
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    publicNetworkAccess: 'Enabled'
  }
}

// --- Connection: AI Services ---
resource aiServicesConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiHub
  name: 'ai-services-connection'
  properties: {
    category: 'AIServices'
    target: 'https://${aiServicesName}.cognitiveservices.azure.com'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServicesId
    }
  }
}

// --- Connection: AI Search ---
resource aiSearchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiHub
  name: 'ai-search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: searchServiceEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchServiceId
    }
  }
}

// --- AI Foundry Project ---
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: '${prefix}-project'
  location: location
  kind: 'Project'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Finance RAG Project'
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
}

output aiHubName string = aiHub.name
output aiHubId string = aiHub.id
output aiProjectName string = aiProject.name
output aiProjectId string = aiProject.id
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
