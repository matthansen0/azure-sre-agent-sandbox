<#
.SYNOPSIS
    Configures RBAC permissions for Azure SRE Agent and related services.

.DESCRIPTION
    This script assigns necessary RBAC roles that cannot be reliably assigned
    through Bicep due to subscription policy restrictions.
    
    Includes:
    - SRE Agent roles (when SRE Agent is created)
    - Contributor access for managed identities
    - Key Vault access roles

.PARAMETER ResourceGroupName
    The resource group containing the deployed resources

.PARAMETER SreAgentPrincipalId
    Object ID of the SRE Agent managed identity (if already created)

.PARAMETER CurrentUserPrincipalId
    Object ID of the current user for admin access

.EXAMPLE
    .\configure-rbac.ps1 -ResourceGroupName "rg-srelab-eastus2"

.NOTES
    This script is idempotent - safe to run multiple times.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$SreAgentPrincipalId,

    [Parameter()]
    [string]$CurrentUserPrincipalId
)

$ErrorActionPreference = 'Stop'

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    Azure RBAC Configuration Script                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Get current user if not provided
if (-not $CurrentUserPrincipalId) {
    Write-Host "🔍 Getting current user principal ID..." -ForegroundColor Yellow
    $account = az ad signed-in-user show --output json 2>$null | ConvertFrom-Json
    if ($account) {
        $CurrentUserPrincipalId = $account.id
        Write-Host "  ✅ Current user: $($account.displayName) ($CurrentUserPrincipalId)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Could not determine current user. Some role assignments may be skipped." -ForegroundColor Yellow
    }
}

# Get resource group info
Write-Host "`n🔍 Getting resource group information..." -ForegroundColor Yellow
$rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json

if (-not $rg) {
    Write-Error "Resource group '$ResourceGroupName' not found"
    exit 1
}

Write-Host "  ✅ Resource Group: $ResourceGroupName" -ForegroundColor Green
Write-Host "  📍 Location: $($rg.location)" -ForegroundColor Gray

# Get subscription ID
$subscriptionId = (az account show --output json | ConvertFrom-Json).id

# Function to assign role with error handling
function Set-RoleAssignment {
    param(
        [string]$Scope,
        [string]$RoleDefinition,
        [string]$PrincipalId,
        [string]$PrincipalType = "ServicePrincipal",
        [string]$Description
    )
    
    if (-not $PrincipalId) {
        Write-Host "    ⏭️  Skipping: No principal ID provided" -ForegroundColor Gray
        return
    }
    
    Write-Host "    📋 $Description" -ForegroundColor White
    
    # Check if assignment already exists
    $existing = az role assignment list `
        --scope $Scope `
        --role $RoleDefinition `
        --assignee $PrincipalId `
        --output json 2>$null | ConvertFrom-Json

    if ($existing -and $existing.Count -gt 0) {
        Write-Host "       ✅ Already assigned" -ForegroundColor Green
        return
    }

    try {
        az role assignment create `
            --scope $Scope `
            --role $RoleDefinition `
            --assignee-object-id $PrincipalId `
            --assignee-principal-type $PrincipalType `
            --output none 2>$null
        
        Write-Host "       ✅ Assigned successfully" -ForegroundColor Green
    } catch {
        Write-Host "       ⚠️  Failed to assign: $_" -ForegroundColor Yellow
        Write-Host "          This may be due to subscription policies." -ForegroundColor Gray
    }
}

# Get AKS cluster info
Write-Host "`n🔍 Getting AKS cluster information..." -ForegroundColor Yellow
$aksCluster = az aks list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json | Select-Object -First 1

if ($aksCluster) {
    $aksIdentityPrincipalId = $aksCluster.identityProfile.kubeletidentity.objectId
    $aksControlPlaneIdentity = $aksCluster.identity.principalId
    
    Write-Host "  ✅ AKS Cluster: $($aksCluster.name)" -ForegroundColor Green
    Write-Host "     Kubelet Identity: $aksIdentityPrincipalId" -ForegroundColor Gray
    Write-Host "     Control Plane Identity: $aksControlPlaneIdentity" -ForegroundColor Gray
}

# Assign roles
Write-Host "`n🔐 Assigning RBAC roles..." -ForegroundColor Yellow

# 1. AKS Cluster Admin for current user
if ($CurrentUserPrincipalId) {
    Write-Host "`n  📌 AKS Cluster Access:" -ForegroundColor Cyan
    Set-RoleAssignment `
        -Scope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" `
        -RoleDefinition "Azure Kubernetes Service Cluster Admin Role" `
        -PrincipalId $CurrentUserPrincipalId `
        -PrincipalType "User" `
        -Description "AKS Cluster Admin Role for current user"
    
    Set-RoleAssignment `
        -Scope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" `
        -RoleDefinition "Azure Kubernetes Service RBAC Cluster Admin" `
        -PrincipalId $CurrentUserPrincipalId `
        -PrincipalType "User" `
        -Description "AKS RBAC Cluster Admin for current user"
}

# 2. Key Vault roles
$keyVault = az keyvault list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json | Select-Object -First 1

if ($keyVault -and $CurrentUserPrincipalId) {
    Write-Host "`n  📌 Key Vault Access:" -ForegroundColor Cyan
    Set-RoleAssignment `
        -Scope $keyVault.id `
        -RoleDefinition "Key Vault Administrator" `
        -PrincipalId $CurrentUserPrincipalId `
        -PrincipalType "User" `
        -Description "Key Vault Administrator for current user"
}

# 3. SRE Agent roles (if SRE Agent is already created)
if ($SreAgentPrincipalId) {
    Write-Host "`n  📌 SRE Agent Access:" -ForegroundColor Cyan
    
    # SRE Agent needs Contributor on the resource group to diagnose AND remediate issues
    Set-RoleAssignment `
        -Scope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" `
        -RoleDefinition "Contributor" `
        -PrincipalId $SreAgentPrincipalId `
        -PrincipalType "ServicePrincipal" `
        -Description "Contributor for SRE Agent (read/write access to resources)"
    
    # Reader on subscription for broader context
    Set-RoleAssignment `
        -Scope "/subscriptions/$subscriptionId" `
        -RoleDefinition "Reader" `
        -PrincipalId $SreAgentPrincipalId `
        -PrincipalType "ServicePrincipal" `
        -Description "Reader for SRE Agent at subscription level"
    
    # AKS-specific roles for Kubernetes operations (restart pods, scale, etc.)
    if ($aksCluster) {
        Write-Host "`n  📌 SRE Agent AKS Access:" -ForegroundColor Cyan
        
        # Azure Kubernetes Service Cluster Admin - allows kubectl access
        Set-RoleAssignment `
            -Scope $aksCluster.id `
            -RoleDefinition "Azure Kubernetes Service Cluster Admin Role" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "AKS Cluster Admin for SRE Agent (kubectl access)"
        
        # Azure Kubernetes Service RBAC Cluster Admin - full K8s RBAC permissions
        Set-RoleAssignment `
            -Scope $aksCluster.id `
            -RoleDefinition "Azure Kubernetes Service RBAC Cluster Admin" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "AKS RBAC Cluster Admin for SRE Agent (full K8s permissions)"
        
        # Azure Kubernetes Service Contributor - manage AKS resource itself
        Set-RoleAssignment `
            -Scope $aksCluster.id `
            -RoleDefinition "Azure Kubernetes Service Contributor Role" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "AKS Contributor for SRE Agent (scale nodes, update config)"
    }
    
    # Log Analytics access for querying logs
    $logAnalytics = az monitor log-analytics workspace list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
    if ($logAnalytics) {
        Set-RoleAssignment `
            -Scope $logAnalytics.id `
            -RoleDefinition "Log Analytics Contributor" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "Log Analytics Contributor for SRE Agent (query and manage logs)"
    }
    
    # Key Vault access for secrets management
    if ($keyVault) {
        Set-RoleAssignment `
            -Scope $keyVault.id `
            -RoleDefinition "Key Vault Secrets Officer" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "Key Vault Secrets Officer for SRE Agent (manage secrets)"
    }
    
    # Container Registry access
    $acr = az acr list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
    if ($acr) {
        Set-RoleAssignment `
            -Scope $acr.id `
            -RoleDefinition "AcrPush" `
            -PrincipalId $SreAgentPrincipalId `
            -PrincipalType "ServicePrincipal" `
            -Description "ACR Push for SRE Agent (push/pull images)"
    }
}

# 4. Grafana roles (if Grafana is deployed)
$grafanaJson = az grafana list --resource-group $ResourceGroupName --output json 2>$null
$grafana = $null
if ($grafanaJson -and $grafanaJson -match '^\s*\[') {
    try {
        $grafana = $grafanaJson | ConvertFrom-Json | Select-Object -First 1
    } catch {
        # Ignore JSON parsing errors - Grafana likely not deployed
    }
}

if ($grafana) {
    Write-Host "`n  📌 Grafana Access:" -ForegroundColor Cyan
    $grafanaPrincipalId = $grafana.identity.principalId
    
    Set-RoleAssignment `
        -Scope "/subscriptions/$subscriptionId" `
        -RoleDefinition "Monitoring Reader" `
        -PrincipalId $grafanaPrincipalId `
        -PrincipalType "ServicePrincipal" `
        -Description "Monitoring Reader for Grafana"
    
    if ($CurrentUserPrincipalId) {
        Set-RoleAssignment `
            -Scope $grafana.id `
            -RoleDefinition "Grafana Admin" `
            -PrincipalId $CurrentUserPrincipalId `
            -PrincipalType "User" `
            -Description "Grafana Admin for current user"
    }
}

# Final summary
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                      RBAC Configuration Complete ✅                           ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Note: When you create an Azure SRE Agent, you'll need to:                   ║
║                                                                              ║
║  1. Get the SRE Agent's managed identity Object ID from Azure Portal         ║
║  2. Run this script again with -SreAgentPrincipalId parameter:               ║
║                                                                              ║
║     .\configure-rbac.ps1 -ResourceGroupName "$ResourceGroupName" ``
║         -SreAgentPrincipalId "<object-id>"                                   ║
║                                                                              ║
║  SRE Agent RBAC Roles (assigned via Azure Portal):                           ║
║  • SRE Agent Admin - Full access to create/manage agent                     ║
║  • SRE Agent Standard User - Chat and diagnose capabilities                 ║
║  • SRE Agent Reader - View-only access                                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
