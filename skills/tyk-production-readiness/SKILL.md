---
name: tyk-production-readiness
description: Audit or harden a Tyk configuration against production guidance. Use when asked whether a Tyk deployment is production ready, to review a values.yaml or gateway env file before going live, to apply performance or scale tuning, to check Redis and Postgres placement, TLS, secrets, rate limiting, or analytics storage, or to prepare an OpenShift overlay. Reads the production, performance, security, and OpenShift guidance this repository already carries as annotated config, so recommendations cannot drift from the configuration they describe.
---

# Tyk Production Readiness

Report what a Tyk configuration should change before it carries real traffic, and optionally write
the overlay that changes it. Works on any config the user already has, so it is useful to someone
who never used the other skills.

## Where The Guidance Lives

Every tuning decision in this repository is already written down, as a marker comment beside the
setting it applies to:

```bash
TYK_GW_LOGLEVEL=info # PROD: Set to "error" to reduce log volume
# TYK_GW_MAXIDLECONNSPERHOST=10000 # PROD/PERFORMANCE: Set high value (>=10000)
TYK_GW_SECRET=352d... # SECURITY: Change to a strong 32+ character string
```

`scripts/profiles.py` is the only thing that reads them. Use it instead of recalling Tyk
production advice from memory: the guidance stays in the files engineers already maintain, so it
cannot go stale, and every finding cites a `file:line` the user can open.

Marker families map to profiles: `# PROD:` → `prod`, `# PROD/PERFORMANCE:` → both `prod` and
`performance`, `# SECURITY:` → `security`, and `# Required for deploying on RedHat OpenShift`
blocks → `openshift`.

## Workflow

1. Identify the files to review. On a Helm path that is **both** `kubernetes/<target>/values.yaml`
   **and** its sibling `.env.example` — the credentials live in the latter and the values file only
   references them, so auditing just the file the user named misses every secret. Otherwise
   `docker/*/confs/*.env`, `baremetal/confs/*.env`, or a file the user supplies.
2. `profiles.py list <files>` to see what guidance each file carries.
3. `profiles.py audit <files> --profile prod` (add `performance`, `security`) for the findings.
4. Read `references/hardening.md` for what the markers do not cover: topology, HA, backups, and
   the checks that are not expressible as a single setting.
5. Report findings using the three buckets in `## Reporting` — that is the grouping, and it is the
   one the completion contract checks. Order the buckets' contents worst-first, and lead the whole
   report with anything from `## Reporting`'s always-call-out list, since those outrank marker
   findings.
6. If asked to change things, hand back edits to a copy of the file. Do not generate a
   production overlay — `apply` refuses, for the reasons in `## Applying` below.

```bash
python3 scripts/profiles.py list  kubernetes/helm-self-managed/values.yaml
python3 scripts/profiles.py audit kubernetes/helm-self-managed/values.yaml --profile prod --profile security
python3 scripts/profiles.py apply kubernetes/helm-self-managed/values.yaml --profile openshift -o openshift-values.yaml
```

## Reporting

Separate three cases, because they need different actions:

- **Already correct** — guidance is satisfied. Say so briefly; do not pad the report.
- **Needs changing** — guidance the config does not satisfy. Report the setting, its `file:line`,
  and the guidance text verbatim. Do **not** infer a value from a commented-out placeholder: those
  are frequently the current default shown for illustration, so the commented value is often the
  opposite of what the advice says.
- **Needs a decision** — guidance whose recommendation is prose rather than a value
  (`# TYK_GW_HOSTNAME= # PROD: Set to a domain name`), or a number that needs sizing work. Carry
  these into the report as decisions the user owes.

Always call out, regardless of markers:

- Committed development secrets: `TYK_GW_SECRET` and `TYK_GW_NODESECRET` ship with the same
  hardcoded value, and Postgres and Redis ship with default passwords. Any deployment that is not
  a local throwaway must replace them.
- Single-instance Redis or Postgres, which is a data-loss risk rather than a tuning gap.
- A gateway control API sharing a port with API traffic.

## Applying

**`apply` generates the OpenShift overlay only, and refuses everything else.** Two reasons, both
found by generating an overlay and then checking what it actually did:

1. A commented-out setting does not reliably carry the *recommended* value. Many are the current
   default shown for illustration, so activating them emits the opposite of their own advice —
   `# TYK_GW_ENABLESEPERATEANALYTICSSTORE=false # PROD/PERFORMANCE: Set to true` becomes `false`.
   Nothing in the file distinguishes an illustrative value from a recommended one.
2. On Helm, an overlay **replaces** a list rather than merging it. A generated `extraEnvs` therefore
   deletes every entry the base file set — 23 variables in `helm-self-managed`, including the
   Dashboard security block and the Portal CSRF setting. `helm template` exits 0 either way, so it
   does **not** guard against this.

So for production work: report findings, and hand the user edits to make to a copy of the values
file, preserving its existing lists. Never present a generated production overlay as hardened.

The OpenShift overlay is exempt: those blocks are genuine "uncomment to use" recommendations and
graft as new mappings the base file does not define, so neither problem applies. Before generating
one, check whether the target directory already ships `values-openshift.yaml`
(`kubernetes/helm-self-managed/` and `kubernetes/helm-hybrid/` do, for tyk-charts 5.4.0 or later)
and prefer that. When you do generate one, validate it and check the env-var count is unchanged:

```bash
python3 scripts/profiles.py apply kubernetes/helm-self-managed/values.yaml \
  --profile openshift -o openshift-values.yaml
helm template check tyk-helm/tyk-stack -f kubernetes/helm-self-managed/values.yaml -f openshift-values.yaml
```

## References

- Read `references/hardening.md` for topology, HA, TLS, backup, and upgrade concerns that no
  single setting expresses.
- Read `references/sizing.md` for gateway, Redis, and Postgres sizing and scaling guidance.
- Read `tyk-deployment-planner/references/topology-matrix.md` when a finding implies a different
  topology rather than a different value.

## Safety

- Never edit a tracked config file. Hand back edits for a copy of it, or generate the OpenShift
  overlay.
- Never print a secret's value, including one you are flagging as weak. Name the variable and cite
  its `file:line`.
- Do not report a configuration as production ready. Report which guidance it satisfies and which
  it does not — the judgement belongs to the person who owns the service.
- Do not invent thresholds. If the repository's guidance gives no number and
  `references/hardening.md` gives none, say the number needs sizing work and cite
  <https://tyk.io/docs/planning-for-production>.

## Completion Contract

Finish when every file in scope has been audited — including the sibling `.env.example` on a Helm
path — findings are grouped into already-correct, needs-changing, and needs-a-decision with a
`file:line` for each, committed development secrets and single-instance datastores are called out
explicitly, and any generated OpenShift overlay has been validated with `helm template` and shown
not to reduce the rendered environment-variable count.
