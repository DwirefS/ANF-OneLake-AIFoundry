// ============================================================================
// Gateway VM Module
// Creates a Windows Server VM for the On-Premises Data Gateway
// ============================================================================

@description('Azure region')
param location string

@description('Resource name prefix')
param prefix string

@description('Subnet ID for the VM NIC')
param subnetId string

@description('VM admin username')
param adminUsername string

@description('VM admin password')
@secure()
param adminPassword string

@description('VM size')
param vmSize string = 'Standard_D2s_v3'

// --- Public IP ---
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-gateway-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- NIC ---
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-gateway-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// --- Windows VM ---
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${prefix}-gateway-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'gw-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output vmName string = vm.name
output vmId string = vm.id
output vmPublicIp string = publicIp.properties.ipAddress
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
