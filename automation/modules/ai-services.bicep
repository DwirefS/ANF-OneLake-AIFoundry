// ============================================================================
// Azure AI Services Module
// Creates AI Services account and deploys GPT-4o + embedding models
// ============================================================================

@description('Azure region')
param location string

@description('Resource name prefix')
param prefix string

@description('User object ID for Cognitive Services OpenAI User role')
param userObjectId string

// --- AI Services Account ---
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${prefix}-ai-services'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    customSubDomainName: '${prefix}-ai-services'
  }
}

// --- GPT-4o Deployment (must deploy sequentially) ---
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
  }
}

// --- Embedding Model Deployment (depends on GPT-4o for sequential deployment) ---
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: 'text-embedding-3-small'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
  }
  dependsOn: [
    gpt4oDeployment
  ]
}

// --- Cognitive Services OpenAI User role assignment ---
resource openaiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, userObjectId, 'CognitiveServicesOpenAIUser')
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: userObjectId
    principalType: 'User'
  }
}

output aiServicesName string = aiServices.name
output aiServicesId string = aiServices.id
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiServicesPrincipalId string = aiServices.identity.principalId
#disable-next-line outputs-should-not-contain-secrets
output aiServicesKey string = aiServices.listKeys().key1
