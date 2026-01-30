// =============================================================================
// Observability Stack Module
// =============================================================================
// Deploys Azure Managed Grafana and Azure Monitor managed service for
// Prometheus. These integrate with SRE Agent for comprehensive monitoring.
// =============================================================================

@description('Name of the Managed Grafana workspace')
param grafanaName string

@description('Name of the Azure Monitor workspace for Prometheus')
param prometheusName string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('AKS cluster ID to monitor')
param aksClusterId string

// =============================================================================
// RESOURCES
// =============================================================================

// Azure Monitor Workspace for Prometheus
resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: prometheusName
  location: location
  tags: tags
}

// Data collection endpoint
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: '${prometheusName}-dce'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Data collection rule for Prometheus metrics
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${prometheusName}-dcr'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccount'
          accountResourceId: azureMonitorWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount'
        ]
      }
    ]
  }
}

// Azure Managed Grafana
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    apiKey: 'Disabled'
    deterministicOutboundIP: 'Disabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: azureMonitorWorkspace.id
        }
      ]
    }
  }
}

// Note: Data Collection Rule Association for AKS is configured via the AKS module's
// azureMonitorProfile setting, not as a separate resource. The aksClusterId parameter
// is used for reference in Grafana integrations.
#disable-next-line no-unused-params
var _aksRef = aksClusterId // Reference to prevent unused parameter warning

// Grant Grafana Monitoring Reader on the subscription
// Note: This may need to be done via script if Bicep RBAC fails
resource grafanaMonitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, subscription().subscriptionId, 'MonitoringReader')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
    ) // Monitoring Reader
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output grafanaId string = grafana.id
output grafanaName string = grafana.name
output grafanaEndpoint string = grafana.properties.endpoint
output azureMonitorWorkspaceId string = azureMonitorWorkspace.id
output dataCollectionRuleId string = dataCollectionRule.id
