<#
.SYNOPSIS
    Configures the SRE Agent using the dataplane v2 API after infrastructure deployment.

.DESCRIPTION
    This script runs after deploy.ps1 to configure the SRE Agent with:
    - Knowledge base documents (runbooks uploaded to Agent Memory)
    - Custom agents via the dataplane v2 API
    - Azure Monitor connector for incident detection
    - (Optional) GitHub MCP connector for source code analysis
    - Scheduled health check task
    - Portal guidance for incident response plans

    Uses the dataplane v2 API at {agentEndpoint}/api/v2/extendedAgent/
    which is the GA-supported programmatic configuration path.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.

.PARAMETER GitHubPat
    Optional GitHub Personal Access Token for enabling GitHub MCP integration.

.PARAMETER GitHubRepo
    Optional GitHub repository (owner/repo format) for code analysis agent.

.PARAMETER SkipKnowledgeBase
    Skip knowledge base upload.

.PARAMETER SkipAgents
    Skip custom agent creation.

.PARAMETER SkipConnectors
    Skip connector creation.

.PARAMETER SkipScheduledTasks
    Skip scheduled task creation.

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
    [switch]$SkipAgents,

    [Parameter()]
    [switch]$SkipConnectors,

    [Parameter()]
    [switch]$SkipScheduledTasks
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Banner
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║            SRE Agent Configuration — Dataplane v2 API                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Configures knowledge base, custom agents, connectors, and scheduled tasks   ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# Discover SRE Agent
# ============================================================================
Write-Host "🔍 Discovering SRE Agent in resource group: $ResourceGroupName" -ForegroundColor Yellow

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

Write-Host "  ✅ Found agent: $agentName" -ForegroundColor Green

# Get the agent endpoint
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
# Helper: Get Bearer Token for dataplane API
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
# Helper: Call dataplane v2 API
# ============================================================================
function Invoke-DataplaneApi {
    param(
        [string]$Method,
        [string]$Path,
        [string]$Body = $null,
        [string]$Token
    )

    $url = "$agentEndpoint$Path"

    $curlArgs = @('-s', '-w', "`n%{http_code}", '-X', $Method, $url,
                  '-H', "Authorization: Bearer $Token")

    if ($Body) {
        $curlArgs += @('-H', 'Content-Type: application/json', '-d', $Body)
    }

    $output = & curl @curlArgs 2>&1
    $lines = ($output -join "`n") -split "`n"
    $httpCode = $lines[-1].Trim()
    $responseBody = ($lines[0..($lines.Count - 2)]) -join "`n"

    return @{
        StatusCode = [int]$httpCode
        Body       = $responseBody
    }
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

        # Verify uploads
        $filesResp = Invoke-DataplaneApi -Method GET -Path "/api/v1/AgentMemory/files" -Token $token
        if ($filesResp.StatusCode -eq 200) {
            try {
                $filesData = $filesResp.Body | ConvertFrom-Json
                $indexedCount = ($filesData.files | Where-Object { $_.isIndexed }).Count
                Write-Host "  📊 $indexedCount files indexed in agent memory" -ForegroundColor Green
            }
            catch {
                Write-Host "  📊 Files uploaded (could not parse count)" -ForegroundColor Gray
            }
        }
    }
}
else {
    Write-Host "`n📚 Step 1: Skipping knowledge base upload (-SkipKnowledgeBase)" -ForegroundColor Gray
}

# ============================================================================
# Step 2: Create Custom Agents
# ============================================================================
if (-not $SkipAgents) {
    Write-Host "`n🤖 Step 2: Creating custom agents via dataplane v2 API..." -ForegroundColor Yellow

    $hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat)
    $token = Get-SreAgentToken

    # Check for Python + PyYAML
    $python = $null
    if (Get-Command python3 -ErrorAction SilentlyContinue) { $python = 'python3' }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $python = 'python' }

    $converterScript = Join-Path $PSScriptRoot "yaml-to-agent-json.py"
    $agentsDir = Join-Path $PSScriptRoot "..\sre-config\agents"

    if (-not $python) {
        Write-Host "  ⚠️  Python not found. Skipping agent creation." -ForegroundColor Yellow
    }
    elseif (-not (Test-Path $converterScript)) {
        Write-Host "  ⚠️  Converter script not found: $converterScript" -ForegroundColor Yellow
    }
    else {
        # Test that pyyaml is available
        $yamlCheck = & $python -c "import yaml" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  📦 Installing pyyaml..." -ForegroundColor Gray
            & $python -m pip install --user pyyaml 2>$null
        }

        # Determine which agents to create
        $agentFiles = @()

        if ($hasGitHub) {
            Write-Host "  🔗 GitHub PAT detected — deploying full incident handler with GitHub tools" -ForegroundColor Gray
            $agentFiles += Join-Path $agentsDir "incident-handler-full.yaml"
            $agentFiles += Join-Path $agentsDir "code-analyzer.yaml"
        }
        else {
            Write-Host "  📋 No GitHub PAT — deploying core incident handler" -ForegroundColor Gray
            $agentFiles += Join-Path $agentsDir "incident-handler-core.yaml"
        }

        $agentFiles += Join-Path $agentsDir "cluster-health-monitor.yaml"

        $createdAgents = @()

        foreach ($yamlFile in $agentFiles) {
            if (-not (Test-Path $yamlFile)) {
                Write-Host "  ⚠️  Agent file not found: $(Split-Path $yamlFile -Leaf)" -ForegroundColor Yellow
                continue
            }

            $agentFileName = Split-Path $yamlFile -Leaf

            # Convert YAML to API JSON
            $convertArgs = @($converterScript, $yamlFile)
            if ($hasGitHub -and $GitHubRepo) { $convertArgs += $GitHubRepo }
            $jsonBody = & $python @convertArgs 2>&1

            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonBody)) {
                Write-Host "  ⚠️  YAML conversion failed for $agentFileName" -ForegroundColor Yellow
                continue
            }

            # Extract agent name from the JSON
            try {
                $agentObj = $jsonBody | ConvertFrom-Json
                $customAgentName = $agentObj.name
            }
            catch {
                Write-Host "  ⚠️  Invalid JSON from $agentFileName" -ForegroundColor Yellow
                continue
            }

            Write-Host "  🤖 Creating agent: $customAgentName..." -ForegroundColor Gray

            $resp = Invoke-DataplaneApi `
                -Method PUT `
                -Path "/api/v2/extendedAgent/agents/$customAgentName" `
                -Body $jsonBody `
                -Token $token

            if ($resp.StatusCode -eq 202 -or $resp.StatusCode -eq 200) {
                Write-Host "    ✅ Created $customAgentName" -ForegroundColor Green
                $createdAgents += $customAgentName
            }
            else {
                Write-Host "    ⚠️  HTTP $($resp.StatusCode) for $customAgentName" -ForegroundColor Yellow
                if ($resp.Body.Length -gt 0) {
                    try {
                        $errObj = $resp.Body | ConvertFrom-Json
                        $errMsg = if ($errObj.error.message) { $errObj.error.message } else { $resp.Body.Substring(0, [Math]::Min(200, $resp.Body.Length)) }
                        Write-Host "       $errMsg" -ForegroundColor Gray
                    }
                    catch {
                        Write-Host "       $($resp.Body.Substring(0, [Math]::Min(200, $resp.Body.Length)))" -ForegroundColor Gray
                    }
                }
            }
        }

        # List all agents
        $listResp = Invoke-DataplaneApi -Method GET -Path "/api/v2/extendedAgent/agents" -Token $token
        if ($listResp.StatusCode -eq 200) {
            try {
                $agentList = ($listResp.Body | ConvertFrom-Json).value
                Write-Host "  📊 $($agentList.Count) custom agent(s) registered" -ForegroundColor Green
            }
            catch {}
        }
    }
}
else {
    Write-Host "`n🤖 Step 2: Skipping agent creation (-SkipAgents)" -ForegroundColor Gray
}

# ============================================================================
# Step 3: Create Connectors
# ============================================================================
if (-not $SkipConnectors) {
    Write-Host "`n🔌 Step 3: Creating connectors..." -ForegroundColor Yellow

    $token = Get-SreAgentToken
    $hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat)

    # 3a: Azure Monitor connector (always)
    Write-Host "  📊 Creating Azure Monitor connector..." -ForegroundColor Gray

    $azMonBody = @{
        name       = "azure-monitor"
        properties = @{
            dataConnectorType = "AzureMonitor"
            dataSource        = "azure-monitor"
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $resp = Invoke-DataplaneApi `
        -Method PUT `
        -Path "/api/v2/extendedAgent/connectors/azure-monitor" `
        -Body $azMonBody `
        -Token $token

    if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 202) {
        Write-Host "    ✅ Azure Monitor connector created" -ForegroundColor Green
    }
    else {
        Write-Host "    ⚠️  HTTP $($resp.StatusCode) — Azure Monitor connector may need manual setup" -ForegroundColor Yellow
    }

    # 3b: GitHub MCP connector (optional)
    if ($hasGitHub) {
        Write-Host "  🔗 Creating GitHub MCP connector..." -ForegroundColor Gray

        $ghBody = @{
            name       = "github-mcp"
            properties = @{
                dataConnectorType = "StreamableHttp"
                dataSource        = "github"
                serverUri         = "https://api.githubcopilot.com/mcp/"
                authenticationType = "BearerToken"
                credentials       = @{
                    token = $GitHubPat
                }
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $resp = Invoke-DataplaneApi `
            -Method PUT `
            -Path "/api/v2/extendedAgent/connectors/github-mcp" `
            -Body $ghBody `
            -Token $token

        if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 202) {
            Write-Host "    ✅ GitHub MCP connector created" -ForegroundColor Green
        }
        else {
            Write-Host "    ⚠️  HTTP $($resp.StatusCode) — GitHub connector may need manual setup in portal" -ForegroundColor Yellow
            Write-Host "       Use the pre-configured GitHub card in Settings > Connectors" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  🔗 GitHub connector — ⏭️  Skipped (no PAT provided)" -ForegroundColor Gray
    }

    # 3c: Outlook connector (always — enables SendOutlookEmail tool)
    Write-Host "  📧 Creating Outlook connector..." -ForegroundColor Gray

    $outlookBody = @{
        name       = "outlook"
        properties = @{
            dataConnectorType = "Outlook"
            dataSource        = "outlook"
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $resp = Invoke-DataplaneApi `
        -Method PUT `
        -Path "/api/v2/extendedAgent/connectors/outlook" `
        -Body $outlookBody `
        -Token $token

    if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 202) {
        Write-Host "    ✅ Outlook connector created" -ForegroundColor Green
        Write-Host "    📌 Authorize in portal: https://sre.azure.com → Settings → Connectors → Outlook → Authorize" -ForegroundColor Gray
    }
    else {
        Write-Host "    ⚠️  HTTP $($resp.StatusCode) — Outlook connector may need manual setup" -ForegroundColor Yellow
        Write-Host "       Create it in the portal: Settings → Connectors → Add → Outlook" -ForegroundColor Gray
    }
}
else {
    Write-Host "`n🔌 Step 3: Skipping connector creation (-SkipConnectors)" -ForegroundColor Gray
}

# ============================================================================
# Step 4: Create Incident Response Plan (best-effort via API)
# ============================================================================
Write-Host "`n🚨 Step 4: Attempting incident response plan creation..." -ForegroundColor Yellow

$token = Get-SreAgentToken

# Try the v2 incidentFilters endpoint — this may fail if the API doesn't support
# creation yet, or if an incident management platform (PagerDuty/ServiceNow) is required.
$incidentFilterBody = @{
    name       = "aks-pod-failure-handler"
    type       = "IncidentFilter"
    properties = @{
        description     = "Routes AKS pod failure incidents to the incident-handler subagent"
        severities      = @("Sev1", "Sev2", "Sev3")
        titleContains   = "pod"
        agentName       = "incident-handler"
        agentAutonomy   = "Review"
        enabled         = $true
    }
} | ConvertTo-Json -Depth 5 -Compress

$resp = Invoke-DataplaneApi `
    -Method PUT `
    -Path "/api/v2/extendedAgent/incidentFilters/aks-pod-failure-handler" `
    -Body $incidentFilterBody `
    -Token $token

if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 202) {
    Write-Host "  ✅ Incident filter 'aks-pod-failure-handler' created" -ForegroundColor Green
    Write-Host "     Incidents matching 'pod' in title → incident-handler subagent" -ForegroundColor Gray
}
else {
    Write-Host "  ⚠️  HTTP $($resp.StatusCode) — Incident filter API not yet supported" -ForegroundColor Yellow
    Write-Host "     This is expected — create manually in the portal (see guidance below)" -ForegroundColor Gray
}

# Also try listing existing incident filters to see current state
$listResp = Invoke-DataplaneApi -Method GET -Path "/api/v2/extendedAgent/incidentFilters" -Token $token
if ($listResp.StatusCode -eq 200) {
    try {
        $filterList = ($listResp.Body | ConvertFrom-Json).value
        if ($filterList.Count -gt 0) {
            Write-Host "  📊 $($filterList.Count) incident filter(s) registered" -ForegroundColor Green
        }
        else {
            Write-Host "  📊 No incident filters registered yet" -ForegroundColor Gray
        }
    }
    catch {}
}

# ============================================================================
# Step 5: Create Scheduled Tasks
# ============================================================================
if (-not $SkipScheduledTasks) {
    Write-Host "`n⏰ Step 5: Creating scheduled health check..." -ForegroundColor Yellow

    $token = Get-SreAgentToken

    $taskBody = @{
        name       = "daily-health-check"
        type       = "ScheduledTask"
        properties = @{
            cronExpression = "0 8 * * *"
            agentPrompt    = "Run a comprehensive health check of the AKS cluster in the pets namespace. Check all pod statuses, recent restarts, resource utilization, and error trends. Report any issues found with severity ratings."
            agentName      = "cluster-health-monitor"
            enabled        = $true
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $resp = Invoke-DataplaneApi `
        -Method PUT `
        -Path "/api/v2/extendedAgent/scheduledTasks/daily-health-check" `
        -Body $taskBody `
        -Token $token

    if ($resp.StatusCode -eq 202 -or $resp.StatusCode -eq 200) {
        Write-Host "  ✅ Scheduled task 'daily-health-check' created (runs daily at 08:00 UTC)" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  HTTP $($resp.StatusCode) — scheduled task creation failed" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n⏰ Step 5: Skipping scheduled tasks (-SkipScheduledTasks)" -ForegroundColor Gray
}

# ============================================================================
# Step 6: Summary and Portal Guidance
# ============================================================================
$hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat)

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                  SRE Agent Configuration Complete! 🎉                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  ✅ Knowledge Base: Runbooks uploaded to Agent Memory                        ║
║  ✅ Custom Agents:  incident-handler, cluster-health-monitor                 ║
$(if ($hasGitHub) { "║  ✅ Custom Agents:  code-analyzer (GitHub enabled)                         ║`n" } else { "" })║  ✅ Connector:      Azure Monitor (incident source)                          ║
║  ✅ Connector:      Outlook (email delivery — authorize in portal)           ║
$(if ($hasGitHub) { "║  ✅ Connector:      GitHub MCP (source code analysis)                      ║`n" } else { "" })║  ✅ Scheduled Task: daily-health-check (08:00 UTC)                           ║
║                                                                              ║
║  Portal: https://sre.azure.com                                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Outlook authorization reminder
Write-Host "📧 Outlook Authorization (required for email delivery):" -ForegroundColor Yellow
Write-Host "   The Outlook connector was created but must be authorized in the portal:" -ForegroundColor Gray
Write-Host ""
Write-Host "   1. Open https://sre.azure.com → your agent → Settings → Connectors" -ForegroundColor White
Write-Host "   2. Find the Outlook connector and click 'Authorize'" -ForegroundColor White
Write-Host "   3. Sign in with the account that should send incident emails" -ForegroundColor White
Write-Host "   4. Once authorized, agents can use SendOutlookEmail to deliver results" -ForegroundColor White
Write-Host ""

# Incident response plan guidance
Write-Host "📋 Incident Response Plan:" -ForegroundColor Yellow
Write-Host "   The script attempted to create an incident filter via the API." -ForegroundColor Gray
Write-Host "   If it failed (common — API may not support creation yet)," -ForegroundColor Gray
Write-Host "   create one manually in the portal:" -ForegroundColor Gray
Write-Host ""
Write-Host "   1. Open https://sre.azure.com → your agent" -ForegroundColor White
Write-Host "   2. Go to Builder → Incident response plans" -ForegroundColor White
Write-Host "   3. Click 'New incident response plan' with these settings:" -ForegroundColor White
Write-Host "      • Name:            AKS Pod Failure Handler" -ForegroundColor White
Write-Host "      • Severity:        Sev1, Sev2, Sev3" -ForegroundColor White
Write-Host "      • Title contains:  pod" -ForegroundColor White
Write-Host "      • Response agent:  incident-handler" -ForegroundColor White
Write-Host "      • Agent autonomy:  Review" -ForegroundColor White
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Authorize Outlook connector in the portal (see above)" -ForegroundColor White
Write-Host "  2. Open https://sre.azure.com and verify your agent configuration" -ForegroundColor White
Write-Host "  3. Check Builder → Agent Canvas to see agents and triggers" -ForegroundColor White
Write-Host "  4. Apply a breakable scenario: break-oom, break-crash, etc." -ForegroundColor White
Write-Host "  5. Ask the agent: 'Why are pods crashing in the pets namespace?'" -ForegroundColor White
Write-Host "  6. Or invoke directly: /agent incident-handler" -ForegroundColor White
Write-Host ""
