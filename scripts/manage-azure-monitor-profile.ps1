<#
.SYNOPSIS
    Reports or removes the opt-in Azure Monitor automation profile.

.PARAMETER ResourceGroupName
    Resource group containing the lab.

.PARAMETER Cleanup
    Remove the profile's action group and scheduled-query alerts.

.PARAMETER ConfirmCleanup
    Required with -Cleanup to perform deletion.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [switch]$Cleanup,

    [Parameter()]
    [switch]$ConfirmCleanup
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
