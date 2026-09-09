<#
.SYNOPSIS
    Runs one breakable scenario and produces a verified evidence report.

.DESCRIPTION
    Captures a healthy baseline, applies one scenario, verifies the induced
    fault, restores the baseline, validates final health, and writes redacted
    JSON and Markdown reports. Alert, agent, and approval stages are reported
    as not-observed unless an external workflow supplies evidence.

.PARAMETER ResourceGroupName
    Resource group containing the AKS cluster.

.PARAMETER Scenario
    Scenario manifest name without the .yaml extension.

.PARAMETER OutputDirectory
    Directory for evidence reports.

.PARAMETER FaultTimeoutSeconds
    Maximum time to wait for the scenario fault to become observable.

.EXAMPLE
    .\run-demo-scenario.ps1 -ResourceGroupName rg-srelab-eastus2 -Scenario oom-killed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateSet('oom-killed', 'crash-loop', 'image-pull-backoff', 'high-cpu', 'pending-pods', 'probe-failure', 'network-block', 'missing-config', 'mongodb-down', 'service-mismatch')]
    [string]$Scenario,

    [Parameter()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\evidence'),

    [Parameter()]
    [ValidateRange(30, 1800)]
    [int]$FaultTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$scenarioPath = Join-Path $PSScriptRoot "..\k8s\scenarios\$Scenario.yaml"
$baselinePath = Join-Path $PSScriptRoot '..\k8s\base\application.yaml'
$validatePath = Join-Path $PSScriptRoot 'validate-deployment.ps1'
$events = [System.Collections.Generic.List[object]]::new()
$restoreRequired = $false

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $entry = [pscustomobject]@{
        stage = $Name
        status = $Status
        detail = $Detail
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    [void]$events.Add($entry)
    Write-Host "[$Status] $Name$(if ($Detail) { ": $Detail" })" -ForegroundColor $(if ($Status -eq 'passed') { 'Green' } elseif ($Status -eq 'failed') { 'Red' } else { 'Yellow' })
}

function Invoke-KubectlJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $raw = & kubectl @Arguments -o json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl $($Arguments -join ' ') failed: $($raw.Trim())"
    }
    return $raw | ConvertFrom-Json
}

function Get-Evidence {
    $pods = Invoke-KubectlJson -Arguments @('get', 'pods', '-n', 'pets')
    $eventsData = Invoke-KubectlJson -Arguments @('get', 'events', '-n', 'pets', '--sort-by=.lastTimestamp')
    $deployments = Invoke-KubectlJson -Arguments @('get', 'deployments', '-n', 'pets')
    return [pscustomobject]@{
        pods = @($pods.items | ForEach-Object {
            [pscustomobject]@{
                name = $_.metadata.name
                phase = $_.status.phase
                restarts = @($_.status.containerStatuses | ForEach-Object { $_.restartCount } | Measure-Object -Sum).Sum
                ready = @($_.status.containerStatuses | Where-Object ready).Count
            }
        })
        deployments = @($deployments.items | ForEach-Object {
            [pscustomobject]@{ name = $_.metadata.name; ready = $_.status.readyReplicas; desired = $_.spec.replicas }
        })
        events = @($eventsData.items | Select-Object -Last 50 | ForEach-Object {
            [pscustomobject]@{ reason = $_.reason; type = $_.type; message = $_.message; involvedObject = $_.involvedObject.name }
        })
    }
}

function Test-FaultObserved {
    param([Parameter(Mandatory)]$Evidence)
    switch ($Scenario) {
        'oom-killed' { return @($Evidence.events | Where-Object { $_.reason -match 'OOM|BackOff' }).Count -gt 0 -or @($Evidence.pods | Where-Object { $_.restarts -gt 0 }).Count -gt 0 }
        'crash-loop' { return @($Evidence.pods | Where-Object { $_.phase -ne 'Running' -or $_.restarts -gt 0 }).Count -gt 0 }
        'image-pull-backoff' { return @($Evidence.events | Where-Object { $_.reason -match 'Failed|BackOff|ErrImagePull' }).Count -gt 0 }
        default { return @($Evidence.pods | Where-Object { $_.phase -ne 'Running' -or $_.ready -lt 1 }).Count -gt 0 -or @($Evidence.events | Where-Object { $_.type -eq 'Warning' }).Count -gt 0 }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$reportBase = Join-Path $OutputDirectory "scenario-$Scenario-$(Get-Date -Format yyyyMMdd-HHmmss)"
$report = [ordered]@{
    scenario = $Scenario
    resourceGroup = $ResourceGroupName
    startedAt = $started.ToUniversalTime().ToString('o')
    stages = $events
    baseline = $null
    fault = $null
    restored = $null
}

try {
    if (-not (Test-Path $scenarioPath) -or -not (Test-Path $baselinePath)) { throw 'Scenario or baseline manifest is missing.' }
    Add-Stage -Name 'baseline' -Status 'running'
    $report.baseline = Get-Evidence
    Add-Stage -Name 'baseline' -Status 'passed'

    Add-Stage -Name 'fault-injection' -Status 'running'
    $restoreRequired = $true
    kubectl apply -f $scenarioPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Scenario manifest could not be applied.' }
    Add-Stage -Name 'fault-injection' -Status 'passed'

    Add-Stage -Name 'fault-observation' -Status 'running'
    $deadline = (Get-Date).AddSeconds($FaultTimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        $report.fault = Get-Evidence
        $observed = Test-FaultObserved -Evidence $report.fault
    } while (-not $observed -and (Get-Date) -lt $deadline)
    if (-not $observed) { throw "Scenario fault was not observed within $FaultTimeoutSeconds seconds." }
    Add-Stage -Name 'fault-observation' -Status 'passed'
    Add-Stage -Name 'alert' -Status 'not-observed' -Detail 'External Azure Monitor/SRE Agent trigger evidence was not supplied.'
    Add-Stage -Name 'investigation' -Status 'not-observed' -Detail 'Run the SRE Agent prompt separately and attach evidence if available.'
    Add-Stage -Name 'approval' -Status 'not-observed' -Detail 'No remediation approval event was supplied.'
}
catch {
    Add-Stage -Name 'workflow' -Status 'failed' -Detail $_.Exception.Message
}
finally {
    if ($restoreRequired) {
        $activeCleanupStage = $null
        try {
            $activeCleanupStage = 'restore'
            Add-Stage -Name 'restore' -Status 'running'
            kubectl apply -f $baselinePath | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Baseline manifest could not be reapplied.' }
            Add-Stage -Name 'restore' -Status 'passed'

            $activeCleanupStage = 'recovery'
            Add-Stage -Name 'recovery' -Status 'running'
            $deploymentNamesRaw = & kubectl get deployment -n pets -o jsonpath='{.items[*].metadata.name}' 2>&1
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($deploymentNamesRaw)) {
                throw 'Could not enumerate deployments while waiting for recovery.'
            }
            foreach ($deploymentName in ($deploymentNamesRaw -split '\s+' | Where-Object { $_ })) {
                kubectl rollout status "deployment/$deploymentName" -n pets --timeout=300s | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Deployment $deploymentName did not recover before timeout." }
            }
            $validationOutput = & pwsh -NoLogo -NoProfile -File $validatePath -ResourceGroupName $ResourceGroupName 2>&1 | Out-String
            $validationExitCode = $LASTEXITCODE
            $report.restored = Get-Evidence
            if ($validationExitCode -ne 0) { throw "Final validation failed with exit code $validationExitCode." }
            Add-Stage -Name 'recovery' -Status 'passed'
            $activeCleanupStage = $null
        }
        catch {
            if ($activeCleanupStage) {
                Add-Stage -Name $activeCleanupStage -Status 'failed' -Detail $_.Exception.Message
            }
            Add-Stage -Name 'cleanup' -Status 'failed' -Detail $_.Exception.Message
        }
    }
}

$report.stages = @($events)
$report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
$report.status = if (@($events | Where-Object status -eq 'failed').Count -eq 0 -and @($events | Where-Object { $_.stage -eq 'recovery' -and $_.status -eq 'passed' }).Count -eq 1) { 'passed' } else { 'failed' }
$report | ConvertTo-Json -Depth 12 | Set-Content -Path "$reportBase.json" -Encoding utf8

$markdown = @(
    ('# Scenario Report: ' + $Scenario),
    '',
    ('- Status: **' + $report.status + '**'),
    ('- Resource group: `' + $ResourceGroupName + '`'),
    ('- Started: ' + $report.startedAt),
    ('- Finished: ' + $report.finishedAt),
    "",
    '## Lifecycle',
    '',
    '| Stage | Status | Detail |',
    '| --- | --- | --- |'
)
$markdown += @($events | ForEach-Object { '| ' + $_.stage + ' | ' + $_.status + ' | ' + $_.detail + ' |' })
$markdown += @('', 'Alert, investigation, and approval are marked not-observed unless external evidence is supplied.', '')
$markdown | Set-Content -Path "$reportBase.md" -Encoding utf8

Write-Host "Evidence written to $reportBase.json and $reportBase.md" -ForegroundColor Cyan
if ($report.status -ne 'passed') { exit 1 }
