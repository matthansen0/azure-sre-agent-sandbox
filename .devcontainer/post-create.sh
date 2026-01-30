#!/bin/bash
# =============================================================================
# Post-Create Script for Dev Container
# =============================================================================
# This script runs once when the dev container is created.
# It sets up the environment for Azure SRE Agent demo development.
# =============================================================================

set -e

echo "🔧 Setting up Azure SRE Agent Demo Lab dev container..."

# Install additional tools
echo "📦 Installing additional tools..."

# kubelogin for Azure AD authentication to AKS
curl -LO "https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-amd64.zip"
unzip -o kubelogin-linux-amd64.zip -d /tmp
sudo mv /tmp/bin/linux_amd64/kubelogin /usr/local/bin/
rm -f kubelogin-linux-amd64.zip

# k9s - Kubernetes CLI dashboard
curl -LO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
tar xzf k9s_Linux_amd64.tar.gz -C /tmp
sudo mv /tmp/k9s /usr/local/bin/
rm -f k9s_Linux_amd64.tar.gz

# kubectx and kubens for context switching
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx 2>/dev/null || true
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens

# Configure Git
echo "⚙️ Configuring Git..."
git config --global init.defaultBranch main
git config --global core.autocrlf input

# Set up Azure CLI defaults for device code authentication
echo "🔐 Configuring Azure CLI for device code authentication..."
mkdir -p ~/.azure
cat > ~/.azure/config << 'EOF'
[core]
collect_telemetry = yes
first_run = no

[defaults]
# Use device code authentication by default (works in containers/codespaces)
# Set AZURE_CLI_USE_DEVICE_CODE=true in environment or use --use-device-code flag

[cloud]
name = AzureCloud
EOF

# Create helpful aliases
echo "📝 Setting up shell aliases..."
cat >> ~/.bashrc << 'EOF'

# Azure SRE Agent Demo Lab aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get namespaces'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kctx='kubectx'
alias kns='kubens'

# Azure aliases
alias azlogin='az login --use-device-code'
alias azwho='az account show'
alias azsub='az account list -o table'

# Demo shortcuts
alias deploy='pwsh ./scripts/deploy.ps1'
alias destroy='pwsh ./scripts/destroy.ps1'
alias break-oom='kubectl apply -f k8s/scenarios/oom-killed.yaml'
alias break-crash='kubectl apply -f k8s/scenarios/crash-loop.yaml'
alias fix-all='kubectl apply -f k8s/base/application.yaml'

# Helpful functions
function kwatch() {
    kubectl get pods -n ${1:-pets} -w
}

function klogs() {
    kubectl logs -n ${2:-pets} -l app=$1 -f
}
EOF

# Same for PowerShell
mkdir -p ~/.config/powershell
cat > ~/.config/powershell/Microsoft.PowerShell_profile.ps1 << 'EOF'
# Azure SRE Agent Demo Lab PowerShell Profile

# Aliases
Set-Alias -Name k -Value kubectl

# Functions
function kgp { kubectl get pods @args }
function kgs { kubectl get svc @args }
function kgd { kubectl get deployments @args }
function kgn { kubectl get namespaces @args }

# Demo commands
function deploy { 
    param([string]$Location = "eastus2")
    & pwsh -File "./scripts/deploy.ps1" -Location $Location @args 
}

function destroy {
    param([string]$ResourceGroupName)
    if ($ResourceGroupName) {
        & pwsh -File "./scripts/destroy.ps1" -ResourceGroupName $ResourceGroupName @args
    } else {
        & pwsh -File "./scripts/destroy.ps1" @args
    }
}

function break-oom { kubectl apply -f k8s/scenarios/oom-killed.yaml }
function break-crash { kubectl apply -f k8s/scenarios/crash-loop.yaml }
function fix-all { kubectl apply -f k8s/base/application.yaml }

# Menu/help function
function menu {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    Azure SRE Agent Demo Lab                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Commands:                                                                   ║
║    az login --use-device-code  - Login to Azure                              ║
║    deploy                      - Deploy the infrastructure                   ║
║    destroy                     - Tear down the infrastructure                ║
║    menu                        - Show this help menu                         ║
║                                                                              ║
║  Kubernetes Shortcuts:                                                       ║
║    k, kgp, kgs, kgd, kgn       - kubectl aliases                             ║
║                                                                              ║
║  Break Scenarios:                                                            ║
║    break-oom                   - Apply OOM scenario                          ║
║    break-crash                 - Apply crash-loop scenario                   ║
║    fix-all                     - Restore healthy state                       ║
║                                                                              ║
║  Documentation: docs/                                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

# Welcome message (calls menu)
menu
EOF

# Create kubectl completion
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

echo "✅ Dev container setup complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Run 'azlogin' to authenticate to Azure"
echo "   2. Run 'deploy' to deploy the infrastructure"
echo "   3. See docs/SRE-AGENT-SETUP.md for SRE Agent configuration"
