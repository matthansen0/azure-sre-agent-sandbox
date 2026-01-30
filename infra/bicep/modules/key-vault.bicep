// =============================================================================
// Azure Key Vault Module
// =============================================================================
// Provides secure secrets management. SRE Agent can help diagnose
// Key Vault access issues and configuration problems.
// =============================================================================

@description('Name of the Key Vault')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Enable RBAC authorization (recommended)')
param enableRbacAuthorization bool = true

@description('SKU for Key Vault')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

// =============================================================================
// RESOURCES
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Note: enablePurgeProtection is omitted to default to false for dev/demo
    // Once enabled, purge protection cannot be disabled
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
