// ============================================================================
// Networking Module
// Creates VNet, subnets (default + ANF delegated), and NSG for gateway VM
// ============================================================================

@description('Azure region for all resources')
param location string

@description('Resource name prefix')
param prefix string

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Default subnet address prefix (for VM, etc.)')
param defaultSubnetPrefix string = '10.0.0.0/24'

@description('ANF delegated subnet address prefix')
param anfSubnetPrefix string = '10.0.1.0/24'

// ADDED: Bastion subnet for RDP access when no public IPs (Lesson 9, 18)
@description('Deploy Azure Bastion for secure RDP access (required when no public IP on gateway VM)')
param deployBastion bool = true

@description('AzureBastionSubnet address prefix (minimum /26)')
param bastionSubnetPrefix string = '10.0.2.0/26'

// --- Network Security Group for Gateway VM ---
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-gateway-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- Virtual Network ---
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'anf-subnet'
        properties: {
          addressPrefix: anfSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.NetApp.volumes'
              properties: {
                serviceName: 'Microsoft.NetApp/volumes'
              }
            }
          ]
        }
      }
      // ADDED: AzureBastionSubnet — required for Azure Bastion when gateway VM has no public IP (Lesson 9)
      // Azure requires the subnet to be named exactly 'AzureBastionSubnet' with /26 or larger prefix.
    ]
  }
}

// ADDED: AzureBastionSubnet as a child resource — avoids redeployment issues with inline subnets (Lesson 10)
resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (deployBastion) {
  parent: vnet
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: bastionSubnetPrefix
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output defaultSubnetId string = vnet.properties.subnets[0].id
output anfSubnetId string = vnet.properties.subnets[1].id
// ADDED: Bastion subnet ID for Bastion deployment
output bastionSubnetId string = deployBastion ? bastionSubnet.id : ''
