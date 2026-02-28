// ============================================================================
// Azure AI Search Module
// Creates AI Search service with system-assigned managed identity
// ============================================================================

@description('Azure region')
param location string

@description('Resource name prefix')
param prefix string

@description('Search service SKU')
@allowed(['basic', 'standard', 'standard2'])
param skuName string = 'basic'

// --- Azure AI Search ---
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: '${prefix}-search'
  location: location
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    semanticSearch: 'free'
  }
}

output searchServiceName string = searchService.name
output searchServiceId string = searchService.id
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'
output searchServicePrincipalId string = searchService.identity.principalId
#disable-next-line outputs-should-not-contain-secrets
output searchServiceAdminKey string = searchService.listAdminKeys().primaryKey
