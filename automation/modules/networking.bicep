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
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output defaultSubnetId string = vnet.properties.subnets[0].id
output anfSubnetId string = vnet.properties.subnets[1].id
