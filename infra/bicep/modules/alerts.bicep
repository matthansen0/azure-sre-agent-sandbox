// =============================================================================
// Alerts Module
// =============================================================================
// Deploys baseline Azure Monitor scheduled query alerts for the SRE demo app.
// These alerts can be connected to action groups for paging/incident workflows.
// =============================================================================

@description('Prefix used for alert names')
param namePrefix string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Application namespace to monitor')
param appNamespace string = 'pets'

@description('Optional action group resource IDs for alert notifications')
param actionGroupIds array = []

var alertActions = {
  actionGroups: actionGroupIds
  customProperties: {
    source: 'azure-sre-agent-sandbox'
    workload: 'pet-store'
  }
}

resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2025-01-01-preview' = {
  name: '${namePrefix}-pod-restarts'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Pet Store - Pod restart spike'
    description: 'Triggers when a container restart count increases in the application namespace.'
    enabled: true
    severity: 2
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubePodInventory | where TimeGenerated > ago(5m) | where Namespace == "${appNamespace}" | summarize FirstRestartCount=min(ContainerRestartCount), LastRestartCount=max(ContainerRestartCount) by ContainerName | where LastRestartCount > FirstRestartCount'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: alertActions
  }
}

resource http5xxAlert 'Microsoft.Insights/scheduledQueryRules@2025-01-01-preview' = {
  name: '${namePrefix}-http-5xx'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Pet Store - HTTP 5xx spike'
    description: 'Triggers when a 5xx response appears in application container access logs.'
    enabled: true
    severity: 1
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'ContainerLogV2 | where TimeGenerated > ago(2m) | where PodNamespace == "${appNamespace}" | where LogMessage has "HTTP/" | extend StatusCode=toint(extract(" ([0-9]{3}) [0-9]+ ", 1, tostring(LogMessage))) | where StatusCode >= 500'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: alertActions
  }
}

resource podFailureAlert 'Microsoft.Insights/scheduledQueryRules@2025-01-01-preview' = {
  name: '${namePrefix}-pod-failures'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Pet Store - Failed or pending pods'
    description: 'Triggers quickly when failed or pending pods are detected in the application namespace.'
    enabled: true
    severity: 2
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubePodInventory | where TimeGenerated > ago(2m) | where Namespace == "${appNamespace}" | summarize arg_max(TimeGenerated, *) by ContainerName | where PodStatus in ("Failed", "Pending") or ContainerStatus =~ "waiting"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: alertActions
  }
}

resource crashLoopOomAlert 'Microsoft.Insights/scheduledQueryRules@2025-01-01-preview' = {
  name: '${namePrefix}-crashloop-oom'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Pet Store - CrashLoop/OOM detected'
    description: 'Triggers when container inventory reports CrashLoopBackOff, OOM, image-pull, or startup errors.'
    enabled: true
    severity: 1
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubePodInventory | where TimeGenerated > ago(2m) | where Namespace == "${appNamespace}" | summarize arg_max(TimeGenerated, *) by ContainerName | where ContainerStatusReason in~ ("CrashLoopBackOff", "OOMKilled", "Error", "ImagePullBackOff", "ErrImagePull")'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: alertActions
  }
}

output podRestartAlertId string = podRestartAlert.id
output http5xxAlertId string = http5xxAlert.id
output podFailureAlertId string = podFailureAlert.id
output crashLoopOomAlertId string = crashLoopOomAlert.id
