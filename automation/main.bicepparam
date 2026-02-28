using 'main.bicep'

// ============================================================================
// Sample Parameters — Update these values before deployment
// ============================================================================

// Azure region (must support GPT-4o)
// Options: eastus2, swedencentral, westus3
param location = 'eastus2'

// Resource name prefix (lowercase, 3-15 chars)
param prefix = 'ragworkshop'

// Gateway VM credentials
param vmAdminUsername = 'azureuser'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')

// Your Azure AD user Object ID (for AI Foundry RBAC)
// Find via: az ad signed-in-user show --query id -o tsv
param userObjectId = readEnvironmentVariable('USER_OBJECT_ID', '')

// ANF capacity pool size (TiB) — minimum 2
param anfPoolSizeTiB = 2

// ANF volume quota (GiB)
param anfVolumeQuotaGiB = 100
