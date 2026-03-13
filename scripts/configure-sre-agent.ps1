<#
.SYNOPSIS
    Configures the SRE Agent with knowledge base, subagents, and response plans after infrastructure deployment.

.DESCRIPTION
    This script runs after deploy.ps1 to configure the SRE Agent with:
    - Knowledge base documents (runbooks, architecture docs, templates)
    - Subagent configurations (incident-handler, cluster-health-monitor, code-analyzer)
    - Incident response plans for alert-driven automation
    - (Optional) GitHub MCP connector for source code analysis

    It uses the SRE Agent REST API via Azure CLI to upload configurations.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.

.PARAMETER GitHubPat
    Optional GitHub Personal Access Token for enabling GitHub MCP integration.
    Requires 'repo' scope (Classic) or Contents:Read + Issues:Read/Write (Fine-grained).

.PARAMETER GitHubRepo
    Optional GitHub repository (owner/repo format) for code analysis subagent.

.PARAMETER SkipKnowledgeBase
    Skip knowledge base upload (useful for retry after partial failure).

.PARAMETER SkipSubagents
    Skip subagent creation.

.PARAMETER SkipResponsePlan
    Skip response plan creation.

.EXAMPLE
    .\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2"

.EXAMPLE
    .\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -GitHubPat $env:GITHUB_PAT -GitHubRepo "myorg/myrepo"
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
    [switch]$SkipKnowledgeBase,

    [Parameter()]
    [switch]$SkipSubagents,

    [Parameter()]
    [switch]$SkipResponsePlan
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Banner
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║              SRE Agent Configuration — Post-Provision Setup                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Configures knowledge base, subagents, and response plans                    ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# Discover SRE Agent
# ============================================================================
Write-Host "🔍 Discovering SRE Agent in resource group: $ResourceGroupName" -ForegroundColor Yellow

# Find the SRE Agent resource
$agentListRaw = az resource list `
    --resource-group $ResourceGroupName `
    --resource-type "Microsoft.App/agents" `
    --output json 2>$null | Out-String

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($agentListRaw)) {
    Write-Error "Could not list SRE Agent resources in $ResourceGroupName. Ensure the agent was deployed."
    exit 1
}

$agents = $agentListRaw | ConvertFrom-Json
if ($agents.Count -eq 0) {
    Write-Error "No SRE Agent found in $ResourceGroupName. Run deploy.ps1 first."
    exit 1
}

$agent = $agents[0]
$agentName = $agent.name
$agentId = $agent.id
$subscriptionId = (az account show --query id -o tsv 2>$null)

Write-Host "  ✅ Found agent: $agentName" -ForegroundColor Green

# Get the agent endpoint from resource properties
$agentDetailRaw = az resource show --ids $agentId --api-version 2025-05-01-preview --output json 2>$null | Out-String
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($agentDetailRaw)) {
    Write-Error "Could not retrieve agent details."
    exit 1
}

$agentDetail = $agentDetailRaw | ConvertFrom-Json
$agentEndpoint = $agentDetail.properties.agentEndpoint

if ([string]::IsNullOrWhiteSpace($agentEndpoint)) {
    Write-Error "Agent endpoint not found. The agent may still be provisioning."
    exit 1
}

Write-Host "  ✅ Agent endpoint: $agentEndpoint" -ForegroundColor Green

# ============================================================================
# Helper: Get Bearer Token
# ============================================================================
function Get-SreAgentToken {
    $token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        Write-Error "Failed to get access token for SRE Agent API. Ensure you are logged in."
        exit 1
    }
    return $token
}

# ============================================================================
# Step 1: Upload Knowledge Base
# ============================================================================
if (-not $SkipKnowledgeBase) {
    Write-Host "`n📚 Step 1: Uploading knowledge base documents..." -ForegroundColor Yellow

    $kbPath = Join-Path $PSScriptRoot "..\sre-config\knowledge-base"
    $kbFiles = Get-ChildItem -Path $kbPath -Filter "*.md" -ErrorAction SilentlyContinue

    if ($kbFiles.Count -eq 0) {
        Write-Host "  ⚠️  No knowledge base files found in $kbPath" -ForegroundColor Yellow
    }
    else {
        $token = Get-SreAgentToken
        $uploadUrl = "$agentEndpoint/api/v1/AgentMemory/upload"

        foreach ($file in $kbFiles) {
            Write-Host "  📄 Uploading $($file.Name)..." -ForegroundColor Gray

            try {
                # Use curl for multipart form upload
                $curlOutput = curl -s -w "`n%{http_code}" `
                    -X POST $uploadUrl `
                    -H "Authorization: Bearer $token" `
                    -F "triggerIndexing=true" `
                    -F "files=@$($file.FullName);type=text/plain" 2>&1

                $lines = $curlOutput -split "`n"
                $httpCode = $lines[-1].Trim()

                if ($httpCode -eq '200' -or $httpCode -eq '201' -or $httpCode -eq '204') {
                    Write-Host "    ✅ Uploaded $($file.Name)" -ForegroundColor Green
                }
                else {
                    Write-Host "    ⚠️  HTTP $httpCode for $($file.Name)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "    ⚠️  Failed to upload $($file.Name): $_" -ForegroundColor Yellow
            }
        }
    }
}
else {
    Write-Host "`n📚 Step 1: Skipping knowledge base upload (-SkipKnowledgeBase)" -ForegroundColor Gray
}

# ============================================================================
# Step 2: Create Subagents
# ============================================================================
if (-not $SkipSubagents) {
    Write-Host "`n🤖 Step 2: Creating subagents..." -ForegroundColor Yellow

    $hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat)
    $apiVersion = "2025-05-01-preview"

    # Check for Python (needed for YAML-to-JSON conversion)
    $python = $null
    if (Get-Command python3 -ErrorAction SilentlyContinue) { $python = 'python3' }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $python = 'python' }

    if (-not $python) {
        Write-Host "  ⚠️  Python not found. Skipping subagent creation (required for YAML parsing)." -ForegroundColor Yellow
    }
    else {
        $converterScript = Join-Path $PSScriptRoot "yaml-to-api-json.py"
        $agentsDir = Join-Path $PSScriptRoot "..\sre-config\agents"

        # Determine which agents to create
        $agentFiles = @()

        if ($hasGitHub) {
            Write-Host "  🔗 GitHub PAT detected — using full incident handler with GitHub tools" -ForegroundColor Gray
            $agentFiles += @{
                File = Join-Path $agentsDir "incident-handler-full.yaml"
                Name = "incident-handler"
            }
            $agentFiles += @{
                File = Join-Path $agentsDir "code-analyzer.yaml"
                Name = "code-analyzer"
            }
        }
        else {
            Write-Host "  📋 No GitHub PAT — using core incident handler (log analysis only)" -ForegroundColor Gray
            $agentFiles += @{
                File = Join-Path $agentsDir "incident-handler-core.yaml"
                Name = "incident-handler"
            }
        }

        $agentFiles += @{
            File = Join-Path $agentsDir "cluster-health-monitor.yaml"
            Name = "cluster-health-monitor"
        }

        foreach ($agentSpec in $agentFiles) {
            if (-not (Test-Path $agentSpec.File)) {
                Write-Host "  ⚠️  Agent file not found: $($agentSpec.File)" -ForegroundColor Yellow
                continue
            }

            Write-Host "  🤖 Creating subagent: $($agentSpec.Name)..." -ForegroundColor Gray
            $tmpJson = [System.IO.Path]::GetTempFileName()

            try {
                $env:GITHUB_REPO = $GitHubRepo
                & $python $converterScript $agentSpec.File $tmpJson $GitHubRepo 2>$null

                if (-not (Test-Path $tmpJson) -or (Get-Item $tmpJson).Length -eq 0) {
                    Write-Host "    ⚠️  YAML conversion failed for $($agentSpec.Name)" -ForegroundColor Yellow
                    continue
                }

                $jsonBody = Get-Content $tmpJson -Raw
                $specObj = $jsonBody | ConvertFrom-Json
                $specJson = $specObj.properties | ConvertTo-Json -Depth 10 -Compress
                $specBytes = [System.Text.Encoding]::UTF8.GetBytes($specJson)
                $specB64 = [Convert]::ToBase64String($specBytes)

                $putBody = @{
                    properties = @{
                        value = $specB64
                    }
                } | ConvertTo-Json -Compress

                $putUrl = "https://management.azure.com${agentId}/subagents/$($agentSpec.Name)?api-version=${apiVersion}"

                az rest --method PUT `
                    --url $putUrl `
                    --body $putBody `
                    --output none 2>$null

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    ✅ Created $($agentSpec.Name)" -ForegroundColor Green
                }
                else {
                    Write-Host "    ⚠️  Failed to create $($agentSpec.Name) (HTTP error)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "    ⚠️  Error creating $($agentSpec.Name): $_" -ForegroundColor Yellow
            }
            finally {
                if (Test-Path $tmpJson) { Remove-Item $tmpJson -ErrorAction SilentlyContinue }
            }
        }
    }
}
else {
    Write-Host "`n🤖 Step 2: Skipping subagent creation (-SkipSubagents)" -ForegroundColor Gray
}

# ============================================================================
# Step 3: Create Response Plan
# ============================================================================
if (-not $SkipResponsePlan) {
    Write-Host "`n📋 Step 3: Creating incident response plan..." -ForegroundColor Yellow

    $token = Get-SreAgentToken
    $responsePlanUrl = "$agentEndpoint/api/v1/ResponsePlans"

    $responsePlan = @{
        name        = "AKS Pod Failure Investigation"
        description = "Auto-trigger incident-handler when pod crash, OOM, or failure alerts fire"
        priority    = 3
        enabled     = $true
        conditions  = @(
            @{
                field    = "title"
                operator = "contains"
                value    = "pod"
            }
        )
        handlingAgent = "incident-handler"
        maxAttempts   = 3
    } | ConvertTo-Json -Depth 5

    try {
        $curlOutput = curl -s -w "`n%{http_code}" `
            -X POST $responsePlanUrl `
            -H "Authorization: Bearer $token" `
            -H "Content-Type: application/json" `
            -d $responsePlan 2>&1

        $lines = $curlOutput -split "`n"
        $httpCode = $lines[-1].Trim()

        if ($httpCode -eq '200' -or $httpCode -eq '201' -or $httpCode -eq '204') {
            Write-Host "  ✅ Response plan created" -ForegroundColor Green
        }
        elseif ($httpCode -eq '405' -or $httpCode -eq '409') {
            Write-Host "  ℹ️  Response plan may already exist (HTTP $httpCode)" -ForegroundColor Gray
        }
        else {
            Write-Host "  ⚠️  Response plan creation returned HTTP $httpCode" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ⚠️  Failed to create response plan: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n📋 Step 3: Skipping response plan (-SkipResponsePlan)" -ForegroundColor Gray
}

# ============================================================================
# Step 4: GitHub MCP Integration (Optional)
# ============================================================================
$hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat)
if ($hasGitHub) {
    Write-Host "`n🔗 Step 4: Configuring GitHub MCP connector..." -ForegroundColor Yellow

    $connectorTemplate = Join-Path $PSScriptRoot "..\sre-config\connectors\github-mcp.yaml"

    if (-not (Test-Path $connectorTemplate)) {
        Write-Host "  ⚠️  Connector template not found: $connectorTemplate" -ForegroundColor Yellow
    }
    else {
        $token = Get-SreAgentToken

        # Build connector JSON from the YAML template
        $connectorYaml = Get-Content $connectorTemplate -Raw
        $connectorYaml = $connectorYaml -replace 'PLACEHOLDER_GITHUB_PAT', $GitHubPat

        $connectorBody = @{
            name     = "github-mcp"
            type     = "Mcp"
            endpoint = "https://api.githubcopilot.com/mcp/"
            auth     = @{
                type  = "BearerToken"
                token = $GitHubPat
            }
        } | ConvertTo-Json -Depth 5

        $apiVersion = "2025-05-01-preview"
        $connectorUrl = "https://management.azure.com${agentId}/mcpServers/github-mcp?api-version=${apiVersion}"

        try {
            $connectorPutBody = @{
                properties = @{
                    serverUri      = "https://api.githubcopilot.com/mcp/"
                    authenticationType = "PersonalAccessToken"
                    credentials    = @{
                        token = $GitHubPat
                    }
                }
            } | ConvertTo-Json -Depth 5

            az rest --method PUT `
                --url $connectorUrl `
                --body $connectorPutBody `
                --output none 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ GitHub MCP connector configured" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠️  MCP connector creation returned an error. You can configure it manually in the portal." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ⚠️  Failed to configure GitHub MCP: $_" -ForegroundColor Yellow
            Write-Host "       You can add this manually in the SRE Agent portal under Connectors." -ForegroundColor Gray
        }
    }
}
else {
    Write-Host "`n🔗 Step 4: GitHub integration — ⏭️  Skipped (no PAT provided)" -ForegroundColor Gray
    Write-Host "   To add GitHub integration later, re-run with:" -ForegroundColor Gray
    Write-Host "   .\configure-sre-agent.ps1 -ResourceGroupName $ResourceGroupName -GitHubPat `$env:GITHUB_PAT -GitHubRepo 'owner/repo'" -ForegroundColor Gray
}

# ============================================================================
# Summary
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                  SRE Agent Configuration Complete! 🎉                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Knowledge Base:  Runbooks for pod failures, networking, dependencies,       ║
║                   resource exhaustion, app architecture, incident template    ║
║  Subagents:       incident-handler, cluster-health-monitor                   ║
$(if ($hasGitHub) { "║                   code-analyzer (GitHub enabled)                             ║`n" } else { "" })║  Response Plan:   Auto-triggered on pod failure alerts                       ║
$(if ($hasGitHub) { "║  GitHub MCP:      Configured                                                 ║`n" } else { "║  GitHub MCP:      Not configured (no PAT provided)                          ║`n" })║                                                                              ║
║  Portal: https://aka.ms/sreagent/portal                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open https://sre.azure.com and find your agent" -ForegroundColor White
Write-Host "  2. Verify knowledge base, subagents, and response plan in the Builder" -ForegroundColor White
Write-Host "  3. Apply a breakable scenario: break-oom, break-crash, etc." -ForegroundColor White
Write-Host "  4. Watch the agent investigate and remediate!" -ForegroundColor White
Write-Host ""
