# SRE Agent Capability Lab Implementation

Implementation branch: `feature/sre-agent-capability-lab`

The expanded sandbox work is tracked through focused issues. Optional
capabilities must remain independently disableable and must not block the core
AKS diagnosis demo.

| Issue | Workstream | Status |
|---|---|---|
| [#12](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/12) | Lab drift, documentation parity, and image pinning | Open |
| [#13](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/13) | Authoritative deployment/readiness validation | Open |
| [#14](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/14) | Idempotent SRE Agent setup and expected-state verification | Open |
| [#15](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/15) | Opt-in Azure Monitor automation profile | Open |
| [#16](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/16) | GitHub infrastructure/runbook RCA workflow | Open |
| [#17](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/17) | Optional Microsoft Learn MCP capability | Open |
| [#18](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/18) | Story-driven simulator and evidence reports | Open |
| [#19](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/19) | Governance profile for tools and remediation | Open |

Existing upstream limitation: [#3](https://github.com/matthansen0/azure-sre-agent-sandbox/issues/3)
tracks the unsupported incident-filter creation API. The current workaround is
portal configuration followed by verification; this branch does not attempt to
fake API support.

The GitHub track in this branch analyzes this repository's Bicep, Kubernetes,
scripts, runbooks, and SRE configuration. The deployed application source is
published in upstream container images and is intentionally out of scope.