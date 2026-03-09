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

// ADDED: Lab Lesson 9 — Enterprise policy "Do Not Allow Public IPs" blocks PIP creation
@description('Set to false to skip Public IP (required when subscription has "Do Not Allow Public IPs" policy)')
param deployPublicIp bool = true

// --- Public IP (conditional — Lab Lesson 9) ---
// ORIGINAL (unconditional):
// resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
//   name: '${prefix}-gateway-pip'
//   ...
// }
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployPublicIp) {
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
// ORIGINAL (always attached PIP):
// resource nic ... {
//   properties: { ipConfigurations: [{ properties: { publicIPAddress: { id: publicIp.id } } }] }
// }
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
          // Lab Lesson 9: Only attach PIP when deployPublicIp is true
          publicIPAddress: deployPublicIp ? {
            id: publicIp.id
          } : null
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// FIX (Lesson 18): Windows computer name must be ≤15 characters (NETBIOS limit).
// Original: computerName: '${prefix}-gateway-vm' — exceeds 15 chars for most prefixes.
// Now derives a short name from prefix, truncated to 15 chars.
var computerName = take('${prefix}gw', 15)

// --- Windows VM ---
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${prefix}-gateway-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      // FIX (Lesson 18): Use derived short name instead of full resource name
      // Original: computerName: 'gw-vm'
      computerName: computerName
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
// ORIGINAL: output vmPublicIp string = publicIp.properties.ipAddress
output vmPublicIp string = deployPublicIp ? publicIp.properties.ipAddress : 'none-policy-blocked'
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
