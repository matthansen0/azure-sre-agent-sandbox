// =============================================================================
// Application Insights Module
// =============================================================================
// Provides application-level telemetry for the demo application. SRE Agent
// can analyze Application Insights data for troubleshooting.
// =============================================================================

@description('Name of the Application Insights resource')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Log Analytics workspace ID to send telemetry to')
param workspaceId string

@description('Application type')
@allowed([
  'web'
  'other'
])
param applicationType string = 'web'

// =============================================================================
// RESOURCES
// =============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: applicationType
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: workspaceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    RetentionInDays: 90
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appId string = appInsights.properties.AppId
output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
