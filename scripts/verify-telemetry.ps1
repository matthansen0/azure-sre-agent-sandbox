<#
.SYNOPSIS
    Verifies Container Insights telemetry is being ingested into Log Analytics.

.PARAMETER ResourceGroupName
    Resource group containing the AKS cluster and Log Analytics workspace.

.PARAMETER Attempts
    Number of bounded ingestion checks before failing.

.PARAMETER DelaySeconds
    Delay between ingestion checks.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$Attempts = 3,

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$DelaySeconds = 30
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Name, [bool]$Passed, [string]$Message)
    $icon = if ($Passed) { '✅' } else { '❌' }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host "  $icon ${Name}: $Message" -ForegroundColor $color
}

$workspaceName = az resource list --resource-group $ResourceGroupName --resource-type Microsoft.OperationalInsights/workspaces --query '[0].name' --output tsv 2>$null
$workspaceId = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($workspaceName)) {
    az monitor log-analytics workspace show --resource-group $ResourceGroupName --workspace-name $workspaceName --query customerId --output tsv 2>$null
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceId)) {
    throw "Could not resolve the Log Analytics workspace for $ResourceGroupName."
}

$amaPods = @(kubectl get pods -n kube-system --no-headers 2>$null | Where-Object { $_ -match '^ama-logs-' -and $_ -match 'Running' -and $_ -match '3/3' })
Write-Result -Name 'Container Insights agent running' -Passed ($amaPods.Count -gt 0) -Message "$($amaPods.Count) ready ama-logs pod(s)"
if ($amaPods.Count -eq 0) { exit 1 }

$aksId = az resource list --resource-group $ResourceGroupName --resource-type Microsoft.ContainerService/managedClusters --query '[0].id' --output tsv 2>$null
$associationId = "$aksId/providers/Microsoft.Insights/dataCollectionRuleAssociations/ContainerInsightsExtension"
$association = az resource show --ids $associationId --query properties.dataCollectionRuleId --output tsv 2>$null
Write-Result -Name 'Container Insights DCR association' -Passed ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($association)) -Message $(if ($association) { $association } else { 'Association not found' })
if ([string]::IsNullOrWhiteSpace($association)) { exit 1 }

$queries = [ordered]@{
    ContainerLogV2 = 'ContainerLogV2 | where TimeGenerated > ago(15m) | summarize Rows=count(), Latest=max(TimeGenerated)'
    ContainerLog = 'ContainerLog | where TimeGenerated > ago(15m) | summarize Rows=count(), Latest=max(TimeGenerated)'
    KubePodInventory = 'KubePodInventory | where TimeGenerated > ago(15m) | summarize Rows=count(), Latest=max(TimeGenerated)'
}

for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $tableResults = @{}
    foreach ($table in $queries.Keys) {
        $raw = az monitor log-analytics query --workspace $workspaceId --analytics-query $queries[$table] --timespan PT15M --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            try {
                $row = @($raw | ConvertFrom-Json)[0]
                $tableResults[$table] = [int64]$row.Rows
            }
            catch {
                $tableResults[$table] = 0
            }
        }
        else {
            $tableResults[$table] = 0
        }
    }

    $logsIngested = $tableResults.ContainerLogV2 -gt 0 -or $tableResults.ContainerLog -gt 0
    $inventoryIngested = $tableResults.KubePodInventory -gt 0
    Write-Result -Name 'Container log telemetry' -Passed $logsIngested -Message "ContainerLogV2=$($tableResults.ContainerLogV2), ContainerLog=$($tableResults.ContainerLog)"
    Write-Result -Name 'Kubernetes inventory telemetry' -Passed $inventoryIngested -Message "KubePodInventory=$($tableResults.KubePodInventory)"

    if ($logsIngested -and $inventoryIngested) {
        Write-Host 'Telemetry ingestion verified.' -ForegroundColor Green
        exit 0
    }

    if ($attempt -lt $Attempts) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

Write-Host "Telemetry ingestion was not verified after $Attempts attempt(s)." -ForegroundColor Red
exit 1
