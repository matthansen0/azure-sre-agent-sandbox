#!/usr/bin/env python3
"""Validate the local SRE Agent governance contract and agent specifications."""

from pathlib import Path
import re
import sys

import yaml

ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = ROOT / "sre-config" / "governance" / "review-profile.yaml"
AGENTS_PATH = ROOT / "sre-config" / "agents"
SECRET_PATTERN = re.compile(r"(?i)(bearer\s+[A-Za-z0-9._-]+|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+)")


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"FAIL: {message}")


def main() -> int:
    failures: list[str] = []
    profile = yaml.safe_load(PROFILE_PATH.read_text())
    spec = profile.get("spec", {})

    if spec.get("enabled") is not False:
        fail("governance profile must remain disabled by default", failures)
    if spec.get("mode") != "Review":
        fail("governance profile must use Review mode", failures)
    if spec.get("autonomous_execution") is not False:
        fail("autonomous execution must remain disabled", failures)
    if spec.get("approval_required_for_writes") is not True:
        fail("writes must require explicit approval", failures)
    if spec.get("allowed_kubernetes_namespace") != "pets":
        fail("Kubernetes scope must be pets", failures)
    if not spec.get("secret_redaction_required"):
        fail("secret redaction must be required", failures)

    for agent_path in sorted(AGENTS_PATH.glob("*.yaml")):
        text = agent_path.read_text()
        agent = yaml.safe_load(text).get("spec", {})
        tools = set(agent.get("tools", []))
        mcp_tools = agent.get("mcp_tools", [])
        if agent.get("agent_type") == "Autonomous":
            print(f"WARN: {agent_path.name}: declares Autonomous; runtime profile must override or report unknown")
        if "RunAzCliWriteCommands" in tools and "RunAzCliWriteCommands" not in spec.get("allowed_write_tools", []):
            fail(f"{agent_path.name}: write tool is not allowed by governance profile", failures)
        if mcp_tools and not spec.get("allowed_kubernetes_namespace"):
            fail(f"{agent_path.name}: MCP tools lack a declared scope", failures)
        if SECRET_PATTERN.search(text):
            fail(f"{agent_path.name}: possible credential material found", failures)

    if failures:
        print(f"Governance validation failed with {len(failures)} finding(s).")
        return 1

    print("Governance contract passed static validation.")
    print("Runtime enforcement remains unknown until supported service-level policy hooks are exposed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
