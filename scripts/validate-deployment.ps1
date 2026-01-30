<#
.SYNOPSIS
    Validates that the Azure SRE Agent Demo Lab deployment is healthy.

.DESCRIPTION
    This script checks:
    - Azure resources are provisioned and healthy
    - AKS cluster is reachable
    - All pods in the demo application are running
    - Services have endpoints assigned
    - Basic connectivity tests pass

.PARAMETER ResourceGroupName
    Name of the resource group containing the deployment

.PARAMETER Detailed
    Show detailed output for each check

.EXAMPLE
    .\validate-deployment.ps1 -ResourceGroupName "rg-srelab-eastus2"

.EXAMPLE
    .\validate-deployment.ps1 -ResourceGroupName "rg-srelab-eastus2" -Detailed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter()]
    [switch]$Detailed
)

$ErrorActionPreference = 'Continue'

# Colors and formatting
function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Message = "")
    if ($Passed) {
        Write-Host "  ✅ $Name" -ForegroundColor Green
        if ($Message -and $Detailed) { Write-Host "     $Message" -ForegroundColor Gray }
    }
    else {
        Write-Host "  ❌ $Name" -ForegroundColor Red
        if ($Message) { Write-Host "     $Message" -ForegroundColor Yellow }
    }
    return $Passed
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

# Banner
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                   Azure SRE Agent Demo Lab - Validation                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Checking deployment health and readiness...                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$totalChecks = 0
$passedChecks = 0

# =============================================================================
# AZURE RESOURCE CHECKS
# =============================================================================
Write-Section "Azure Resources"

# Check resource group exists
$rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json
$totalChecks++
if (Write-Check "Resource Group exists" ($null -ne $rg) "Location: $($rg.location)") {
    $passedChecks++
}

# Get all resources in RG
$resources = az resource list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json

# Check AKS
$aks = $resources | Where-Object { $_.type -eq "Microsoft.ContainerService/managedClusters" }
$totalChecks++
if (Write-Check "AKS Cluster exists" ($null -ne $aks) $aks.name) {
    $passedChecks++
    
    # Get AKS details
    $aksDetails = az aks show --resource-group $ResourceGroupName --name $aks.name --output json 2>$null | ConvertFrom-Json
    
    $totalChecks++
    if (Write-Check "AKS Cluster is running" ($aksDetails.provisioningState -eq "Succeeded" -and $aksDetails.powerState.code -eq "Running") "State: $($aksDetails.powerState.code)") {
        $passedChecks++
    }
    
    # Check AKS is NOT private (required for SRE Agent)
    $totalChecks++
    $isPublic = -not $aksDetails.apiServerAccessProfile.enablePrivateCluster
    if (Write-Check "AKS API is public (required for SRE Agent)" $isPublic) {
        $passedChecks++
    }
    
    # Store AKS name for later
    $aksName = $aks.name
}

# Check Container Registry
$acr = $resources | Where-Object { $_.type -eq "Microsoft.ContainerRegistry/registries" }
$totalChecks++
if (Write-Check "Container Registry exists" ($null -ne $acr) $acr.name) {
    $passedChecks++
}

# Check Log Analytics
$la = $resources | Where-Object { $_.type -eq "Microsoft.OperationalInsights/workspaces" }
$totalChecks++
if (Write-Check "Log Analytics Workspace exists" ($null -ne $la) $la.name) {
    $passedChecks++
}

# Check App Insights
$ai = $resources | Where-Object { $_.type -eq "Microsoft.Insights/components" }
$totalChecks++
if (Write-Check "Application Insights exists" ($null -ne $ai) $ai.name) {
    $passedChecks++
}

# Check Key Vault
$kv = $resources | Where-Object { $_.type -eq "Microsoft.KeyVault/vaults" }
$totalChecks++
if (Write-Check "Key Vault exists" ($null -ne $kv) $kv.name) {
    $passedChecks++
}

# Check Grafana (optional)
$grafana = $resources | Where-Object { $_.type -eq "Microsoft.Dashboard/grafana" }
if ($grafana) {
    $totalChecks++
    if (Write-Check "Managed Grafana exists" $true $grafana.name) {
        $passedChecks++
    }
}

# =============================================================================
# KUBERNETES CONNECTIVITY
# =============================================================================
Write-Section "Kubernetes Connectivity"

# Get AKS credentials if needed
if ($aksName) {
    Write-Host "  Connecting to AKS cluster..." -ForegroundColor Gray
    az aks get-credentials --resource-group $ResourceGroupName --name $aksName --overwrite-existing 2>$null
}

# Test kubectl connectivity
$kubectlTest = kubectl cluster-info 2>&1
$totalChecks++
if (Write-Check "kubectl can connect to cluster" ($LASTEXITCODE -eq 0)) {
    $passedChecks++
}

# Check node status
$nodes = kubectl get nodes -o json 2>$null | ConvertFrom-Json
$totalChecks++
$healthyNodes = ($nodes.items | Where-Object { 
        ($_.status.conditions | Where-Object { $_.type -eq "Ready" }).status -eq "True" 
    }).Count
$totalNodes = $nodes.items.Count
if (Write-Check "All nodes are Ready" ($healthyNodes -eq $totalNodes) "$healthyNodes/$totalNodes nodes ready") {
    $passedChecks++
}

# =============================================================================
# APPLICATION HEALTH
# =============================================================================
Write-Section "Demo Application (pets namespace)"

# Check if namespace exists
$namespace = kubectl get namespace pets -o json 2>$null | ConvertFrom-Json
$totalChecks++
if (Write-Check "Namespace 'pets' exists" ($null -ne $namespace)) {
    $passedChecks++
}
else {
    Write-Host "  ⚠️  Run: kubectl apply -f k8s/base/application.yaml" -ForegroundColor Yellow
}

# Check pods
if ($namespace) {
    $pods = kubectl get pods -n pets -o json 2>$null | ConvertFrom-Json
    
    if ($pods.items.Count -gt 0) {
        Write-Host "`n  Pod Status:" -ForegroundColor White
        
        foreach ($pod in $pods.items) {
            $podName = $pod.metadata.name
            $phase = $pod.status.phase
            $ready = ($pod.status.containerStatuses | Where-Object { $_.ready -eq $true }).Count
            $total = $pod.status.containerStatuses.Count
            
            $totalChecks++
            $isHealthy = ($phase -eq "Running") -and ($ready -eq $total)
            
            $statusIcon = if ($isHealthy) { "✅" } else { "❌" }
            $statusColor = if ($isHealthy) { "Green" } else { "Red" }
            
            if ($Detailed -or -not $isHealthy) {
                Write-Host "    $statusIcon $podName - $phase ($ready/$total ready)" -ForegroundColor $statusColor
            }
            
            if ($isHealthy) { $passedChecks++ }
        }
        
        # Summary
        $runningPods = ($pods.items | Where-Object { $_.status.phase -eq "Running" }).Count
        Write-Host "`n  Summary: $runningPods/$($pods.items.Count) pods running" -ForegroundColor $(if ($runningPods -eq $pods.items.Count) { "Green" } else { "Yellow" })
    }
    else {
        Write-Host "  ⚠️  No pods found in 'pets' namespace" -ForegroundColor Yellow
        Write-Host "     Run: kubectl apply -f k8s/base/application.yaml" -ForegroundColor Gray
    }
}

# Check services
Write-Host "`n  Services:" -ForegroundColor White
$services = kubectl get svc -n pets -o json 2>$null | ConvertFrom-Json

foreach ($svc in $services.items) {
    $svcName = $svc.metadata.name
    $svcType = $svc.spec.type
    $hasEndpoint = $false
    
    if ($svcType -eq "LoadBalancer") {
        $externalIP = $null
        if ($svc.status.loadBalancer.ingress -and $svc.status.loadBalancer.ingress.Count -gt 0) {
            $externalIP = $svc.status.loadBalancer.ingress[0].ip
        }
        $hasEndpoint = $null -ne $externalIP
        $endpoint = if ($hasEndpoint) { $externalIP } else { "Pending" }
    }
    elseif ($svcType -eq "ClusterIP") {
        $hasEndpoint = $true
        $endpoint = $svc.spec.clusterIP
    }
    else {
        $hasEndpoint = $true
        $endpoint = $svcType
    }
    
    $totalChecks++
    if (Write-Check "$svcName ($svcType)" $hasEndpoint $endpoint) {
        $passedChecks++
    }
}

# Check for store-front LoadBalancer specifically
$storeFrontSvc = $services.items | Where-Object { $_.metadata.name -eq "store-front" }
if ($storeFrontSvc -and $storeFrontSvc.spec.type -eq "LoadBalancer") {
    $externalIP = $null
    if ($storeFrontSvc.status.loadBalancer.ingress -and $storeFrontSvc.status.loadBalancer.ingress.Count -gt 0) {
        $externalIP = $storeFrontSvc.status.loadBalancer.ingress[0].ip
    }
    if ($externalIP) {
        Write-Host "`n  🌐 Store Front URL: http://$externalIP" -ForegroundColor Cyan
    }
}

# =============================================================================
# OBSERVABILITY
# =============================================================================
Write-Section "Observability"

# Check Container Insights
$ciDaemonset = kubectl get daemonset -n kube-system -l component=oms-agent -o json 2>$null | ConvertFrom-Json
if ($ciDaemonset.items.Count -gt 0) {
    $totalChecks++
    $desired = $ciDaemonset.items[0].status.desiredNumberScheduled
    $ready = $ciDaemonset.items[0].status.numberReady
    if (Write-Check "Container Insights agent running" ($ready -eq $desired) "$ready/$desired pods") {
        $passedChecks++
    }
}
else {
    # Azure Monitor Agent (newer)
    $amaDeployment = kubectl get pods -n kube-system -l app=ama-logs -o json 2>$null | ConvertFrom-Json
    if ($amaDeployment.items.Count -gt 0) {
        $totalChecks++
        $running = ($amaDeployment.items | Where-Object { $_.status.phase -eq "Running" }).Count
        if (Write-Check "Azure Monitor Agent running" ($running -gt 0) "$running pods") {
            $passedChecks++
        }
    }
    else {
        Write-Host "  ℹ️  No Container Insights agent detected" -ForegroundColor Gray
    }
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host "`n"
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { "Green" } else { "Yellow" })
Write-Host "  VALIDATION SUMMARY: $passedChecks/$totalChecks checks passed" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { "Green" } else { "Yellow" })
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { "Green" } else { "Yellow" })

if ($passedChecks -eq $totalChecks) {
    Write-Host @"

✅ All checks passed! Your deployment is healthy.

Next steps:
1. Create SRE Agent: https://portal.azure.com/#create/Microsoft.SREAgent
2. Break something: kubectl apply -f k8s/scenarios/oom-killed.yaml
3. Ask SRE Agent to diagnose!

"@ -ForegroundColor Green
}
else {
    $failedChecks = $totalChecks - $passedChecks
    Write-Host @"

⚠️  $failedChecks check(s) failed. Review the issues above.

Common fixes:
- Deploy application: kubectl apply -f k8s/base/application.yaml
- Wait for pods: kubectl get pods -n pets -w
- Check events: kubectl get events -n pets --sort-by='.lastTimestamp'

"@ -ForegroundColor Yellow
}

# Return exit code
if ($passedChecks -ne $totalChecks) {
    exit 1
}
