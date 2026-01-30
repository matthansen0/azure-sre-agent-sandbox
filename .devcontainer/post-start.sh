#!/bin/bash
# =============================================================================
# Post-Start Script for Dev Container
# =============================================================================
# This script runs each time the dev container starts.
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Azure SRE Agent Demo Lab                                   ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                              ║"
echo "║  Quick Start:                                                                ║"
echo "║    1. azlogin                    - Login to Azure                            ║"
echo "║    2. ./scripts/deploy.ps1       - Deploy infrastructure                     ║"
echo "║    3. kubectl get pods -n pets   - Check application status                  ║"
echo "║                                                                              ║"
echo "║  Documentation: docs/SRE-AGENT-SETUP.md                                      ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check Azure login status
if az account show &>/dev/null; then
    ACCOUNT=$(az account show --query 'name' -o tsv)
    USER=$(az account show --query 'user.name' -o tsv)
    echo "✅ Azure: Logged in as $USER ($ACCOUNT)"
else
    echo "⚠️  Azure: Not logged in. Run 'azlogin' to authenticate."
fi

# Check kubectl config
if kubectl config current-context &>/dev/null; then
    CONTEXT=$(kubectl config current-context)
    echo "✅ Kubernetes: Context set to $CONTEXT"
else
    echo "ℹ️  Kubernetes: No context configured yet."
fi

echo ""
