# Tyk Install Agent Contract

## Purpose

Help someone deploy Tyk into their own environment, prove it works, and harden it for production,
using the deployment configurations in this repository.

This repository holds the deployment files, the tools in `tools/` and the guides in `docs/`. The
agent skills that drive a deployment (`tyk-deployment-planner`, `tyk-deployment-runner` and
`tyk-production-readiness`) are in the
[tyk-skills](https://github.com/TykTechnologies/tyk-skills) plugin, with the other Tyk skills.
Without them, follow this contract, `docs/topology-matrix.md` and the tools directly.

| Path | Use it for |
| --- | --- |
| `docs/topology-matrix.md` | Which deployment paths exist, their directories and status |
| `docs/prerequisites.md`, `tools/preflight.py` | What each platform needs, checked before anything starts |
| `docs/runtime.md`, `docs/bootstrap.md` | Starting, bootstrapping, upgrading and tearing down each path |
| `tools/verify_deployment.sh`, `docs/debugging.md` | Proving a deployment works, and what to read when it does not |
| `tools/profiles.py` | Production, performance, security and OpenShift guidance from the config files |

## What Is Free And What Needs A Licence

Open source (free, MPL 2.0): Tyk Gateway and Tyk Pump. Paid (licence key required): Tyk Dashboard,
Tyk Developer Portal, Tyk Operator and Tyk Multi Data Center Bridge (MDCB). A free trial licence
comes from <https://tyk.io/self-managed-trial/> and arrives by email. The canonical comparison is
<https://tyk.io/docs/apim>; state it that way and do not soften or extend it from memory. The open
source Gateway is `tykio/tyk-gateway`; the licensed build is `tykio/tyk-gateway-ee`, and using the
wrong one is the most common mistake on these paths.

## Deployment Runs

- Never invent a deployment path. `docs/topology-matrix.md` maps every supported combination to a real directory in this repository. If a request does not
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
- Run `tools/verify_deployment.sh` and include its output. On
  Kubernetes or OpenShift pass `--namespace` so component checks use `kubectl` rather than Docker,
  and `--stack` on a host running more than one Tyk stack so it cannot inspect the wrong one.
- Re-run configuration to show it is idempotent, and restart the stack to show state survives.
- When verification fails, read `docs/debugging.md` before
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

`tools/profiles.py` is the only thing that reads them. Use it
rather than restating the guidance from memory, so advice cannot drift from the configuration it
describes. It never edits a tracked file: `audit` reports, and `apply` writes an overlay.

`audit` is the mode to use, and it reads guidance on both active and commented-out settings.

`apply` generates the OpenShift overlay only. It refuses production, performance, and security
profiles: a commented-out value is frequently the current default shown for illustration rather
than a recommendation, and on Helm an overlay replaces a list instead of merging it, so a generated
`extraEnvs` deletes settings the base file had set — with `helm template` still exiting 0. Report
findings and hand back edits for a human to apply to a copy of the file.

`kubernetes/helm-self-managed/` and `kubernetes/helm-hybrid/` ship a committed
`values-openshift.yaml`. Prefer it over a generated overlay, and pass it on every `helm upgrade`.

## Versions

Component versions are pinned in each `.env.example` and in the Helm `values*.yaml` image tags,
and a workflow in the Tyk docs repository raises a pull request here on every release to keep
them at the latest stable tag. Read the pin from the file and never quote a version from memory.
Use the pinned versions unless the user asks otherwise, never mix a Gateway and Dashboard from
different minor releases, and record the versions actually deployed in any summary you produce.

## Verification

Run `python3 tools/check_topology_matrix.py` after adding, renaming or removing a deployment
directory: every path the topology matrix names must exist, and no `guidance-only` row may have
one. Do not claim completion if it fails; fix the failure or report the exact blocker.
