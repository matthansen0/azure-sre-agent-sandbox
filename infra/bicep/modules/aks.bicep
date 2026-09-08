// =============================================================================
// Azure Kubernetes Service Module
// =============================================================================
// Deploys an AKS cluster configured for SRE Agent monitoring and diagnosis.
// 
// IMPORTANT FOR SRE AGENT:
// - Cluster must NOT have fully restricted inbound network access
// - Container Insights and OIDC Issuer must be enabled
// - Workload Identity should be enabled for secure service auth
// =============================================================================

@description('Name of the AKS cluster')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Kubernetes version (empty = AKS default)')
param kubernetesVersion string

@description('VM size for system node pool')
param systemNodeVmSize string

@description('VM size for user node pool')
param userNodeVmSize string

@description('System node pool node count')
param systemNodeCount int

@description('User node pool node count')
param userNodeCount int

@description('Subnet ID for AKS nodes')
param vnetSubnetId string

@description('Log Analytics workspace ID for Container Insights')
param logAnalyticsWorkspaceId string

@description('Azure Container Registry ID for image pull permissions')
param acrId string

// =============================================================================
// RESOURCES
// =============================================================================

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Standard' // Standard tier for SLA - recommended for demos
  }
  properties: {
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    dnsPrefix: name

    // Enable features needed for SRE Agent
    oidcIssuerProfile: {
      enabled: true // Required for Workload Identity
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true // Enable Workload Identity
      }
    }

    // Network configuration - PUBLIC networking to allow SRE Agent access
    // SRE Agent cannot access Kubernetes objects if cluster has restricted inbound access
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      loadBalancerSku: 'standard'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
    }

    // API server access - Enable public access for SRE Agent
    apiServerAccessProfile: {
      enablePrivateCluster: false // IMPORTANT: Must be false for SRE Agent
    }

    // System node pool
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        vnetSubnetID: vnetSubnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
        }
      }
      {
        name: 'workload'
        count: userNodeCount
        vmSize: userNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'User'
        vnetSubnetID: vnetSubnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 10
        nodeLabels: {
          'nodepool-type': 'user'
        }
      }
    ]

    // Add-ons and monitoring
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
          enableContainerLogV2: 'true'
        }
      }
      azurepolicy: {
        enabled: true
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // Azure Monitor metrics
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: '*'
          metricAnnotationsAllowList: '*'
        }
      }
    }

    // Auto-upgrade channel
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

// Grant AKS access to ACR for image pulls
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acrId, 'acrpull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    ) // AcrPull
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalyticsContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspaceId, aks.id, 'LogAnalyticsContributorKubelet')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
    )
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource containerInsightsDcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'MSCI-${replace(location, ' ', '')}-${aks.name}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerLogV2'
            'Microsoft-KubeEvents'
            'Microsoft-KubePodInventory'
            'Microsoft-ContainerInventory'
            'Microsoft-ContainerNodeInventory'
            'Microsoft-KubeNodeInventory'
            'Microsoft-KubeServices'
            'Microsoft-Perf'
            'Microsoft-InsightsMetrics'
          ]
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Off'
              namespaces: []
              enableContainerLogV2: true
            }
          }
          extensionName: 'ContainerInsights'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerLogV2'
          'Microsoft-KubeEvents'
          'Microsoft-KubePodInventory'
          'Microsoft-ContainerInventory'
          'Microsoft-ContainerNodeInventory'
          'Microsoft-KubeNodeInventory'
          'Microsoft-KubeServices'
          'Microsoft-Perf'
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}

// The monitoring addon consumes this DCR to collect container logs and inventory.
resource containerInsightsDcra 'Microsoft.ContainerService/managedClusters/providers/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${aks.name}/microsoft.insights/ContainerInsightsExtension'
  properties: {
    description: 'Container Insights data collection association'
    dataCollectionRuleId: containerInsightsDcr.id
  }
  dependsOn: [
    containerInsightsDcr
  ]
}

// =============================================================================
// OUTPUTS
// =============================================================================

output aksId string = aks.id
output aksName string = aks.name
output aksFqdn string = aks.properties.fqdn
output aksNodeResourceGroup string = aks.properties.nodeResourceGroup
output aksIdentityPrincipalId string = aks.identity.principalId
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
