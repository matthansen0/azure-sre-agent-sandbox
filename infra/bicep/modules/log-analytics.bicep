// =============================================================================
// Log Analytics Workspace Module
// =============================================================================
// Provides centralized logging for AKS, application telemetry, and SRE Agent
// diagnostics. This is a prerequisite for Azure SRE Agent.
// =============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Data retention period in days (30-730)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU for the workspace')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
  'PerNode'
])
param sku string = 'PerGB2018'

// =============================================================================
// RESOURCES
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // Unlimited
    }
  }
}

// Container Insights solution for AKS monitoring
resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'ContainerInsights(${name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/ContainerInsights'
    promotionCode: ''
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId
