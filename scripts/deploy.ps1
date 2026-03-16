<#
.SYNOPSIS
    Deploys the Azure SRE Agent Demo Lab infrastructure using Bicep.

.DESCRIPTION
    This script deploys all Azure infrastructure needed for the SRE Agent demo,
    including AKS, Container Registry, Key Vault, observability tools, and
    Azure SRE Agent (Microsoft.App/agents@2025-05-01-preview).
    It uses device code authentication by default for dev container support.

.PARAMETER Location
    Azure region for deployment. Must be an SRE Agent supported region.
    Valid values: eastus2, swedencentral, australiaeast

.PARAMETER WorkloadName
    Name prefix for resources. Default: srelab

.PARAMETER SkipRbac
    Skip RBAC role assignments (useful if subscription policies block them)

.PARAMETER SkipSreAgent
    Skip Azure SRE Agent deployment and deploy only the core lab infrastructure

.PARAMETER WhatIf
    Show what would be deployed without making changes

.EXAMPLE
    .\deploy.ps1 -Location eastus2

.EXAMPLE
    .\deploy.ps1 -Location eastus2 -WhatIf

.NOTES
    Author: Azure SRE Agent Demo Lab
    Prerequisites: Azure CLI, Bicep CLI
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('eastus2', 'swedencentral', 'australiaeast')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidateLength(3, 10)]
    [string]$WorkloadName = 'srelab',

    [Parameter()]
    [switch]$SkipRbac,

    [Parameter()]
    [switch]$SkipSreAgent,

    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    # Run command and capture all output
    $raw = Invoke-Expression $Command 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            ExitCode = $exitCode
            Raw      = $raw
            Json     = $null
        }
    }

    # Extract JSON from output (skip any warning lines before the JSON)
    $jsonObjectStart = $raw.IndexOf('{')
    $jsonArrayStart = $raw.IndexOf('[')

    if ($jsonObjectStart -ge 0 -and $jsonArrayStart -ge 0) {
        $jsonStart = [Math]::Min($jsonObjectStart, $jsonArrayStart)
    }
    elseif ($jsonObjectStart -ge 0) {
        $jsonStart = $jsonObjectStart
    }
    elseif ($jsonArrayStart -ge 0) {
        $jsonStart = $jsonArrayStart
    }
    else {
        $jsonStart = -1
    }

    if ($jsonStart -ge 0) {
        $jsonContent = $raw.Substring($jsonStart)
    }
    else {
        $jsonContent = $raw
    }

    try {
        $json = $jsonContent | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            ExitCode = $exitCode
            Raw      = $raw
            Json     = $null
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Raw      = $raw
        Json     = $json
    }
}

function Get-ArmErrorMessages {
    [CmdletBinding()]
    param(
        [Parameter()]
        $ErrorObject
    )

    $messages = [System.Collections.Generic.List[string]]::new()

    function Add-ArmErrorMessage {
        param(
            [Parameter()]
            $Node
        )

        if ($null -eq $Node) {
            return
        }

        if ($Node -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($Node)) {
                [void]$messages.Add($Node.Trim())
            }
            return
        }

        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
            foreach ($Item in $Node) {
                Add-ArmErrorMessage -Node $Item
            }
            return
        }

        $propertyNames = @($Node.PSObject.Properties.Name)
        if ($propertyNames -contains 'message' -and -not [string]::IsNullOrWhiteSpace($Node.message)) {
            $message = if ($propertyNames -contains 'code' -and -not [string]::IsNullOrWhiteSpace($Node.code)) {
                "[$($Node.code)] $($Node.message)"
            }
            else {
                [string]$Node.message
            }

            [void]$messages.Add($message.Trim())
        }

        if ($propertyNames -contains 'error' -and $null -ne $Node.error) {
            Add-ArmErrorMessage -Node $Node.error
        }

        if ($propertyNames -contains 'details' -and $null -ne $Node.details) {
            Add-ArmErrorMessage -Node $Node.details
        }
    }

    Add-ArmErrorMessage -Node $ErrorObject

    return @($messages | Select-Object -Unique)
}

function Write-ResourceGroupDeploymentFailureSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$DeploymentName,

        [Parameter()]
        [string]$Indent = '    '
    )

    $operations = Invoke-AzCliJson -Command "az deployment operation group list --resource-group $ResourceGroupName --name $DeploymentName --output json"
    if ($operations.ExitCode -ne 0 -or -not $operations.Json) {
        return
    }

    $failedOperations = @($operations.Json | Where-Object { $_.properties.provisioningState -eq 'Failed' })
    if ($failedOperations.Count -eq 0) {
        $deployment = Invoke-AzCliJson -Command "az deployment group show --resource-group $ResourceGroupName --name $DeploymentName --output json"
        if ($deployment.ExitCode -ne 0 -or -not $deployment.Json -or -not $deployment.Json.properties.error) {
            return
        }

        $messages = @(Get-ArmErrorMessages -ErrorObject $deployment.Json.properties.error)
        if ($messages.Count -eq 0) {
            return
        }

        Write-Host "$Indent Nested deployment details for ${DeploymentName}:" -ForegroundColor Yellow
        foreach ($message in $messages) {
            Write-Host "$Indent   - $message" -ForegroundColor Yellow
        }
        return
    }

    Write-Host "$Indent Nested deployment failures for ${DeploymentName}:" -ForegroundColor Yellow
    foreach ($failedOperation in $failedOperations) {
        $targetResource = $failedOperation.properties.targetResource
        $targetType = if ($targetResource.resourceType) { $targetResource.resourceType } else { '<unknown-type>' }
        $targetName = if ($targetResource.resourceName) { $targetResource.resourceName } else { '<unknown-name>' }
        Write-Host "$Indent   - $targetType/$targetName" -ForegroundColor Yellow

        $messages = @(Get-ArmErrorMessages -ErrorObject $failedOperation.properties.statusMessage)
        foreach ($message in $messages) {
            Write-Host "$Indent     $message" -ForegroundColor Yellow
        }
    }
}

function Write-SubscriptionDeploymentFailureSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentName,

        [Parameter()]
        [string]$ResourceGroupName
    )

    $operations = Invoke-AzCliJson -Command "az deployment operation sub list --name $DeploymentName --output json"
    if ($operations.ExitCode -ne 0 -or -not $operations.Json) {
        return
    }

    $failedOperations = @($operations.Json | Where-Object { $_.properties.provisioningState -eq 'Failed' })
    if ($failedOperations.Count -eq 0) {
        return
    }

    Write-Host "`nFailed deployment operations:" -ForegroundColor Yellow
    foreach ($failedOperation in $failedOperations) {
        $targetResource = $failedOperation.properties.targetResource
        $targetType = if ($targetResource.resourceType) { $targetResource.resourceType } else { '<unknown-type>' }
        $targetName = if ($targetResource.resourceName) { $targetResource.resourceName } else { '<unknown-name>' }
        Write-Host "  • $targetType/$targetName" -ForegroundColor Yellow

        $messages = @(Get-ArmErrorMessages -ErrorObject $failedOperation.properties.statusMessage)
        foreach ($message in $messages) {
            Write-Host "    $message" -ForegroundColor Yellow
        }

        if ($ResourceGroupName -and $targetType -eq 'Microsoft.Resources/deployments' -and $targetName) {
            Write-ResourceGroupDeploymentFailureSummary -ResourceGroupName $ResourceGroupName -DeploymentName $targetName
        }
    }
}

function Get-DeletedKeyVaultConflict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName
    )

    $deployment = Invoke-AzCliJson -Command "az deployment group show --resource-group $ResourceGroupName --name deploy-keyvault --output json"
    if ($deployment.ExitCode -ne 0 -or -not $deployment.Json -or -not $deployment.Json.properties.error) {
        return $null
    }

    $errorJson = $deployment.Json.properties.error | ConvertTo-Json -Depth 20
    if ($errorJson -notmatch 'already exists in deleted state') {
        return $null
    }

    $operations = Invoke-AzCliJson -Command "az deployment operation group list --resource-group $ResourceGroupName --name deploy-keyvault --output json"
    if ($operations.ExitCode -ne 0 -or -not $operations.Json) {
        return $null
    }

    $vaultOperation = @($operations.Json | Where-Object {
            $_.properties.targetResource.resourceType -eq 'Microsoft.KeyVault/vaults'
        } | Select-Object -First 1)

    if (-not $vaultOperation) {
        return $null
    }

    $vaultName = $vaultOperation.properties.targetResource.resourceName
    if ([string]::IsNullOrWhiteSpace($vaultName)) {
        return $null
    }

    return [pscustomobject]@{
        VaultName = $vaultName
    }
}

function Resolve-DeletedKeyVaultConflict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter(Mandatory)]
        [string]$Location
    )

    Write-Host "`n🧹 Found soft-deleted Key Vault blocking redeploy: $VaultName" -ForegroundColor Yellow
    Write-Host "  Purging deleted Key Vault entry so the deployment can continue..." -ForegroundColor Gray

    $purgeOutput = az keyvault purge --name $VaultName --location $Location 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $deletedVaultCount = az keyvault list-deleted --query "[?name=='$VaultName'] | length(@)" --output tsv 2>$null
        if ($purgeOutput -match 'DeletedVaultNotFound' -and $LASTEXITCODE -eq 0 -and $deletedVaultCount -eq '0') {
            Write-Host "  ℹ️  Deleted Key Vault entry is already gone. Waiting for Azure to release the name..." -ForegroundColor Yellow
            Start-Sleep -Seconds 20
            return $true
        }

        if (-not [string]::IsNullOrWhiteSpace($purgeOutput)) {
            Write-Host $purgeOutput.Trim() -ForegroundColor Red
        }
        return $false
    }

    $deadline = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 5
        $deletedVaultCount = az keyvault list-deleted --query "[?name=='$VaultName'] | length(@)" --output tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $deletedVaultCount -eq '0') {
            Write-Host "  ✅ Deleted Key Vault entry purged" -ForegroundColor Green
            Start-Sleep -Seconds 20
            return $true
        }
    } while ((Get-Date) -lt $deadline)

    Write-Host "  ⚠️  Purge request completed, but Azure has not removed the deleted vault entry yet." -ForegroundColor Yellow
    return $false
}

function Get-SreAgentProviderStatus {
    [CmdletBinding()]
    param()

    $providerRaw = az provider show --namespace Microsoft.App --output json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($providerRaw)) {
        return [pscustomobject]@{
            RegistrationState  = 'Unknown'
            HasAgentsResource  = $false
            SupportsPreviewApi = $false
            DefaultApiVersion  = ''
        }
    }

    try {
        $provider = $providerRaw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            RegistrationState  = 'Unknown'
            HasAgentsResource  = $false
            SupportsPreviewApi = $false
            DefaultApiVersion  = ''
        }
    }

    $agentsResource = $provider.resourceTypes | Where-Object { $_.resourceType -eq 'agents' } | Select-Object -First 1
    $apiVersions = @()
    if ($agentsResource -and $agentsResource.apiVersions) {
        $apiVersions = @($agentsResource.apiVersions)
    }

    return [pscustomobject]@{
        RegistrationState  = $provider.registrationState
        HasAgentsResource  = $null -ne $agentsResource
        SupportsPreviewApi = $apiVersions -contains '2025-05-01-preview'
        DefaultApiVersion  = if ($agentsResource -and $agentsResource.PSObject.Properties.Name -contains 'defaultApiVersion') { $agentsResource.defaultApiVersion } else { '' }
    }
}

# Banner
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    Azure SRE Agent Demo Lab Deployment                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  This script deploys:                                                        ║
║  • Azure Kubernetes Service (AKS) with multi-service demo app               ║
║  • Azure Container Registry                                                  ║
║  • Observability stack (Log Analytics, App Insights, Grafana)               ║
║  • Key Vault for secrets management                                         ║
║  • Azure SRE Agent for AI-powered diagnostics                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Verify prerequisites
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow

# Check Azure CLI
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Host "  ✅ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
}
catch {
    Write-Error "Azure CLI is not installed. Please install it from https://aka.ms/installazurecli"
    exit 1
}

# Check Bicep
try {
    $bicepVersion = az bicep version 2>&1
    Write-Host "  ✅ Bicep: $bicepVersion" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠️  Bicep not found, installing..." -ForegroundColor Yellow
    az bicep install
}

# Check login status
Write-Host "`n🔐 Checking Azure authentication..." -ForegroundColor Yellow
$account = az account show --output json 2>$null | ConvertFrom-Json

if (-not $account) {
    Write-Host "  Not logged in. Initiating device code authentication..." -ForegroundColor Yellow
    Write-Host "  This method works well in dev containers and codespaces." -ForegroundColor Gray
    az login --use-device-code
    $account = az account show --output json | ConvertFrom-Json
}

Write-Host "  ✅ Logged in as: $($account.user.name)" -ForegroundColor Green

Write-Host "`n🔎 Validating Azure subscription context..." -ForegroundColor Yellow
$null = az group list --subscription $account.id --query "[0].id" --output tsv 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "The current Azure context is not a usable subscription. Run 'az account set --subscription <subscription-id>' and retry."
    exit 1
}

Write-Host "  ✅ Subscription context is valid for ARM deployments" -ForegroundColor Green

Write-Host "  📋 Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

$deploySreAgent = -not $SkipSreAgent
$sreAgentSkipReason = ''

if ($deploySreAgent) {
    Write-Host "`n🤖 Checking Azure SRE Agent availability..." -ForegroundColor Yellow
    $sreAgentProvider = Get-SreAgentProviderStatus

    if ($sreAgentProvider.RegistrationState -ne 'Registered') {
        Write-Host "  Microsoft.App provider is not registered. Attempting registration..." -ForegroundColor Yellow
        az provider register --namespace Microsoft.App --wait --only-show-errors | Out-Null
        $sreAgentProvider = Get-SreAgentProviderStatus
    }

    if (-not $sreAgentProvider.HasAgentsResource -or -not $sreAgentProvider.SupportsPreviewApi) {
        $deploySreAgent = $false
        $sreAgentSkipReason = 'Microsoft.App/agents@2025-05-01-preview is not available for this subscription.'
        Write-Host "  ⚠️  $sreAgentSkipReason" -ForegroundColor Yellow
        Write-Host "      Continuing with core infrastructure deployment." -ForegroundColor Gray
    }
    else {
        $apiVersion = if ($sreAgentProvider.DefaultApiVersion) { $sreAgentProvider.DefaultApiVersion } else { '2025-05-01-preview' }
        Write-Host "  ✅ Microsoft.App/agents is available (API: $apiVersion)" -ForegroundColor Green
    }
}
else {
    $sreAgentSkipReason = 'Disabled by -SkipSreAgent.'
    Write-Host "`n🤖 Skipping Azure SRE Agent deployment (-SkipSreAgent)." -ForegroundColor Yellow
}

$deploySreAgentValue = if ($deploySreAgent) { 'true' } else { 'false' }

# Confirm subscription
Write-Host "`n⚠️  Resources will be deployed to subscription: $($account.name)" -ForegroundColor Yellow
if (-not $Yes) {
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Deployment cancelled." -ForegroundColor Red
        exit 0
    }
}
else {
    Write-Host "  ✅ Confirmation skipped (-Yes)" -ForegroundColor Gray
}

# Set variables
$resourceGroupName = "rg-$WorkloadName-$Location"
$deploymentName = "sre-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$bicepFile = Join-Path $PSScriptRoot "..\infra\bicep\main.bicep"
$parametersFile = Join-Path $PSScriptRoot "..\infra\bicep\main.bicepparam"

Write-Host "`n📦 Deployment Configuration:" -ForegroundColor Cyan
Write-Host "  • Location:        $Location" -ForegroundColor White
Write-Host "  • Workload Name:   $WorkloadName" -ForegroundColor White
Write-Host "  • Resource Group:  $resourceGroupName" -ForegroundColor White
Write-Host "  • Deployment Name: $deploymentName" -ForegroundColor White
Write-Host "  • SRE Agent:       $(if ($deploySreAgent) { 'Enabled' } else { 'Disabled' })" -ForegroundColor White
if ($sreAgentSkipReason) {
    Write-Host "  • SRE Agent Note:  $sreAgentSkipReason" -ForegroundColor Gray
}

# Validate template
Write-Host "`n🔍 Validating Bicep template..." -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "  Running what-if analysis..." -ForegroundColor Gray
    $whatIfOutput = az deployment sub what-if `
        --location $Location `
        --template-file $bicepFile `
        --parameters location=$Location workloadName=$WorkloadName deploySreAgent=$deploySreAgentValue `
        --name $deploymentName 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        Write-Host $whatIfOutput.Trim() -ForegroundColor Red
        Write-Error 'What-if analysis failed.'
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($whatIfOutput)) {
        Write-Host $whatIfOutput.Trim()
    }
    
    Write-Host "`n✅ What-if analysis complete. No changes were made." -ForegroundColor Green
    exit 0
}

# Deploy
Write-Host "`n🚀 Starting deployment..." -ForegroundColor Yellow
Write-Host "  This will take approximately 15-25 minutes." -ForegroundColor Gray

$startTime = Get-Date

try {
    $createCmd = @(
        "az deployment sub create",
        "--location $Location",
        "--template-file `"$bicepFile`"",
        "--parameters `"$parametersFile`" location=$Location workloadName=$WorkloadName deploySreAgent=$deploySreAgentValue",
        "--name $deploymentName",
        "--only-show-errors",
        "--output json"
    ) -join ' '

    $deployment = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $create = Invoke-AzCliJson -Command $createCmd

        if ($create.ExitCode -eq 0 -and $create.Json) {
            $deployment = $create.Json
            break
        }

        Write-Host "`nAzure CLI deployment command failed." -ForegroundColor Red
        if ($create.Raw) {
            Write-Host "Azure CLI output:`n$($create.Raw.Trim())" -ForegroundColor Red
        }

        # Best-effort: if a deployment record exists, pull structured error details.
        $showCmd = "az deployment sub show --name $deploymentName --output json"
        $show = Invoke-AzCliJson -Command $showCmd
        if ($show.ExitCode -eq 0 -and $show.Json) {
            $state = $show.Json.properties.provisioningState
            Write-Host "`nDeployment provisioningState: $state" -ForegroundColor Yellow
            if ($show.Json.properties.error) {
                Write-Host "`nDeployment error (structured):" -ForegroundColor Yellow
                Write-Host ($show.Json.properties.error | ConvertTo-Json -Depth 50) -ForegroundColor Yellow
            }
        }

        Write-SubscriptionDeploymentFailureSummary -DeploymentName $deploymentName -ResourceGroupName $resourceGroupName

        if ($attempt -eq 1) {
            $deletedKeyVaultConflict = Get-DeletedKeyVaultConflict -ResourceGroupName $resourceGroupName
            if ($deletedKeyVaultConflict) {
                $resolved = Resolve-DeletedKeyVaultConflict -VaultName $deletedKeyVaultConflict.VaultName -Location $Location
                if ($resolved) {
                    Write-Host "`n🔁 Retrying deployment after Key Vault purge..." -ForegroundColor Yellow
                    continue
                }
            }
        }

        throw "Deployment failed (see output above)."
    }

    if (-not $deployment) {
        throw "Deployment failed (see output above)."
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime

    Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host "   Duration: $($duration.Minutes) minutes $($duration.Seconds) seconds" -ForegroundColor Gray

    # Output deployment results
    Write-Host "`n📋 Deployment Outputs:" -ForegroundColor Cyan
    
    $outputs = $deployment.properties.outputs
    Write-Host "  • Resource Group:   $($outputs.resourceGroupName.value)" -ForegroundColor White
    Write-Host "  • AKS Cluster:      $($outputs.aksClusterName.value)" -ForegroundColor White
    Write-Host "  • AKS FQDN:         $($outputs.aksClusterFqdn.value)" -ForegroundColor White
    Write-Host "  • ACR Login Server: $($outputs.acrLoginServer.value)" -ForegroundColor White
    Write-Host "  • Key Vault URI:    $($outputs.keyVaultUri.value)" -ForegroundColor White
    Write-Host "  • Log Analytics ID: $($outputs.logAnalyticsWorkspaceId.value)" -ForegroundColor White
    Write-Host "  • App Insights ID:  $($outputs.appInsightsId.value)" -ForegroundColor White
    
    if ($outputs.grafanaDashboardUrl.value) {
        Write-Host "  • Grafana:          $($outputs.grafanaDashboardUrl.value)" -ForegroundColor White
        Write-Host "  • AMW ID:           $($outputs.azureMonitorWorkspaceId.value)" -ForegroundColor White
        Write-Host "  • Prometheus DCR:   $($outputs.prometheusDataCollectionRuleId.value)" -ForegroundColor White
    }

    if ($outputs.podRestartAlertId.value) {
        Write-Host "  • Alert (restarts): $($outputs.podRestartAlertId.value)" -ForegroundColor White
        Write-Host "  • Alert (HTTP 5xx): $($outputs.http5xxAlertId.value)" -ForegroundColor White
        Write-Host "  • Alert (failures): $($outputs.podFailureAlertId.value)" -ForegroundColor White
        Write-Host "  • Alert (crash/oom):$($outputs.crashLoopOomAlertId.value)" -ForegroundColor White
    }

    if ($outputs.defaultActionGroupId.value) {
        Write-Host "  • Action Group:     $($outputs.defaultActionGroupId.value)" -ForegroundColor White
        Write-Host "  • Incident Webhook: $($outputs.defaultActionGroupHasWebhook.value)" -ForegroundColor White
    }

    if ($outputs.sreAgentId.value) {
        Write-Host "  • SRE Agent:        $($outputs.sreAgentName.value)" -ForegroundColor White
        Write-Host "  • SRE Agent Portal: $($outputs.sreAgentPortalUrl.value)" -ForegroundColor White
    }
    elseif ($sreAgentSkipReason) {
        Write-Host "  • SRE Agent:        Skipped" -ForegroundColor Yellow
        Write-Host "  • Reason:           $sreAgentSkipReason" -ForegroundColor Gray
    }

    # Save outputs to file
    $outputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
    $deployment.properties.outputs | ConvertTo-Json -Depth 10 | Set-Content $outputsFile
    Write-Host "`n  📄 Outputs saved to: $outputsFile" -ForegroundColor Gray

}
catch {
    Write-Host "`n❌ Deployment failed!" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    exit 1
}

# Get AKS credentials
Write-Host "`n🔑 Getting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials `
    --resource-group $resourceGroupName `
    --name $outputs.aksClusterName.value `
    --overwrite-existing

Write-Host "  ✅ kubectl configured for cluster: $($outputs.aksClusterName.value)" -ForegroundColor Green

$sreAgentManagedIdentityPrincipalId = ''
if ($outputs.PSObject.Properties.Name -contains 'sreAgentManagedIdentityPrincipalId') {
    $sreAgentManagedIdentityPrincipalId = $outputs.sreAgentManagedIdentityPrincipalId.value
}

# Apply RBAC if not skipped
if (-not $SkipRbac) {
    Write-Host "`n🔐 Applying RBAC assignments..." -ForegroundColor Yellow
    Write-Host "  ⚠️  Note: If this fails due to subscription policies, run with -SkipRbac" -ForegroundColor Gray
    
    $rbacScript = Join-Path $PSScriptRoot "configure-rbac.ps1"
    if (Test-Path $rbacScript) {
        $rbacParams = @{
            ResourceGroupName = $resourceGroupName
        }

        if ($sreAgentManagedIdentityPrincipalId) {
            $rbacParams.SreAgentPrincipalId = $sreAgentManagedIdentityPrincipalId
            Write-Host "  ✅ Auto-detected SRE Agent managed identity principal ID" -ForegroundColor Green
        }
        elseif ($deploySreAgent) {
            Write-Host "  ⚠️  SRE Agent principal ID was not returned by the deployment. Agent-specific RBAC was skipped." -ForegroundColor Yellow
        }

        & $rbacScript @rbacParams
    }
    else {
        Write-Host "  ⚠️  RBAC script not found, skipping..." -ForegroundColor Yellow
    }
}

# Deploy application
Write-Host "`n📦 Deploying demo application to AKS..." -ForegroundColor Yellow
$k8sPath = Join-Path $PSScriptRoot "..\k8s\base\application.yaml"

if (Test-Path $k8sPath) {
    kubectl apply -f $k8sPath
    Write-Host "  ✅ Demo application deployed" -ForegroundColor Green
    
    Write-Host "`n⏳ Waiting for workloads to roll out..." -ForegroundColor Yellow
    $deploymentNamesRaw = kubectl get deployment -n pets -o jsonpath='{.items[*].metadata.name}' 2>$null
    $deploymentNames = @()
    if ($deploymentNamesRaw) {
        $deploymentNames = $deploymentNamesRaw -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    foreach ($deploymentName in $deploymentNames) {
        kubectl rollout status "deployment/$deploymentName" -n pets --timeout=300s 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ⚠️  Rollout still in progress for deployment/$deploymentName" -ForegroundColor Yellow
        }
    }
    
    # Wait for LoadBalancer IP
    Write-Host "⏳ Waiting for store-front external IP..." -ForegroundColor Yellow
    $maxWait = 120
    $waited = 0
    $storeUrl = $null
    while ($waited -lt $maxWait) {
        $externalIp = kubectl get svc store-front -n pets -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if ($externalIp) {
            $storeUrl = "http://$externalIp"
            break
        }
        Start-Sleep -Seconds 5
        $waited += 5
    }
    
    if ($storeUrl) {
        Write-Host "  ✅ Store Front URL: $storeUrl" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  Store Front external IP is still pending. Check again with: kubectl get svc store-front -n pets" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⚠️  Application manifest not found at: $k8sPath" -ForegroundColor Yellow
}

# Run validation
Write-Host "`n🔍 Running deployment validation..." -ForegroundColor Yellow
$validateScript = Join-Path $PSScriptRoot "validate-deployment.ps1"

if (Test-Path $validateScript) {
    & pwsh -NoLogo -NoProfile -File $validateScript -ResourceGroupName $resourceGroupName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠️  Validation found issues, but the infrastructure deployment completed. Review the validation output above." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⚠️  Validation script not found, skipping..." -ForegroundColor Yellow
}

if ($sreAgentSkipReason -and -not $outputs.sreAgentId.value) {
    Write-Host "`nℹ️  Azure SRE Agent was not deployed: $sreAgentSkipReason" -ForegroundColor Yellow
    Write-Host "   Re-run without -SkipSreAgent once Microsoft.App/agents is available in the subscription." -ForegroundColor Gray
}

# Configure SRE Agent (knowledge base, custom agents, connectors, scheduled tasks)
if ($outputs.sreAgentId.value) {
    Write-Host "`n🧠 Configuring SRE Agent (knowledge base, agents, connectors)..." -ForegroundColor Yellow
    $configureScript = Join-Path $PSScriptRoot "configure-sre-agent.ps1"
    if (Test-Path $configureScript) {
        try {
            & $configureScript -ResourceGroupName $resourceGroupName
            Write-Host "  ✅ SRE Agent configuration complete" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠️  SRE Agent configuration had issues: $_" -ForegroundColor Yellow
            Write-Host "      You can re-run it separately: .\scripts\configure-sre-agent.ps1 -ResourceGroupName $resourceGroupName" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  ⚠️  Configuration script not found. Run configure-sre-agent.ps1 manually." -ForegroundColor Yellow
    }
}

# Final instructions
$aksName = if ($outputs.aksClusterName.value) { $outputs.aksClusterName.value } else { "<check Azure Portal>" }
$siteUrlDisplay = if ($storeUrl) { $storeUrl } else { "kubectl get svc store-front -n pets" }

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                         Deployment Complete! 🎉                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Resources Deployed:                                                         ║
║    • AKS Cluster:    $($aksName.PadRight(44))║
║    • Store Front:    $($siteUrlDisplay.PadRight(44))║
║                                                                              ║
║  ℹ️  SRE Agent: See deployment output above for status                       ║
║    Portal: https://aka.ms/sreagent/portal                                    ║
║                                                                              ║
║  Quick Start (after SRE Agent setup):                                        ║
║    1. Open the store: $siteUrlDisplay
║    2. Break something: break-oom                                             ║
║    3. Refresh store to see failure                                           ║
║    4. Ask SRE Agent: "Why are pods crashing in the pets namespace?"         ║
║    5. Fix it: fix-all                                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

