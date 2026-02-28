// ============================================================================
// Zero-Copy RAG Workshop — Main Bicep Template
// Deploys all Azure infrastructure for the ANF → OneLake → AI Search → AI Foundry pipeline
// ============================================================================

targetScope = 'resourceGroup'

// ---- Parameters ----

@description('Azure region for all resources. Must support GPT-4o (e.g., eastus2, swedencentral, westus3)')
param location string

@description('Resource name prefix (lowercase, no special chars). Used across all resource names.')
@minLength(3)
@maxLength(15)
param prefix string = 'ragworkshop'

@description('VM admin username for the gateway VM')
param vmAdminUsername string = 'azureuser'

@description('VM admin password for the gateway VM')
@secure()
param vmAdminPassword string

@description('Object ID of the user who will interact with AI Foundry (for RBAC)')
param userObjectId string

@description('ANF capacity pool size in TiB (minimum 2)')
@minValue(2)
param anfPoolSizeTiB int = 2

@description('ANF volume quota in GiB')
param anfVolumeQuotaGiB int = 100

// ---- Modules ----

module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    prefix: prefix
  }
}

module anf 'modules/anf.bicep' = {
  name: 'anf'
  params: {
    location: location
    prefix: prefix
    anfSubnetId: networking.outputs.anfSubnetId
    poolSizeTiB: anfPoolSizeTiB
    volumeQuotaGiB: anfVolumeQuotaGiB
  }
}

module gatewayVm 'modules/gateway-vm.bicep' = {
  name: 'gateway-vm'
  params: {
    location: location
    prefix: prefix
    subnetId: networking.outputs.defaultSubnetId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
  }
}

module aiSearch 'modules/ai-search.bicep' = {
  name: 'ai-search'
  params: {
    location: location
    prefix: prefix
  }
}

module aiServices 'modules/ai-services.bicep' = {
  name: 'ai-services'
  params: {
    location: location
    prefix: prefix
    userObjectId: userObjectId
  }
}

module aiFoundry 'modules/ai-foundry.bicep' = {
  name: 'ai-foundry'
  params: {
    location: location
    prefix: prefix
    aiServicesId: aiServices.outputs.aiServicesId
    aiServicesName: aiServices.outputs.aiServicesName
    searchServiceId: aiSearch.outputs.searchServiceId
    searchServiceName: aiSearch.outputs.searchServiceName
    searchServiceEndpoint: aiSearch.outputs.searchServiceEndpoint
  }
}

// ---- Outputs ----
// These outputs are consumed by the post-deployment PowerShell scripts

output resourceGroupName string = resourceGroup().name

// Networking
output vnetName string = networking.outputs.vnetName

// ANF
output netappAccountName string = anf.outputs.netappAccountName
output anfVolumeName string = anf.outputs.volumeName
output anfCapacityPoolName string = anf.outputs.capacityPoolName

// Gateway VM
output gatewayVmName string = gatewayVm.outputs.vmName
output gatewayVmPublicIp string = gatewayVm.outputs.vmPublicIp

// AI Search
output searchServiceName string = aiSearch.outputs.searchServiceName
output searchServiceEndpoint string = aiSearch.outputs.searchServiceEndpoint
output searchServicePrincipalId string = aiSearch.outputs.searchServicePrincipalId

// AI Services
output aiServicesName string = aiServices.outputs.aiServicesName
output aiServicesEndpoint string = aiServices.outputs.aiServicesEndpoint

// AI Foundry
output aiHubName string = aiFoundry.outputs.aiHubName
output aiProjectName string = aiFoundry.outputs.aiProjectName
