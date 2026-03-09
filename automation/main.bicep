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

// ADDED: Lab Lesson 4 — Skip RBAC when deployer lacks User Access Administrator role
@description('Set to false to skip RBAC role assignment (requires User Access Administrator)')
param deployRbac bool = true

// ADDED: Lab Lesson 9 — Enterprise policy "Do Not Allow Public IPs" blocks gateway VM PIP
@description('Set to false to skip Public IP on gateway VM (required when subscription has no-public-IP policy)')
param deployPublicIp bool = true

// ADDED: Deploy Azure Bastion for secure RDP (needed when no public IP — Lesson 9, 18)
@description('Deploy Azure Bastion for RDP access to gateway VM. Required when deployPublicIp=false.')
param deployBastion bool = true

// ---- Modules ----

module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    prefix: prefix
    deployBastion: deployBastion  // ADDED: pass Bastion toggle to networking module
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
    deployPublicIp: deployPublicIp  // Lab Lesson 9: pass through PIP toggle
  }
}

// ADDED: Azure Bastion for secure RDP access to gateway VM (Lesson 9 — no public IPs)
// Bastion requires: AzureBastionSubnet (/26+), Standard SKU Public IP, and Basic+ SKU Bastion.
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) {
  name: '${prefix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = if (deployBastion) {
  name: '${prefix}-bastion'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: networking.outputs.bastionSubnetId
          }
        }
      }
    ]
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
    deployRbac: deployRbac  // Lab Lesson 4: pass through RBAC toggle
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
output gatewayVmPrivateIp string = gatewayVm.outputs.vmPrivateIp

// Bastion (ADDED: for secure RDP access)
output bastionName string = deployBastion ? bastion.name : 'not-deployed'

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
