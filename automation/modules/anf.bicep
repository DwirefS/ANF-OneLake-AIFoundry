// ============================================================================
// Azure NetApp Files Module
// Creates NetApp account, capacity pool, and NFS volume
// ============================================================================

@description('Azure region')
param location string

@description('Resource name prefix')
param prefix string

@description('ANF delegated subnet resource ID')
param anfSubnetId string

@description('Capacity pool size in TiB (minimum 2)')
@minValue(2)
param poolSizeTiB int = 2

@description('Volume quota in GiB')
param volumeQuotaGiB int = 100

// --- NetApp Account ---
resource netappAccount 'Microsoft.NetApp/netAppAccounts@2024-07-01' = {
  name: '${prefix}-netapp'
  location: location
  properties: {}
}

// --- Capacity Pool ---
resource capacityPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2024-07-01' = {
  parent: netappAccount
  name: '${prefix}-pool'
  location: location
  properties: {
    serviceLevel: 'Standard'
    size: poolSizeTiB * 1099511627776 // Convert TiB to bytes
  }
}

// --- NFS Volume ---
resource volume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2024-07-01' = {
  parent: capacityPool
  name: 'anf-finance-vol'
  location: location
  properties: {
    creationToken: 'anf-finance-vol'
    serviceLevel: 'Standard'
    subnetId: anfSubnetId
    usageThreshold: volumeQuotaGiB * 1073741824 // Convert GiB to bytes
    protocolTypes: [
      'NFSv3'
    ]
    exportPolicy: {
      rules: [
        {
          ruleIndex: 1
          allowedClients: '0.0.0.0/0'
          unixReadOnly: false
          unixReadWrite: true
          nfsv3: true
          nfsv41: false
        }
      ]
    }
  }
}

output netappAccountName string = netappAccount.name
output netappAccountId string = netappAccount.id
output capacityPoolName string = capacityPool.name
output volumeName string = volume.name
output volumeId string = volume.id
