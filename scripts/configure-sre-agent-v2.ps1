<#
.SYNOPSIS
    Compatibility entry point for the maintained SRE Agent configuration script.

.DESCRIPTION
    The primary configure-sre-agent.ps1 script uses the dataplane v2 API and is
    the single implementation. This wrapper preserves older invocations of the
    -v2 filename while forwarding all parameters and exit status.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$GitHubPat = '',

    [Parameter()]
    [string]$GitHubRepo = '',

    [Parameter()]
    [string]$GitHubBranch = 'main',

    [Parameter()]
    [switch]$SkipKnowledgeBase,

    [Parameter()]
    [switch]$SkipAgents,

    [Parameter()]
    [switch]$SkipConnectors,

    [Parameter()]
    [switch]$EnableMicrosoftLearnMcp,

    [Parameter()]
    [switch]$RemoveMicrosoftLearnMcp,

    [Parameter()]
    [switch]$SkipScheduledTasks
)

$ErrorActionPreference = 'Stop'
$primaryScript = Join-Path $PSScriptRoot 'configure-sre-agent.ps1'

if (-not (Test-Path $primaryScript)) {
    throw "Primary configuration script not found: $primaryScript"
}

Write-Warning 'configure-sre-agent-v2.ps1 is a compatibility alias; use configure-sre-agent.ps1.'
& $primaryScript @PSBoundParameters
exit $LASTEXITCODE