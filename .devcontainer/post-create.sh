#!/bin/bash
# =============================================================================
# Post-Create Script for Dev Container
# =============================================================================
# This script runs once when the dev container is created.
# It sets up the environment for Azure SRE Agent demo development.
# =============================================================================

set -e

echo "🔧 Setting up Azure SRE Agent Demo Lab dev container..."

# Ensure Python + PyYAML are available for scripts/yaml-to-agent-json.py
echo "🐍 Ensuring Python and PyYAML are available..."
if ! command -v python3 &> /dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq python3 python3-pip
fi
python3 -m pip install --user --quiet pyyaml || python3 -m pip install --break-system-packages --quiet pyyaml

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
alias kgp='kubectl get pods -n pets'
alias kgs='kubectl get svc -n pets'
alias kgd='kubectl get deployments -n pets'
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

# Break scenarios
alias break-oom='kubectl apply -f k8s/scenarios/oom-killed.yaml'
alias break-crash='kubectl apply -f k8s/scenarios/crash-loop.yaml'
alias break-image='kubectl apply -f k8s/scenarios/image-pull-backoff.yaml'
alias break-cpu='kubectl apply -f k8s/scenarios/high-cpu.yaml'
alias break-pending='kubectl apply -f k8s/scenarios/pending-pods.yaml'
alias break-probe='kubectl apply -f k8s/scenarios/probe-failure.yaml'
alias break-network='kubectl apply -f k8s/scenarios/network-block.yaml'
alias break-config='kubectl apply -f k8s/scenarios/missing-config.yaml'
alias break-mongodb='kubectl apply -f k8s/scenarios/mongodb-down.yaml'
alias break-service='kubectl apply -f k8s/scenarios/service-mismatch.yaml'

# Fix commands
alias fix-all='kubectl apply -f k8s/base/application.yaml'
alias fix-network='kubectl delete networkpolicy deny-order-service -n pets 2>/dev/null'
alias fix-extras='kubectl delete deployment cpu-stress-test resource-hog unhealthy-service misconfigured-service -n pets 2>/dev/null'

# Site URL command
alias site='echo "Store Front: http://$(kubectl get svc store-front -n pets -o jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" 2>/dev/null || echo "pending...")"'
# SRE Agent portal
alias sre-agent='echo "SRE Agent Portal: https://aka.ms/sreagent/portal"'
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
function kgp { kubectl get pods -n pets @args }
function kgs { kubectl get svc -n pets @args }
function kgd { kubectl get deployments -n pets @args }
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
function break-image { kubectl apply -f k8s/scenarios/image-pull-backoff.yaml }
function break-cpu { kubectl apply -f k8s/scenarios/high-cpu.yaml }
function break-pending { kubectl apply -f k8s/scenarios/pending-pods.yaml }
function break-probe { kubectl apply -f k8s/scenarios/probe-failure.yaml }
function break-network { kubectl apply -f k8s/scenarios/network-block.yaml }
function break-config { kubectl apply -f k8s/scenarios/missing-config.yaml }
function break-mongodb { kubectl apply -f k8s/scenarios/mongodb-down.yaml }
function break-service { kubectl apply -f k8s/scenarios/service-mismatch.yaml }
function fix-all { kubectl apply -f k8s/base/application.yaml }
function fix-network { kubectl delete networkpolicy deny-order-service -n pets 2>$null }
function fix-extras { kubectl delete deployment cpu-stress-test resource-hog unhealthy-service misconfigured-service -n pets 2>$null }

# Site URL command  
function site { 
    $ip = kubectl get svc store-front -n pets -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ip) { Write-Host "Store Front: http://$ip" -ForegroundColor Green } 
    else { Write-Host "Store Front IP not ready yet..." -ForegroundColor Yellow }
}

# SRE Agent portal
function sre-agent {
    Write-Host "SRE Agent Portal: https://aka.ms/sreagent/portal" -ForegroundColor Cyan
}

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
║    site                        - Show the store front URL                    ║
║    sre-agent                   - Show SRE Agent portal URL                   ║
║    menu                        - Show this help menu                         ║
║                                                                              ║
║  Kubernetes Shortcuts (default namespace: pets):                             ║
║    kgp, kgs, kgd               - Get pods/services/deployments               ║
║                                                                              ║
║  Break Scenarios:                                                            ║
║    break-oom                   - OOMKilled (order-service)                   ║
║    break-crash                 - CrashLoopBackOff (product-service)          ║
║    break-image                 - ImagePullBackOff (makeline-service)         ║
║    break-cpu                   - High CPU (new stress pod)                   ║
║    break-pending               - Pending pods (insufficient resources)       ║
║    break-probe                 - Liveness probe failure                      ║
║    break-network               - Network policy blocking                     ║
║    break-config                - Missing ConfigMap                           ║
║    break-mongodb               - MongoDB down (cascading failure)            ║
║    break-service               - Service selector mismatch                   ║
║                                                                              ║
║  Fix Commands:                                                               ║
║    fix-all                     - Restore all services to healthy state       ║
║    fix-network                 - Remove network policy                       ║
║    fix-extras                  - Delete extra broken deployments             ║
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
