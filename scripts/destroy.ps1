<#
.SYNOPSIS
    Tears down the Azure SRE Agent Demo Lab infrastructure.

.DESCRIPTION
    This script removes all Azure resources created by the deployment script.
    Use with caution - this action is irreversible!

.PARAMETER ResourceGroupName
    The resource group to delete. Default: rg-srelab-eastus2

.PARAMETER Force
    Skip confirmation prompt

.EXAMPLE
    .\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"

.EXAMPLE
    .\destroy.ps1 -Force
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ResourceGroupName = "rg-srelab-eastus2",

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    Azure SRE Agent Demo Lab - DESTROY                        ║
║                                                                              ║
║                         ⚠️  WARNING ⚠️                                        ║
║                                                                              ║
║  This will PERMANENTLY DELETE all resources in the resource group!           ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Red

# Check if resource group exists
$rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json

if (-not $rg) {
    Write-Host "❌ Resource group '$ResourceGroupName' not found." -ForegroundColor Yellow
    exit 0
}

Write-Host "📋 Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "📍 Location: $($rg.location)" -ForegroundColor White

# List resources
Write-Host "`n📦 Resources to be deleted:" -ForegroundColor Yellow
$resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
foreach ($resource in $resources) {
    Write-Host "   • $($resource.type) - $($resource.name)" -ForegroundColor Gray
}

$keyVaultNames = @($resources | Where-Object { $_.type -eq 'Microsoft.KeyVault/vaults' } | ForEach-Object { $_.name })

Write-Host "`n  Total: $($resources.Count) resources" -ForegroundColor White

# Confirmation
if (-not $Force) {
    Write-Host "`n⚠️  This action cannot be undone!" -ForegroundColor Red
    $confirm = Read-Host "Type 'DELETE' to confirm"
    
    if ($confirm -ne 'DELETE') {
        Write-Host "`nDestroy cancelled." -ForegroundColor Green
        exit 0
    }
}

# Delete resource group
Write-Host "`n🗑️  Deleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
Write-Host "   This may take several minutes..." -ForegroundColor Gray

$startTime = Get-Date

try {
    az group delete --name $ResourceGroupName --yes --no-wait
    
    Write-Host "`n✅ Resource group deletion initiated." -ForegroundColor Green
    Write-Host "   The deletion is running in the background." -ForegroundColor Gray
    Write-Host "   Check Azure Portal for status." -ForegroundColor Gray
    
} catch {
    Write-Host "`n❌ Failed to delete resource group: $_" -ForegroundColor Red
    exit 1
}

$groupDeleted = $false
if ($keyVaultNames.Count -gt 0) {
    Write-Host "`n🔐 Waiting for resource group deletion so Key Vault names can be purged..." -ForegroundColor Yellow
    $deadline = (Get-Date).AddMinutes(20)

    do {
        $groupExists = az group exists --name $ResourceGroupName --output tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $groupExists -eq 'false') {
            $groupDeleted = $true
            break
        }

        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    if ($groupDeleted) {
        Write-Host "  ✅ Resource group deleted" -ForegroundColor Green
        Write-Host "`n🧹 Purging deleted Key Vault records to avoid name conflicts on redeploy..." -ForegroundColor Yellow

        foreach ($keyVaultName in $keyVaultNames) {
            $deletedVaultFound = $false
            $vaultDeadline = (Get-Date).AddMinutes(5)

            do {
                $deletedCount = az keyvault list-deleted --query "[?name=='$keyVaultName'] | length(@)" --output tsv 2>$null
                if ($LASTEXITCODE -eq 0 -and $deletedCount -eq '1') {
                    $deletedVaultFound = $true
                    break
                }

                Start-Sleep -Seconds 5
            } while ((Get-Date) -lt $vaultDeadline)

            if (-not $deletedVaultFound) {
                Write-Host "   ⚠️  Deleted Key Vault entry not found for $keyVaultName; Azure may still be finalizing deletion." -ForegroundColor Yellow
                continue
            }

            $purgeOutput = az keyvault purge --name $keyVaultName --location $($rg.location) 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✅ Purged $keyVaultName" -ForegroundColor Green
            }
            else {
                Write-Host "   ⚠️  Failed to purge $keyVaultName" -ForegroundColor Yellow
                if (-not [string]::IsNullOrWhiteSpace($purgeOutput)) {
                    Write-Host "      $($purgeOutput.Trim())" -ForegroundColor Gray
                }
            }
        }
    }
    else {
        Write-Host "  ⚠️  Resource group deletion is still in progress. Key Vault purge was not attempted yet." -ForegroundColor Yellow
    }
}

# Clean up local files
Write-Host "`n🧹 Cleaning up local files..." -ForegroundColor Yellow

$outputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
if (Test-Path $outputsFile) {
    Remove-Item $outputsFile -Force
    Write-Host "   ✅ Removed deployment-outputs.json" -ForegroundColor Green
}

# Remove kubectl context
Write-Host "`n🔑 Cleaning up kubectl context..." -ForegroundColor Yellow
$aksName = "aks-*"  # Match any AKS cluster name pattern
kubectl config delete-context $aksName 2>$null
Write-Host "   ✅ kubectl context cleaned up" -ForegroundColor Green

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                        Cleanup Complete! 🧹                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  The resource group deletion has been submitted.                             ║
║  Monitor progress in Azure Portal or run:                                    ║
║                                                                              ║
║    az group show --name $($ResourceGroupName.PadRight(39))║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
