# Tyk Install

This repository supports the Claude Code CLI, the Codex CLI, and any client that implements
[Agent Plugins](https://agent-plugins.org) 1.0.0.

The agent contract is maintained in a single place: read [AGENTS.md](AGENTS.md) and follow it
verbatim. Do not duplicate those rules here, so the two files cannot drift.

Claude-specific notes:

- Invoke the bundled skills as `/tyk-deployment-planner`, `/tyk-deployment-runner`, and
  `/tyk-production-readiness`, or let the skill descriptions trigger them.
- Working inside a clone of this repository is enough — no install step is required.
- To make the skills available from any directory, run `./install-plugin.sh --engine claude`,
  which links each skill into `${CLAUDE_CONFIG_DIR:-~/.claude}/skills`.
