// =============================================================================
// Azure SRE Agent Demo Lab - Main Bicep Template
// =============================================================================
// This template deploys an AKS cluster with a multi-pod sample application,
// along with supporting infrastructure for demonstrating Azure SRE Agent
// capabilities for diagnostics and troubleshooting.
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Name of the workload (used for naming resources)')
@minLength(3)
@maxLength(10)
param workloadName string = 'srelab'

@description('Azure region for deployment. Must be a region supporting SRE Agent (East US 2, Sweden Central, Australia East)')
@allowed([
  'eastus2'
  'swedencentral'
  'australiaeast'
])
param location string = 'eastus2'

@description('Deploy full observability stack (Managed Grafana, Prometheus)')
param deployObservability bool = true

@description('AKS Kubernetes version')
param kubernetesVersion string = '1.32'

@description('AKS system node pool VM size')
@allowed([
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2as_v5'
  'Standard_D4as_v5'
])
param systemNodeVmSize string = 'Standard_D2s_v5'

@description('AKS user node pool VM size for workloads')
@allowed([
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2as_v5'
  'Standard_D4as_v5'
])
param userNodeVmSize string = 'Standard_D2s_v5'

@description('System node pool node count')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('User node pool node count')
@minValue(1)
@maxValue(10)
param userNodeCount int = 3

@description('Tags to apply to all resources')
param tags object = {
  workload: 'sre-agent-demo'
  environment: 'sandbox'
  managedBy: 'bicep'
  purpose: 'demonstration'
}

// =============================================================================
// VARIABLES
// =============================================================================

var resourceGroupName = 'rg-${workloadName}-${location}'
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupName)

// Naming convention for resources
var names = {
  aks: 'aks-${workloadName}'
  acr: 'acr${workloadName}${take(uniqueSuffix, 6)}'
  logAnalytics: 'log-${workloadName}'
  appInsights: 'appi-${workloadName}'
  grafana: 'grafana-${workloadName}'
  prometheus: 'prometheus-${workloadName}'
  keyVault: 'kv-${workloadName}-${take(uniqueSuffix, 6)}'
  managedIdentity: 'id-${workloadName}'
  vnet: 'vnet-${workloadName}'
}

// =============================================================================
// RESOURCE GROUP
// =============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// =============================================================================
// MODULES
// =============================================================================

// Log Analytics Workspace (required for AKS monitoring and SRE Agent)
module logAnalytics 'modules/log-analytics.bicep' = {
  scope: resourceGroup
  name: 'deploy-log-analytics'
  params: {
    name: names.logAnalytics
    location: location
    tags: tags
    retentionInDays: 30
  }
}

// Application Insights (for application-level telemetry)
module appInsights 'modules/app-insights.bicep' = {
  scope: resourceGroup
  name: 'deploy-app-insights'
  params: {
    name: names.appInsights
    location: location
    tags: tags
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

// Virtual Network for AKS
module network 'modules/network.bicep' = {
  scope: resourceGroup
  name: 'deploy-network'
  params: {
    vnetName: names.vnet
    location: location
    tags: tags
    addressPrefix: '10.0.0.0/16'
    aksSubnetPrefix: '10.0.0.0/22'
    servicesSubnetPrefix: '10.0.4.0/24'
  }
}

// Azure Container Registry
module containerRegistry 'modules/container-registry.bicep' = {
  scope: resourceGroup
  name: 'deploy-acr'
  params: {
    name: names.acr
    location: location
    tags: tags
    sku: 'Basic'
  }
}

// Azure Kubernetes Service
module aks 'modules/aks.bicep' = {
  scope: resourceGroup
  name: 'deploy-aks'
  params: {
    name: names.aks
    location: location
    tags: tags
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: systemNodeVmSize
    userNodeVmSize: userNodeVmSize
    systemNodeCount: systemNodeCount
    userNodeCount: userNodeCount
    vnetSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    acrId: containerRegistry.outputs.acrId
  }
}

// Key Vault for secrets management
module keyVault 'modules/key-vault.bicep' = {
  scope: resourceGroup
  name: 'deploy-keyvault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    enableRbacAuthorization: true
  }
}

// Observability Stack - Managed Grafana and Prometheus (optional)
module observability 'modules/observability.bicep' = if (deployObservability) {
  scope: resourceGroup
  name: 'deploy-observability'
  params: {
    grafanaName: names.grafana
    prometheusName: names.prometheus
    location: location
    tags: tags
    aksClusterId: aks.outputs.aksId
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output resourceGroupName string = resourceGroup.name
output aksClusterName string = aks.outputs.aksName
output aksClusterFqdn string = aks.outputs.aksFqdn
output acrLoginServer string = containerRegistry.outputs.loginServer
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appInsightsConnectionString string = appInsights.outputs.connectionString
output keyVaultUri string = keyVault.outputs.vaultUri
output grafanaDashboardUrl string = deployObservability ? observability!.outputs.grafanaEndpoint : ''
