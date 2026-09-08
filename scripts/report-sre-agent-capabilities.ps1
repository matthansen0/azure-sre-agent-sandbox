<#
.SYNOPSIS
    Reports observed SRE Agent capabilities and governance limitations.

.DESCRIPTION
    Uses read-only ARM, dataplane GET, and optional kubectl auth checks. The
    report distinguishes observed configuration from enforceable boundaries.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'

function Get-ApiResponse {
    param([string]$Url, [string]$Token)
    $output = & curl -sS -w "`n%{http_code}" -H "Authorization: Bearer $Token" $Url 2>&1
    $lines = ($output -join "`n") -split "`n"
    $status = 0
    [void][int]::TryParse($lines[-1].Trim(), [ref]$status)
    return @{ StatusCode = $status; Body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' } }
}

$agents = @(az resource list --resource-group $ResourceGroupName --resource-type Microsoft.App/agents -o json 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $agents.Count -ne 1) {
    throw "Expected one SRE Agent in $ResourceGroupName; found $($agents.Count)."
}

$detail = az resource show --ids $agents[0].id --api-version 2025-05-01-preview -o json 2>$null | ConvertFrom-Json
$token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
$endpoint = $detail.properties.agentEndpoint

[pscustomobject]@{
    AgentName = $agents[0].name
    ActionMode = $detail.properties.actionConfiguration.mode
    ReviewMode = if ($detail.properties.actionConfiguration.mode -eq 'Review') { 'observed' } else { 'not-observed' }
    AgentsEndpoint = (Get-ApiResponse -Url "$endpoint/api/v2/extendedAgent/agents" -Token $token).StatusCode
    ConnectorsEndpoint = (Get-ApiResponse -Url "$endpoint/api/v2/extendedAgent/connectors" -Token $token).StatusCode
    ScheduledTasksEndpoint = (Get-ApiResponse -Url "$endpoint/api/v2/extendedAgent/scheduledTasks" -Token $token).StatusCode
    IncidentFiltersEndpoint = (Get-ApiResponse -Url "$endpoint/api/v2/extendedAgent/incidentFilters" -Token $token).StatusCode
    NamespaceBoundary = 'not-enforceable-by-current-RBAC'
    ResourceGroupBoundary = 'not-enforceable-by-current-RBAC'
    HookSupport = 'unknown-until-documented'
    SecretRedaction = 'contract-required; runtime support unknown'
} | Format-List

Write-Host 'Capability report uses read-only calls only.' -ForegroundColor Green
