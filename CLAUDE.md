@AGENTS.md

Claude-specific notes (the contract itself lives in AGENTS.md, imported above, so the two cannot
drift):

- Invoke the bundled skills as `/tyk-deployment-planner`, `/tyk-deployment-runner`, and
  `/tyk-production-readiness`, or let the skill descriptions trigger them.
- Working inside a clone of this repository is enough — no install step is required.
- To make the skills available from any directory, run `./install-plugin.sh --engine claude`,
  which links each skill into `${CLAUDE_CONFIG_DIR:-~/.claude}/skills`.
