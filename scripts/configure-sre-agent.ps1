<#
.SYNOPSIS
    Configures the SRE Agent using the dataplane v2 API after infrastructure deployment.

.DESCRIPTION
    This script runs after deploy.ps1 to configure the SRE Agent with:
    - Knowledge base documents (runbooks uploaded to Agent Memory)
    - Custom agents via the dataplane v2 API
    - Azure Monitor connector and incident response plan
    - (Optional) GitHub MCP connector for source code analysis
    - Scheduled health and audit tasks
    - Review-mode routing to the incident-handler custom agent

    Uses the dataplane v2 API at {agentEndpoint}/api/v2/extendedAgent/
    which is the GA-supported programmatic configuration path.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.

.PARAMETER GitHubPat
    Optional GitHub Personal Access Token for enabling GitHub MCP integration.

.PARAMETER GitHubRepo
    Optional GitHub repository (owner/repo format) for code analysis agent.

.PARAMETER EnableMicrosoftLearnMcp
    Create the optional credential-free Microsoft Learn MCP connector.

.PARAMETER RemoveMicrosoftLearnMcp
    Remove the Microsoft Learn MCP connector and exit without changing other configuration.

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
$configurationFailures = [System.Collections.Generic.List[string]]::new()
$githubPreflightPassed = $false

if ($EnableMicrosoftLearnMcp -and $RemoveMicrosoftLearnMcp) {
    throw 'EnableMicrosoftLearnMcp and RemoveMicrosoftLearnMcp cannot be used together.'
}

function Add-ConfigurationFailure {
    param([Parameter(Mandatory)][string]$Component, [Parameter(Mandatory)][string]$Reason)
    $message = "${Component}: $Reason"
    [void]$configurationFailures.Add($message)
    Write-Host "    ❌ $message" -ForegroundColor Red
}

function Test-SuccessStatus {
    param([int]$StatusCode)
    return $StatusCode -ge 200 -and $StatusCode -lt 300
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Token
    )

    $output = & curl -sS -w "`n%{http_code}" "https://api.github.com$Path" `
        -H "Accept: application/vnd.github+json" `
        -H "Authorization: Bearer $Token" `
        -H 'X-GitHub-Api-Version: 2022-11-28' 2>&1
    $lines = ($output -join "`n") -split "`n"
    $statusCode = 0
    [void][int]::TryParse($lines[-1].Trim(), [ref]$statusCode)
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' }
    return @{ StatusCode = $statusCode; Body = $body }
}

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
    $attempt = 0

    do {
        $attempt++
        $curlArgs = @('-s', '-w', "`n%{http_code}", '-X', $Method, $url,
                      '-H', "Authorization: Bearer $Token")

        if ($Body) {
            $curlArgs += @('-H', 'Content-Type: application/json', '--data-binary', '@-')
            $output = $Body | & curl @curlArgs 2>&1
        }
        else {
            $output = & curl @curlArgs 2>&1
        }

        $lines = ($output -join "`n") -split "`n"
        $httpCode = $lines[-1].Trim()
        $responseBody = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)]) -join "`n" } else { '' }
        $statusCode = 0
        [void][int]::TryParse($httpCode, [ref]$statusCode)
        $retryable = $statusCode -eq 0 -or $statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500

        if ($retryable -and $attempt -lt 3) {
            Start-Sleep -Seconds (2 * $attempt)
        }
    } while ($retryable -and $attempt -lt 3)

    return @{
        StatusCode = $statusCode
        Body       = $responseBody
    }
}

function Set-ArmAgentConnector {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DataConnectorType,
        [Parameter(Mandatory)][string]$DataSource
    )

    $url = "https://management.azure.com${agentId}/connectors/${Name}?api-version=2025-05-01-preview"
    $body = @{
        properties = @{
            name              = $Name
            dataConnectorType = $DataConnectorType
            dataSource        = $DataSource
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $output = az rest `
        --method put `
        --url $url `
        --body $body `
        --only-show-errors `
        --output json 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    return @{
        ExitCode = $exitCode
        Body     = $output
    }
}

if ($RemoveMicrosoftLearnMcp) {
    Write-Host "`n📚 Removing Microsoft Learn MCP connector..." -ForegroundColor Yellow
    $token = Get-SreAgentToken
    $response = Invoke-DataplaneApi `
        -Method DELETE `
        -Path '/api/v2/extendedAgent/connectors/microsoft-learn' `
        -Token $token

    if ((Test-SuccessStatus -StatusCode $response.StatusCode) -or $response.StatusCode -eq 404) {
        Write-Host '  ✅ Microsoft Learn MCP connector is absent.' -ForegroundColor Green
        exit 0
    }

    Write-Error "Could not remove Microsoft Learn MCP connector. HTTP $($response.StatusCode)"
    exit 1
}

# ============================================================================
# Step 1: Upload Knowledge Base
# ============================================================================
if (-not $SkipKnowledgeBase) {
    Write-Host "`n📚 Step 1: Uploading knowledge base documents..." -ForegroundColor Yellow

    $kbPath = Join-Path $PSScriptRoot "..\sre-config\knowledge-base"
    $kbFiles = Get-ChildItem -Path $kbPath -Filter "*.md" -ErrorAction SilentlyContinue

    if ($kbFiles.Count -eq 0) {
        Add-ConfigurationFailure -Component 'Knowledge base' -Reason "No markdown files found in $kbPath"
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
                    Add-ConfigurationFailure -Component "Knowledge base/$($file.Name)" -Reason "HTTP $httpCode"
                }
            }
            catch {
                Add-ConfigurationFailure -Component "Knowledge base/$($file.Name)" -Reason $_.Exception.Message
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
                Add-ConfigurationFailure -Component 'Knowledge base verification' -Reason 'Could not parse the Agent Memory response'
            }
        }
        else {
            Add-ConfigurationFailure -Component 'Knowledge base verification' -Reason "HTTP $($filesResp.StatusCode)"
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
    $githubPreflightPassed = -not $hasGitHub
    $token = Get-SreAgentToken

    if ($hasGitHub) {
        if ([string]::IsNullOrWhiteSpace($GitHubRepo) -or $GitHubRepo -notmatch '^[^/\s]+/[^/\s]+$') {
            Add-ConfigurationFailure -Component 'GitHub preflight' -Reason 'GitHubRepo must use owner/repository format when GitHubPat is provided'
        }
        elseif ([string]::IsNullOrWhiteSpace($GitHubBranch) -or $GitHubBranch -match '[\r\n]') {
            Add-ConfigurationFailure -Component 'GitHub preflight' -Reason 'GitHubBranch must be a non-empty single line value'
        }
        else {
            $repoResp = Invoke-GitHubApi -Path "/repos/$GitHubRepo" -Token $GitHubPat
            if ($repoResp.StatusCode -ne 200) {
                Add-ConfigurationFailure -Component 'GitHub preflight' -Reason "Repository access check returned HTTP $($repoResp.StatusCode)"
            }
            else {
                $branchResp = Invoke-GitHubApi -Path "/repos/$GitHubRepo/branches/$([uri]::EscapeDataString($GitHubBranch))" -Token $GitHubPat
                if ($branchResp.StatusCode -ne 200) {
                    Add-ConfigurationFailure -Component 'GitHub preflight' -Reason "Branch '$GitHubBranch' access check returned HTTP $($branchResp.StatusCode)"
                }
                else {
                    Write-Host "  ✅ GitHub scope: $GitHubRepo@$GitHubBranch" -ForegroundColor Green
                    $githubPreflightPassed = $true
                }
            }
        }
    }

    # Check for Python + PyYAML
    $python = $null
    if (Get-Command python3 -ErrorAction SilentlyContinue) { $python = 'python3' }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $python = 'python' }
    elseif (Test-Path '/opt/az/bin/python3') { $python = '/opt/az/bin/python3' }

    $converterScript = Join-Path $PSScriptRoot "yaml-to-agent-json.py"
    $agentsDir = Join-Path $PSScriptRoot "..\sre-config\agents"

    if (-not $python) {
        Add-ConfigurationFailure -Component 'Custom agents' -Reason 'Python runtime not found; custom agents were not created'
    }
    elseif (-not (Test-Path $converterScript)) {
        Add-ConfigurationFailure -Component 'Custom agents' -Reason "Converter script not found: $converterScript"
    }
    else {
        # Test that pyyaml is available
        $null = & $python -c "import yaml" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  📦 Installing pyyaml..." -ForegroundColor Gray
            & $python -m pip install --user pyyaml 2>$null
        }

        # Determine which agents to create
        $agentFiles = @()

        if ($hasGitHub -and $githubPreflightPassed) {
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
                Add-ConfigurationFailure -Component 'Custom agents' -Reason "Agent file not found: $(Split-Path $yamlFile -Leaf)"
                continue
            }

            $agentFileName = Split-Path $yamlFile -Leaf

            # Convert YAML to API JSON
            $convertArgs = @($converterScript, $yamlFile)
            if ($hasGitHub -and $githubPreflightPassed -and $GitHubRepo) { $convertArgs += $GitHubRepo }
            $jsonBody = & $python @convertArgs 2>&1

            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonBody)) {
                Add-ConfigurationFailure -Component "Custom agents/$agentFileName" -Reason 'YAML conversion failed'
                continue
            }

            # Extract agent name from the JSON
            try {
                $agentObj = $jsonBody | ConvertFrom-Json
                $customAgentName = $agentObj.name
                if ($hasGitHub -and $githubPreflightPassed) {
                    $agentObj.properties.instructions += "`n`nGitHub safety boundary: use repository $GitHubRepo and branch $GitHubBranch only. Never print, quote, or store credentials. Redact secrets and tokens from evidence. Treat issue creation as an explicit reviewable action, request confirmation before creating it, and search for an existing incident fingerprint before creating a duplicate. Do not create or modify pull requests."
                    $jsonBody = $agentObj | ConvertTo-Json -Depth 20 -Compress
                }
            }
            catch {
                Add-ConfigurationFailure -Component "Custom agents/$agentFileName" -Reason 'Converter returned invalid JSON'
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
                Add-ConfigurationFailure -Component "Custom agent/$customAgentName" -Reason "HTTP $($resp.StatusCode)"
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
        else {
            Add-ConfigurationFailure -Component 'Custom agent verification' -Reason "HTTP $($listResp.StatusCode)"
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
    $hasGitHub = -not [string]::IsNullOrWhiteSpace($GitHubPat) -and $githubPreflightPassed

    # 3a: Azure Monitor connector (always)
    Write-Host "  📊 Creating Azure Monitor connector..." -ForegroundColor Gray

    $resp = Set-ArmAgentConnector `
        -Name 'azure-monitor' `
        -DataConnectorType 'AzureMonitor' `
        -DataSource 'azure-monitor'

    if ($resp.ExitCode -eq 0) {
        Write-Host "    ✅ Azure Monitor connector created" -ForegroundColor Green
    }
    else {
        Add-ConfigurationFailure -Component 'Connector/azure-monitor' -Reason "ARM command exit $($resp.ExitCode)"
    }

    # 3b: GitHub MCP connector (optional)
    if ($hasGitHub) {
        Write-Host "  🔗 Creating GitHub MCP connector..." -ForegroundColor Gray

        $ghBody = @{
            name       = "github-mcp"
            properties = @{
                dataConnectorType  = "StreamableHttp"
                dataSource         = "github"
                serverUri          = "https://api.githubcopilot.com/mcp/"
                authenticationType = "BearerToken"
                credentials        = @{
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
            Add-ConfigurationFailure -Component 'Connector/github-mcp' -Reason "HTTP $($resp.StatusCode)"
            Write-Host "       Use the pre-configured GitHub card in Settings > Connectors" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  🔗 GitHub connector — ⏭️  Skipped (no PAT provided)" -ForegroundColor Gray
    }

    # 3c: Microsoft Learn MCP connector (opt-in)
    if ($EnableMicrosoftLearnMcp) {
        Write-Host "  📚 Creating Microsoft Learn MCP connector..." -ForegroundColor Gray

        $learnBody = @{
            name       = "microsoft-learn"
            properties = @{
                dataConnectorType  = "StreamableHttp"
                dataSource         = "microsoft-learn"
                serverUri          = "https://learn.microsoft.com/api/mcp"
                authenticationType = "None"
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $resp = Invoke-DataplaneApi `
            -Method PUT `
            -Path "/api/v2/extendedAgent/connectors/microsoft-learn" `
            -Body $learnBody `
            -Token $token

        if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 202) {
            Write-Host "    ✅ Microsoft Learn MCP connector created" -ForegroundColor Green
        }
        else {
            Add-ConfigurationFailure -Component 'Connector/microsoft-learn' -Reason "HTTP $($resp.StatusCode)"
        }
    }
    else {
        Write-Host "  📚 Microsoft Learn MCP — ⏭️  Skipped (opt-in)" -ForegroundColor Gray
    }

    # 3d: Outlook connector (always — enables SendOutlookEmail tool)
    Write-Host "  📧 Creating Outlook connector..." -ForegroundColor Gray

    $resp = Set-ArmAgentConnector `
        -Name 'outlook' `
        -DataConnectorType 'Outlook' `
        -DataSource 'outlook'

    if ($resp.ExitCode -eq 0) {
        Write-Host "    ✅ Outlook connector created" -ForegroundColor Green
        Write-Host "    📌 Authorize in portal: https://sre.azure.com → Settings → Connectors → Outlook → Authorize" -ForegroundColor Gray
    }
    else {
        Add-ConfigurationFailure -Component 'Connector/outlook' -Reason "ARM command exit $($resp.ExitCode)"
        Write-Host "       Create it in the portal: Settings → Connectors → Add → Outlook" -ForegroundColor Gray
    }
}
else {
    Write-Host "`n🔌 Step 3: Skipping connector creation (-SkipConnectors)" -ForegroundColor Gray
}

# ============================================================================
# Step 4: Create Incident Response Plan
# ============================================================================
Write-Host "`n🚨 Step 4: Creating incident response plan..." -ForegroundColor Yellow

$token = Get-SreAgentToken
$filterName = 'aks-pod-failure-handler'
$handlerName = "$filterName-handler"
$filterDefinition = @{
    Id              = $filterName
    ImpactedService = 'pets'
    Priorities      = @('P1', 'P2')
    TitleContains   = 'Pet Store'
    AgentMode       = 'review'
    HandlingAgent   = 'incident-handler'
}
$processingGuide = @(
    'Use the incident-handler workflow to investigate the matched Azure Monitor alert.'
    'Correlate AKS pod state, Container Insights logs, recent events, and repository runbooks.'
    'Report root cause and evidence, then propose remediation for approval before any write action.'
)
$handlerDefinition = @{
    id                      = $handlerName
    name                    = 'AKS Pod Failure Handler'
    description             = 'Review-mode response plan for high-severity pet store alerts'
    incidentFilterId        = $filterName
    incidentProcessingGuide = $processingGuide
    tools                   = @()
    incidents               = @()
    customInstructions      = 'Trigger condition: Pet Store; severity: high; service: pets; mode: review'
}
$filterReady = $false
$filterEnabled = $false
$handlerReady = $false

$filterResponse = Invoke-DataplaneApi `
    -Method GET `
    -Path "/api/v1/incidentplayground/filters/$filterName" `
    -Token $token

if (Test-SuccessStatus -StatusCode $filterResponse.StatusCode) {
    try {
        $filter = $filterResponse.Body | ConvertFrom-Json
        $filterReady = $filter.id -eq $filterName -and
            $filter.impactedService -eq $filterDefinition.ImpactedService -and
            (@($filter.priorities) -join ',') -eq ($filterDefinition.Priorities -join ',') -and
            $filter.titleContains -eq $filterDefinition.TitleContains -and
            $filter.agentMode -eq $filterDefinition.AgentMode -and
            $filter.handlingAgent -eq $filterDefinition.HandlingAgent -and
            $filter.isDeleted -ne $true
        $filterEnabled = $filter.isEnabled -eq $true
    }
    catch {
        $filterReady = $false
    }

    if (-not $filterReady) {
        Add-ConfigurationFailure -Component "Incident response filter/$filterName" -Reason 'Existing definition does not match the default plan'
    }
}
elseif ($filterResponse.StatusCode -eq 404) {
    $filterResponse = Invoke-DataplaneApi `
        -Method PUT `
        -Path "/api/v1/incidentplayground/filters/$filterName" `
        -Body ($filterDefinition | ConvertTo-Json -Depth 10 -Compress) `
        -Token $token

    if (Test-SuccessStatus -StatusCode $filterResponse.StatusCode) {
        $filterReady = $true
    }
    else {
        Add-ConfigurationFailure -Component "Incident response filter/$filterName" -Reason "HTTP $($filterResponse.StatusCode)"
    }
}
else {
    Add-ConfigurationFailure -Component "Incident response filter/$filterName" -Reason "HTTP $($filterResponse.StatusCode)"
}

if ($filterReady) {
    $handlerResponse = Invoke-DataplaneApi `
        -Method GET `
        -Path "/api/v1/incidentplayground/handlers/$handlerName" `
        -Token $token

    if (Test-SuccessStatus -StatusCode $handlerResponse.StatusCode) {
        try {
            $handler = $handlerResponse.Body | ConvertFrom-Json
            $handlerReady = $handler.id -eq $handlerName -and
                $handler.name -eq $handlerDefinition.name -and
                $handler.incidentFilterId -eq $filterName -and
                (@($handler.incidentProcessingGuide) -join "`n") -eq ($processingGuide -join "`n")
        }
        catch {
            $handlerReady = $false
        }

        if (-not $handlerReady) {
            Add-ConfigurationFailure -Component "Incident response handler/$handlerName" -Reason 'Existing definition does not match the default plan'
        }
    }
    elseif ($handlerResponse.StatusCode -eq 404) {
        $handlerResponse = Invoke-DataplaneApi `
            -Method PUT `
            -Path "/api/v1/incidentplayground/handlers/$handlerName" `
            -Body ($handlerDefinition | ConvertTo-Json -Depth 10 -Compress) `
            -Token $token

        if (Test-SuccessStatus -StatusCode $handlerResponse.StatusCode) {
            $handlerReady = $true
        }
        else {
            Add-ConfigurationFailure -Component "Incident response handler/$handlerName" -Reason "HTTP $($handlerResponse.StatusCode)"
        }
    }
    else {
        Add-ConfigurationFailure -Component "Incident response handler/$handlerName" -Reason "HTTP $($handlerResponse.StatusCode)"
    }
}

if ($filterReady -and $handlerReady) {
    if (-not $filterEnabled) {
        $enableResponse = Invoke-DataplaneApi `
            -Method POST `
            -Path "/api/v1/incidentplayground/filters/$filterName/enable" `
            -Token $token

        if (-not (Test-SuccessStatus -StatusCode $enableResponse.StatusCode)) {
            Add-ConfigurationFailure -Component "Incident response plan/$filterName/enable" -Reason "HTTP $($enableResponse.StatusCode)"
        }
        else {
            $filterEnabled = $true
        }
    }

    if ($filterEnabled) {
        Write-Host "  ✅ Incident response plan '$filterName' configured and enabled" -ForegroundColor Green
    }
}

# ============================================================================
# Step 5: Create Scheduled Tasks
# ============================================================================
if (-not $SkipScheduledTasks) {
    Write-Host "`n⏰ Step 5: Creating scheduled health check..." -ForegroundColor Yellow

    $token = Get-SreAgentToken

    $scheduledTasks = @(
        @{
            Name = 'daily-health-check'
            Cron = '0 8 * * *'
            Prompt = 'Run a comprehensive health check of the AKS cluster in the pets namespace. Check all pod statuses, recent restarts, resource utilization, and error trends. Report any issues found with severity ratings.'
        }
        @{
            Name = 'daily-rbac-cost-network-audit'
            Cron = '30 8 * * *'
            Prompt = 'Run a read-only audit of the pets demo resource group. Review RBAC scope, estimated cost signals, network configuration, and public exposure. Report findings without making changes.'
        }
        @{
            Name = 'hourly-automation-health'
            Cron = '0 * * * *'
            Prompt = 'Run a read-only health check of the pets namespace and Azure Monitor integration. Report active failures, alert readiness, and telemetry gaps. Do not remediate.'
        }
    )

    foreach ($task in $scheduledTasks) {
        $taskBody = @{
            name       = $task.Name
            type       = "ScheduledTask"
            properties = @{
                cronExpression = $task.Cron
                agentPrompt    = $task.Prompt
                agentName      = "cluster-health-monitor"
                enabled        = $true
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $resp = Invoke-DataplaneApi `
            -Method PUT `
            -Path "/api/v2/extendedAgent/scheduledTasks/$($task.Name)" `
            -Body $taskBody `
            -Token $token

        if ($resp.StatusCode -eq 202 -or $resp.StatusCode -eq 200) {
            Write-Host "  ✅ Scheduled task '$($task.Name)' created" -ForegroundColor Green
        }
        else {
            Add-ConfigurationFailure -Component "Scheduled task/$($task.Name)" -Reason "HTTP $($resp.StatusCode)"
        }
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
$(if ($hasGitHub) { "║  ✅ Connector:      GitHub MCP (source code analysis)                      ║`n" } else { "" })║  ✅ Scheduled Tasks: daily health, daily audit, hourly health                ║
║  ✅ Response Plan:  AKS pod failures → incident-handler (Review)             ║
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

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Authorize Outlook connector in the portal (see above)" -ForegroundColor White
Write-Host "  2. Open https://sre.azure.com and verify your agent configuration" -ForegroundColor White
Write-Host "  3. Check Builder → Agent Canvas to see agents and triggers" -ForegroundColor White
Write-Host "  4. Apply a breakable scenario: break-oom, break-crash, etc." -ForegroundColor White
Write-Host "  5. Ask the agent: 'Why are pods crashing in the pets namespace?'" -ForegroundColor White
Write-Host "  6. Or invoke directly: /agent incident-handler" -ForegroundColor White
Write-Host ""

if ($configurationFailures.Count -gt 0) {
    Write-Host "Configuration completed with $($configurationFailures.Count) failure(s):" -ForegroundColor Red
    foreach ($failure in $configurationFailures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Configuration verified successfully." -ForegroundColor Green
