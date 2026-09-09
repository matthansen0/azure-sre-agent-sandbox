<#
.SYNOPSIS
    Verifies the expected SRE Agent configuration state.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.

.EXAMPLE
    .\verify-sre-agent-configuration.ps1 -ResourceGroupName "rg-srelab-eastus2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [switch]$RequireAzureMonitorAutomation,

    [Parameter()]
    [switch]$RequireMicrosoftLearnMcp
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Component, [Parameter(Mandatory)][string]$Reason)
    [void]$failures.Add("${Component}: $Reason")
    Write-Host "  ❌ ${Component}: $Reason" -ForegroundColor Red
}

function Invoke-DataplaneApi {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Token
    )

    $output = & curl -s -w "`n%{http_code}" -H "Authorization: Bearer $Token" $Url 2>&1
    $lines = ($output -join "`n") -split "`n"
    $statusCode = 0
    [void][int]::TryParse($lines[-1].Trim(), [ref]$statusCode)
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' }
    return @{ StatusCode = $statusCode; Body = $body }
}

Write-Host "Verifying SRE Agent configuration in $ResourceGroupName..." -ForegroundColor Cyan

$agentListRaw = az resource list --resource-group $ResourceGroupName --resource-type "Microsoft.App/agents" --output json 2>$null | Out-String
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($agentListRaw)) {
    throw "Could not list SRE Agent resources in $ResourceGroupName."
}

$agents = @($agentListRaw | ConvertFrom-Json)
if ($agents.Count -ne 1) {
    throw "Expected exactly one SRE Agent in $ResourceGroupName; found $($agents.Count)."
}

$agentId = $agents[0].id
$agentDetailRaw = az resource show --ids $agentId --api-version 2025-05-01-preview --output json 2>$null | Out-String
$agentDetail = $agentDetailRaw | ConvertFrom-Json
$agentEndpoint = $agentDetail.properties.agentEndpoint
if ([string]::IsNullOrWhiteSpace($agentEndpoint)) {
    throw 'SRE Agent endpoint is missing.'
}

$token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Could not acquire an SRE Agent dataplane access token.'
}

if ($RequireAzureMonitorAutomation) {
    $monitorResources = @(az resource list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json)
    $requiredAlertNames = @(
        'alert-srelab-pod-restarts',
        'alert-srelab-http-5xx',
        'alert-srelab-pod-failures',
        'alert-srelab-crashloop-oom'
    )
    foreach ($alertName in $requiredAlertNames) {
        if (@($monitorResources | Where-Object { $_.type -eq 'Microsoft.Insights/scheduledQueryRules' -and $_.name -eq $alertName }).Count -eq 1) {
            Write-Host "  ✅ Azure Monitor alert/$alertName" -ForegroundColor Green
        }
        else {
            Add-Failure -Component "Azure Monitor alert/$alertName" -Reason 'Expected alert resource was not found'
        }
    }

    if (@($monitorResources | Where-Object { $_.type -eq 'Microsoft.Insights/actionGroups' -and $_.name -eq 'ag-srelab' }).Count -eq 1) {
        Write-Host '  ✅ Azure Monitor action group/ag-srelab' -ForegroundColor Green
    }
    else {
        Add-Failure -Component 'Azure Monitor action group/ag-srelab' -Reason 'Expected action group was not found'
    }
}

if ($RequireMicrosoftLearnMcp) {
    $learnResponse = Invoke-DataplaneApi -Url "$agentEndpoint/api/v2/extendedAgent/connectors/microsoft-learn" -Token $token
    if ($learnResponse.StatusCode -eq 200) {
        Write-Host '  ✅ Microsoft Learn MCP connector' -ForegroundColor Green
    }
    else {
        Add-Failure -Component 'Microsoft Learn MCP connector' -Reason "HTTP $($learnResponse.StatusCode)"
    }
}
else {
    Write-Host '  ℹ️  Microsoft Learn MCP connector skipped (opt-in).' -ForegroundColor Gray
}

if ($RequireAzureMonitorAutomation) {
    foreach ($taskName in @('daily-rbac-cost-network-audit', 'hourly-automation-health')) {
        $taskResponse = Invoke-DataplaneApi -Url "$agentEndpoint/api/v2/extendedAgent/scheduledTasks/$taskName" -Token $token
        if ($taskResponse.StatusCode -eq 200) {
            Write-Host "  ✅ Azure Monitor automation task/$taskName" -ForegroundColor Green
        }
        else {
            Add-Failure -Component "Azure Monitor automation task/$taskName" -Reason "HTTP $($taskResponse.StatusCode)"
        }
    }
}
else {
    Write-Host '  ℹ️  Azure Monitor automation tasks skipped (opt-in).' -ForegroundColor Gray
}

$checks = @(
    @{ Name = 'Knowledge base'; Path = '/api/v1/AgentMemory/files'; Test = { param($data) @($data.files | Where-Object { $_.isIndexed }).Count -gt 0 } },
    @{ Name = 'Custom agents'; Path = '/api/v2/extendedAgent/agents'; Test = {
            param($data)
            $actualNames = @($data.value | ForEach-Object { $_.name })
            $expectedNames = @('incident-handler', 'cluster-health-monitor')
            return @($expectedNames | Where-Object { $_ -in $actualNames }).Count -eq $expectedNames.Count
        } },
    @{ Name = 'Azure Monitor connector'; Path = '/api/v2/extendedAgent/connectors/azure-monitor'; Test = { param($data) $null -ne $data } },
    @{ Name = 'Outlook connector'; Path = '/api/v2/extendedAgent/connectors/outlook'; Test = { param($data) $null -ne $data } },
    @{ Name = 'Daily health task'; Path = '/api/v2/extendedAgent/scheduledTasks/daily-health-check'; Test = { param($data) $null -ne $data } }
)

foreach ($check in $checks) {
    $response = Invoke-DataplaneApi -Url "$agentEndpoint$($check.Path)" -Token $token
    if ($response.StatusCode -ne 200) {
        Add-Failure -Component $check.Name -Reason "HTTP $($response.StatusCode)"
        continue
    }

    try {
        $data = $response.Body | ConvertFrom-Json
        if (& $check.Test $data) {
            Write-Host "  ✅ $($check.Name)" -ForegroundColor Green
        }
        else {
            Add-Failure -Component $check.Name -Reason 'Expected state was not found'
        }
    }
    catch {
        Add-Failure -Component $check.Name -Reason 'Response was not valid JSON'
    }
}

$incidentFilters = Invoke-DataplaneApi -Url "$agentEndpoint/api/v2/extendedAgent/incidentFilters" -Token $token
if ($incidentFilters.StatusCode -eq 200) {
    Write-Host "  ℹ️  Incident filters readable; creation remains portal-only." -ForegroundColor Gray
}
else {
    Add-Failure -Component 'Incident-filter read-only check' -Reason "HTTP $($incidentFilters.StatusCode)"
}

if ($failures.Count -gt 0) {
    Write-Host "`nSRE Agent verification failed with $($failures.Count) failure(s)." -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "`nSRE Agent expected state verified." -ForegroundColor Green
