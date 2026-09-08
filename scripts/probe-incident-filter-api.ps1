<#+
.SYNOPSIS
    Probes SRE Agent incident-filter create/read/delete support.

.DESCRIPTION
    Runs an isolated, opt-in compatibility probe against the incidentFilters
    dataplane endpoint. The probe never runs as part of normal deployment.
    Supply a candidate JSON payload only after reviewing it for secrets.

.PARAMETER ResourceGroupName
    Resource group containing the SRE Agent.

.PARAMETER FilterName
    Temporary filter name used by the probe.

.PARAMETER PayloadPath
    JSON file containing the candidate incident-filter payload.

.EXAMPLE
    .\probe-incident-filter-api.ps1 -ResourceGroupName rg-srelab-eastus2 `
        -PayloadPath .\incident-filter-payload.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')]
    [string]$FilterName = "compatibility-probe-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))",

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'
$apiPath = "/api/v2/extendedAgent/incidentFilters/$FilterName"

function Get-AgentEndpoint {
    $raw = az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.App/agents' --output json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "Could not list SRE Agent resources in $ResourceGroupName."
    }

    $agents = @($raw | ConvertFrom-Json)
    if ($agents.Count -ne 1) {
        throw "Expected exactly one SRE Agent in $ResourceGroupName; found $($agents.Count)."
    }

    $detail = az resource show --ids $agents[0].id --api-version 2025-05-01-preview --output json 2>$null | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($detail.properties.agentEndpoint)) {
        throw 'SRE Agent endpoint is missing.'
    }

    return $detail.properties.agentEndpoint
}

function Invoke-ProbeRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Token,
        [string]$Body
    )

    $arguments = @('-sS', '-w', "`n%{http_code}", '-X', $Method, $Url,
        '-H', "Authorization: Bearer $Token", '-H', 'Accept: application/json')
    if ($null -ne $Body) {
        $arguments += @('-H', 'Content-Type: application/json', '--data-raw', $Body)
    }

    $output = & curl @arguments 2>&1
    $lines = ($output -join "`n") -split "`n"
    $statusCode = 0
    [void][int]::TryParse($lines[-1].Trim(), [ref]$statusCode)
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' }

    return [pscustomobject]@{
        Method     = $Method
        StatusCode = $statusCode
        Body       = $body
    }
}

function Write-ProbeResult {
    param([Parameter(Mandatory)]$Response)
    $body = $Response.Body.Trim()
    if ($body.Length -gt 500) {
        $body = $body.Substring(0, 500) + '...'
    }
    Write-Host "  $($Response.Method) -> HTTP $($Response.StatusCode)" -ForegroundColor $(if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 300) { 'Green' } else { 'Yellow' })
    if ($body) {
        Write-Host "    $body" -ForegroundColor Gray
    }
}

$payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json | ConvertTo-Json -Depth 30 -Compress
$endpoint = Get-AgentEndpoint
$token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Could not acquire an SRE Agent dataplane access token.'
}

$url = "$endpoint$apiPath"
Write-Host "Probing incident-filter API at $apiPath" -ForegroundColor Cyan
Write-Host "Temporary filter: $FilterName" -ForegroundColor Gray

$getBefore = Invoke-ProbeRequest -Method GET -Url $url -Token $token
Write-ProbeResult -Response $getBefore

$put = Invoke-ProbeRequest -Method PUT -Url $url -Token $token -Body $payload
Write-ProbeResult -Response $put

if ($put.StatusCode -ge 200 -and $put.StatusCode -lt 300) {
    $getAfter = Invoke-ProbeRequest -Method GET -Url $url -Token $token
    Write-ProbeResult -Response $getAfter

    $delete = Invoke-ProbeRequest -Method DELETE -Url $url -Token $token
    Write-ProbeResult -Response $delete

    if ($delete.StatusCode -lt 200 -or $delete.StatusCode -ge 300) {
        throw "Incident filter was created but cleanup failed with HTTP $($delete.StatusCode). Remove '$FilterName' manually before retrying."
    }

    Write-Host 'Incident-filter create/read/delete lifecycle succeeded.' -ForegroundColor Green
    exit 0
}

Write-Host 'Incident-filter creation did not succeed; no delete was attempted.' -ForegroundColor Yellow
exit 2
