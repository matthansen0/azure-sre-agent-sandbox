#!/usr/bin/env python3
"""Convert SRE Agent YAML spec to dataplane v2 API JSON.

Usage: python3 yaml-to-agent-json.py <yaml-file> [github-repo]
Outputs JSON to stdout suitable for PUT /api/v2/extendedAgent/agents/{name}
"""
import json
import sys
import yaml

def convert(yaml_path, github_repo=None):
    with open(yaml_path) as f:
        doc = yaml.safe_load(f)

    spec = doc.get("spec", doc)

    instructions = spec.get("system_prompt", spec.get("instructions", ""))
    if github_repo:
        instructions = instructions.replace("GITHUB_REPO_PLACEHOLDER", github_repo)

    tools = spec.get("tools", [])
    mcp_tools = spec.get("mcp_tools", [])
    handoffs = spec.get("handoffs", [])

    result = {
        "name": spec["name"],
        "type": "ExtendedAgent",
        "properties": {
            "instructions": instructions,
            "handoffDescription": spec.get("handoff_description", spec.get("handoffDescription", "")),
            "tools": tools,
            "mcpTools": mcp_tools,
            "handoffs": handoffs,
            "allowParallelToolCalls": spec.get("allow_parallel_tool_calls", False),
            "enableSkills": spec.get("enable_skills", True),
        },
    }

    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: yaml-to-agent-json.py <yaml-file> [github-repo]", file=sys.stderr)
        sys.exit(1)
    repo = sys.argv[2] if len(sys.argv) > 2 else None
    print(json.dumps(convert(sys.argv[1], repo)))
