<#
.SYNOPSIS
    Reports or removes the opt-in Azure Monitor automation profile.

.PARAMETER ResourceGroupName
    Resource group containing the lab.

.PARAMETER Cleanup
    Remove the profile's action group and scheduled-query alerts.

.PARAMETER ConfirmCleanup
    Required with -Cleanup to perform deletion.

.PARAMETER Pause
    Disable the profile's scheduled audit tasks.

.PARAMETER Resume
    Enable the profile's scheduled audit tasks.

.PARAMETER RunNow
    Request an immediate run of one scheduled audit task when supported.

.PARAMETER TaskName
    Scheduled task used with -RunNow.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [switch]$Cleanup,

    [Parameter()]
    [switch]$ConfirmCleanup,

    [Parameter()]
    [switch]$Pause,

    [Parameter()]
    [switch]$Resume,

    [Parameter()]
    [switch]$RunNow,

    [Parameter()]
    [ValidateSet('daily-rbac-cost-network-audit', 'hourly-automation-health')]
    [string]$TaskName = 'hourly-automation-health'
)

$ErrorActionPreference = 'Stop'
$profileResources = @(
    @{ Type = 'Microsoft.Insights/scheduledQueryRules'; Name = 'alert-srelab-pod-restarts' },
    @{ Type = 'Microsoft.Insights/scheduledQueryRules'; Name = 'alert-srelab-http-5xx' },
    @{ Type = 'Microsoft.Insights/scheduledQueryRules'; Name = 'alert-srelab-pod-failures' },
    @{ Type = 'Microsoft.Insights/scheduledQueryRules'; Name = 'alert-srelab-crashloop-oom' },
    @{ Type = 'Microsoft.Insights/actionGroups'; Name = 'ag-srelab' }
)

if ($Cleanup -and -not $ConfirmCleanup) {
    throw 'Cleanup requires both -Cleanup and -ConfirmCleanup.'
}

if (@($Pause, $Resume, $RunNow, $Cleanup | Where-Object { $_ }).Count -gt 1) {
    throw 'Choose only one of -Pause, -Resume, -RunNow, or -Cleanup.'
}

if ($Pause -or $Resume -or $RunNow) {
    $agent = az resource list --resource-group $ResourceGroupName --resource-type Microsoft.App/agents --query '[0]' -o json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $agent) { throw "No SRE Agent found in $ResourceGroupName." }
    $detail = az resource show --ids $agent.id --api-version 2025-05-01-preview -o json 2>$null | ConvertFrom-Json
    $endpoint = $detail.properties.agentEndpoint
    $token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($endpoint) -or [string]::IsNullOrWhiteSpace($token)) { throw 'Could not resolve SRE Agent endpoint or token.' }

    function Invoke-TaskApi {
        param([ValidateSet('GET', 'POST', 'PUT')][string]$Method, [string]$Path, [string]$Body)
        $args = @('-sS', '-w', "`n%{http_code}", '-X', $Method, "$endpoint$Path", '-H', "Authorization: Bearer $token", '-H', 'Content-Type: application/json')
        if ($Body) { $args += @('--data-raw', $Body) }
        $output = & curl @args 2>&1
        $lines = ($output -join "`n") -split "`n"
        $code = 0
        [void][int]::TryParse($lines[-1].Trim(), [ref]$code)
        return @{ StatusCode = $code; Body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' } }
    }

    if ($RunNow) {
        $response = Invoke-TaskApi -Method POST -Path "/api/v2/extendedAgent/scheduledTasks/$TaskName/run"
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            Write-Host "  ✅ Requested immediate run: $TaskName" -ForegroundColor Green
            exit 0
        }
        Write-Host "  ℹ️  Run-now is not supported by the current API (HTTP $($response.StatusCode)). Use the portal or wait for the cron schedule." -ForegroundColor Yellow
        exit 2
    }

    foreach ($auditTask in @('daily-rbac-cost-network-audit', 'hourly-automation-health')) {
        $current = Invoke-TaskApi -Method GET -Path "/api/v2/extendedAgent/scheduledTasks/$auditTask"
        if ($current.StatusCode -ne 200) { throw "Could not read $auditTask (HTTP $($current.StatusCode))." }
        $task = $current.Body | ConvertFrom-Json
        $task.properties.enabled = $Resume
        $body = $task | ConvertTo-Json -Depth 20 -Compress
        $updated = Invoke-TaskApi -Method PUT -Path "/api/v2/extendedAgent/scheduledTasks/$auditTask" -Body $body
        if ($updated.StatusCode -lt 200 -or $updated.StatusCode -ge 300) { throw "Could not update $auditTask (HTTP $($updated.StatusCode))." }
        Write-Host "  ✅ $auditTask enabled=$Resume" -ForegroundColor Green
    }
    exit 0
}

foreach ($resource in $profileResources) {
    $id = az resource show --resource-group $ResourceGroupName --resource-type $resource.Type --name $resource.Name --query id -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) {
        Write-Host "  - $($resource.Type)/$($resource.Name): not configured" -ForegroundColor Gray
        continue
    }

    if ($Cleanup) {
        if ($PSCmdlet.ShouldProcess($id, 'Delete Azure Monitor profile resource')) {
            az resource delete --ids $id --only-show-errors
            if ($LASTEXITCODE -ne 0) { throw "Failed to delete $id" }
            Write-Host "  ✅ Removed $($resource.Type)/$($resource.Name)" -ForegroundColor Green
        }
    }
    else {
        $state = az resource show --ids $id --query properties.enabled -o tsv 2>$null
        Write-Host "  ✅ $($resource.Type)/$($resource.Name): enabled=$state" -ForegroundColor Green
    }
}

if (-not $Cleanup) {
    Write-Host 'Profile is read-only inspected. Use -Cleanup -ConfirmCleanup to remove it.' -ForegroundColor Cyan
}
