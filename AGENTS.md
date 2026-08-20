# Tyk Install Agent Contract

## Purpose

Help someone deploy Tyk into their own environment, prove it works, and harden it for production,
using the deployment configurations in this repository.

Both the Codex CLI and the Claude Code CLI are supported, along with any client implementing
[Agent Plugins](https://agent-plugins.org) 1.0.0. Invoke a skill with `$name` on Codex or `/name`
on Claude Code. Shared skill files reference sibling skills by plain name only.

## Skills

| Skill | Use it when |
| --- | --- |
| `tyk-deployment-planner` | Choosing a topology, checking prerequisites, resolving configuration. Produces a plan; applies nothing. |
| `tyk-deployment-runner` | Starting a deployment, bootstrapping it, and proving it works. |
| `tyk-production-readiness` | Auditing or hardening a config against this repository's production guidance. |

## Deployment Runs

- Never invent a deployment path. `skills/tyk-deployment-planner/references/topology-matrix.md`
  maps every supported combination to a real directory in this repository. If a request does not
  map to a row, say so.
- Report a path's status honestly. `bundled-tested` means it is verified end to end,
  `bundled` means the artifacts exist, `guidance-only` means documentation without a tested
  artifact. Never present `guidance-only` as though an artifact exists.
- Confirm the target before changing it. Echo the Docker context or the Kubernetes context and
  namespace, and what will be created, before creating it.
- Treat an existing deployment as someone else's. Do not delete, upgrade, or reconfigure resources
  the user did not ask you to touch, and never reuse a namespace or project without asking.
- Prefer this repository's committed configuration over generating your own. When a value must
  change, write an overlay rather than editing a tracked file.

## Evidence

- Never report a deployment as working without an executable result. Component health is not
  enough on its own: prove a request reaches an upstream through the gateway.
- Run `skills/tyk-deployment-runner/scripts/verify_deployment.sh` and include its output. On
  Kubernetes or OpenShift pass `--namespace` so component checks use `kubectl` rather than Docker,
  and `--stack` on a host running more than one Tyk stack so it cannot inspect the wrong one.
- Re-run configuration to show it is idempotent, and restart the stack to show state survives.
- When verification fails, read `skills/tyk-deployment-runner/references/debugging.md` before
  changing anything, and report the actual error rather than a summary of it.
- If a step could not be verified, say which one and why. An unverified path is reported as
  unverified, never as done.

## Secrets

- Licences, tokens, and generated credentials belong only in a gitignored `.env`. `.env.example`
  is the tracked template and must never contain a real value.
- Never print a licence, token, API key, or password, and never write one into a file this
  repository tracks, a log, a commit message, or a chat message. Refer to them by variable name.
- Ask the user to supply licence values themselves. Do not read them out of another customer's
  environment or another deployment's `.env`.
- The Postgres and Redis passwords, `TYK_GW_SECRET`, and `TYK_GW_NODESECRET` committed here are
  development defaults. Flag them for any deployment that is not a local throwaway.

## Production Guidance

Production and platform guidance lives in the config files themselves, as marker comments next to
the setting each applies to: `# PROD:`, `# PROD/PERFORMANCE:`, `# SECURITY:`, and the
`# Required for deploying on RedHat OpenShift` blocks.

`skills/tyk-production-readiness/scripts/profiles.py` is the only thing that reads them. Use it
rather than restating the guidance from memory, so advice cannot drift from the configuration it
describes. It never edits a tracked file: `audit` reports, and `apply` writes an overlay.

`audit` is the mode to use, and it reads guidance on both active and commented-out settings.

`apply` generates the OpenShift overlay only. It refuses production, performance, and security
profiles: a commented-out value is frequently the current default shown for illustration rather
than a recommendation, and on Helm an overlay replaces a list instead of merging it, so a generated
`extraEnvs` deletes settings the base file had set — with `helm template` still exiting 0. Report
findings and hand back edits for a human to apply to a copy of the file.

## Versions

Component versions are pinned in each `.env.example` and in the Helm READMEs. Use the pinned
versions unless the user asks otherwise, and never mix a Gateway and Dashboard from different
minor releases. Record the versions actually deployed in any summary you produce.

## Verification

Run `./install-plugin.sh --check` after changing plugin structure, and
`python3 validate_plugins.py` to check Agent Plugins conformance and that every path named in the
topology matrix exists. Do not claim completion if either fails; fix the failure or report the
exact blocker.
