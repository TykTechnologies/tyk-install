---
name: tyk-deployment-planner
description: Choose and prepare a Tyk deployment before anything is created. Use when someone wants to install, deploy, evaluate, or stand up Tyk and the topology is not already decided — picking between OSS, Self-Managed, hybrid, MDCB, or AI Studio, between Docker, Kubernetes/Helm, OpenShift, or bare metal, and between a local trial and a production install. Checks prerequisites, resolves licences and versions, generates configuration overlays, and writes a deployment plan. Produces a plan only; it starts nothing.
---

# Tyk Deployment Planner

Decide what to deploy, confirm the machine can run it, and write the plan down. Applying the plan
is `tyk-deployment-runner`'s job — this skill creates nothing and starts nothing.

## Workflow

1. Establish what the user actually needs: which edition, which platform, local trial or
   production, and which licences they hold. Ask rather than assume when the answer changes the
   target directory.
2. Read `references/topology-matrix.md` and resolve the request to exactly one row. If nothing
   matches, say so and stop; do not improvise a deployment path.
3. Run `scripts/preflight.py` for the chosen platform, passing `--target <the row's directory>`
   on Docker so only that topology's ports are checked. Resolve every blocker before planning
   further, and report each with its remediation — but a port belonging to a component this row
   does not deploy is not a blocker. If preflight flags one, re-run with `--target` before telling
   the user anything is wrong.
4. Read `references/editions.md` when the edition itself is in question, and
   `references/versions.md` for the pinned component set.
5. Decide which profiles apply: `prod` and `performance` for anything not a laptop trial,
   `security` whenever the deployment outlives the session, `openshift` on OpenShift.
6. Run `profiles.py audit` for those profiles and record the findings in the plan. Generate an
   overlay only for `openshift` (see `## Configuration Overlays`). Never edit a tracked
   config file.
7. Write `deployment-plan.md` somewhere the user will keep it — see `## Where To Put The Plan`.

## Deployment Plan

`deployment-plan.md` must state:

- The chosen row, verbatim from the matrix, including its `bundled-tested` / `bundled` /
  `guidance-only` status.
- Target directory, components, and pinned versions.
- Licences required and which are present, by variable name only — never a value.
- Preflight results, including anything missing and how to install it.
- Profiles audited, the findings, and the path of any OpenShift overlay generated.
- The exact commands `tyk-deployment-runner` will run, in order.
- What will NOT be verified, and why.

A plan that omits the status or the unverifiable parts is not finished.

## Where To Put The Plan

Prefer a directory outside this repository. But the common case is a user who cloned this repo and
is working *inside* it, so "their working directory" and "this repository" are the same place. In
that case, in order of preference:

1. A path the user names when asked.
2. A sibling directory, e.g. `../tyk-deployment/` — outside the clone, next to it.
3. Inside the clone at `./.tyk-deploy/`, and tell the user it is untracked and why.

Whatever you choose, say where you put it, and never write into a path git tracks. Check with
`git check-ignore` or `git status` before writing if you are unsure.

## Configuration Overlays

```bash
# The OpenShift overlay is the one case that is safe to generate.
python3 ../tyk-production-readiness/scripts/profiles.py \
  apply kubernetes/helm-self-managed/values.yaml --profile openshift -o openshift-values.yaml
```

For production and performance, run `audit` instead and record the changes in the plan for a human
to make. `apply` refuses those profiles: a commented-out value is often an illustrative default
rather than a recommendation, and a Helm overlay replaces lists rather than merging them, so a
generated `extraEnvs` silently deletes base settings while `helm template` still exits 0.

Install with the base file first, then the overlay: `helm upgrade --install ... -f
kubernetes/helm-self-managed/values.yaml -f openshift-values.yaml`. The base stays untouched, so a
repo update never conflicts with a customer's choices.

Validate every generated overlay before handing it on, and confirm it did not *remove* anything —
`helm template` exits 0 on an overlay that silently replaced a list:

```bash
V=kubernetes/helm-self-managed/values.yaml
helm template check tyk-helm/tyk-stack -f $V                        | grep -c '\- name: TYK'
helm template check tyk-helm/tyk-stack -f $V -f openshift-values.yaml | grep -c '\- name: TYK'
```

The two counts must match.

`audit` findings whose recommendation is prose rather than a value need a human decision — surface
them in the plan instead of silently dropping them.

Resolve the sibling skill's directory rather than assuming a relative path: the skills may be
installed into an agent skills directory rather than read from this repository.

## References

- Read `references/topology-matrix.md` first, always. It is the only authority on which paths exist.
- Read `references/editions.md` for what OSS, Self-Managed, hybrid, MDCB, and AI Studio each
  include, and which licence each needs.
- Read `references/versions.md` for the pinned component versions and compatibility rules.
- Read `references/prerequisites.md` for what each platform requires and how to install it.
- Read `references/multi-site.md` before planning MDCB or anything described as multi-region,
  multi-data-centre, or "either site can fail". MDCB is asymmetric and does not by itself
  give two equal sites; that reference says what it does and does not cover.

## Safety

- Plan only. Do not run `docker compose up`, `helm install`, `kubectl apply`, or a package
  manager from this skill.
- Never write a licence, token, or password into the plan, a log, or a chat message. Name the
  variable instead.
- Never read licence values out of an unrelated deployment's `.env` to fill a gap. Ask the user.
- Echo the Docker or Kubernetes context and namespace in the plan so the user can see the target
  before anything touches it.
- Keep generated files out of version control. See `## Where To Put The Plan`; never add a plan or
  overlay to a tracked path.

## Completion Contract

Finish when the plan names one matrix row with its status, preflight has passed or every blocker
is reported with a remediation, the overlay validates, and the runner's commands are written out in
order. If the request maps to a `guidance-only` row, say plainly that no tested artifact exists
before the user spends time on it.
