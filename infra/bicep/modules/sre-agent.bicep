// =============================================================================
// Azure SRE Agent Module
// =============================================================================
// Deploys an Azure SRE Agent with managed identity and role assignments.
// Based on: https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment
// Resource type: Microsoft.App/agents@2025-05-01-preview
// =============================================================================

@description('Name of the SRE Agent')
param agentName string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('The access level for the SRE Agent (High = Reader + Contributor + Log Analytics Reader, Low = Reader + Log Analytics Reader)')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Application Insights App ID')
param appInsightsAppId string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Unique suffix for resource naming')
param uniqueSuffix string

@description('Resource IDs to add to SRE Agent knowledge graph (e.g. AKS cluster)')
param managedResourceIds array = []

// =============================================================================
// VARIABLES
// =============================================================================

var identityName = '${agentName}-${uniqueSuffix}'

// Role definition IDs by access level
var roleDefinitions = {
  Low: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  ]
  High: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
  ]
}

// =============================================================================
// RESOURCES
// =============================================================================

// User-Assigned Managed Identity for SRE Agent
#disable-next-line BCP073
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
  tags: tags
  properties: {
    isolationScope: 'Regional'
  }
}

// Role assignments for the managed identity on this resource group
resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (roleId, index) in roleDefinitions[accessLevel]: {
    name: guid(resourceGroup().id, managedIdentity.id, roleId)
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: managedIdentity.properties.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

// SRE Agent
#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: managedIdentity.id
      managedResources: managedResourceIds
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: managedIdentity.id
      mode: 'Review'
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
  }
  dependsOn: [
    roleAssignments
  ]
}

// Assign SRE Agent Administrator role to the deployer
// This allows the deploying user to manage the agent in the portal
resource sreAgentAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, deployer().objectId, 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  scope: sreAgent
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55') // SRE Agent Administrator
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output agentName string = sreAgent.name
output agentId string = sreAgent.id
output agentPortalUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/${replace(sreAgent.id, '/', '%2F')}'
output managedIdentityId string = managedIdentity.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
