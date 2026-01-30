// =============================================================================
// Azure Container Registry Module
// =============================================================================
// Hosts container images for the demo application services.
// =============================================================================

@description('Name of the container registry (must be globally unique)')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('SKU for the container registry')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Enable admin user for local development')
param adminUserEnabled bool = true

// =============================================================================
// RESOURCES
// =============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: sku == 'Premium' ? 'enabled' : 'disabled'
      }
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output acrId string = acr.id
output acrName string = acr.name
output loginServer string = acr.properties.loginServer
