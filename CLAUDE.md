@AGENTS.md

Claude-specific notes (the contract itself lives in AGENTS.md, imported above, so the two cannot
drift):

- The deployment skill, `tyk-deployment`, comes from the tyk-skills plugin:
  `claude plugin marketplace add TykTechnologies/tyk-skills` then
  `claude plugin install tyk-skills@tyk-skills`. Installed that way it is namespaced:
  `/tyk-skills:tyk-deployment`.
- Working inside a clone of this repository without the plugin is fine: follow AGENTS.md and run
  the tools in `tools/` directly.
