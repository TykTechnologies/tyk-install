# Prerequisites

Run `scripts/preflight.py --platform <docker|helm|openshift|baremetal>` rather than checking by
hand. It reports every gap with the command that fixes it, and exits non-zero so it can gate a
deployment.

**Always pass `--target <deployment dir>` on Docker.** Without it, preflight checks the union of
every Docker topology's ports — so it reports the Dashboard's 3000 and Postgres' 5432 as blockers
for an OSS deployment that binds neither. `--target` reads the ports from that directory's own
`.env.example` and checks only those. A false blocker is worse than none: it stops a planner that
is obeying "resolve every blocker" and pushes the user to kill unrelated services.

```bash
python3 skills/tyk-deployment-planner/scripts/preflight.py --platform docker --target docker/oss
python3 skills/tyk-deployment-planner/scripts/preflight.py --platform helm --namespace tyk
python3 skills/tyk-deployment-planner/scripts/preflight.py --platform docker \
  --licence TYK_LICENSE_KEY --env-file docker/self-managed/.env
```

## By platform

| Platform | Required | Optional |
| --- | --- | --- |
| Docker | `docker`, `docker compose`, `curl` | `jq`, `openssl`, `hurl`, `git` |
| Helm | `helm`, `kubectl`, `curl` | `jq`, `openssl`, `git` |
| OpenShift | `helm`, `kubectl`, `oc`, `curl` | `jq`, `openssl`, `git` |
| Bare metal | `curl`, plus a Linux host with systemd and apt or yum | `jq`, `openssl` |

`hurl` is needed only by `docker/getting-started/`, whose bootstrap is written as
`bootstrap.hurl`. It is not installed by default on most machines — `brew install hurl`.

`jq` is optional but worth having: without it, `verify_deployment.sh` cannot break the gateway's
`/hello` response down per component, so a partial failure is harder to see.

## Host ports

The Docker stacks bind these by default. `preflight.py` checks them and reports what is already
listening.

| Port | Used by |
| --- | --- |
| 8080 | Gateway |
| 3000 | Dashboard |
| 3001 | Developer Portal |
| 6379 | Redis |
| 5432 | PostgreSQL |
| 9091 | MDCB RPC (control plane) |

A local PostgreSQL is the usual collision on 5432. Either stop it, or override the host port —
each `.env.example` exposes the mapping, and the MDCB data plane deliberately uses a different
gateway port so it can run alongside a control plane on one host.

## Kubernetes

- A working cluster and a kubeconfig context. `preflight.py` echoes the current context so the
  target is visible before anything is installed — check it, since deploying to the wrong cluster
  is the easiest mistake to make here.
- A default StorageClass, for Redis and PostgreSQL persistence.
- Redis and PostgreSQL are **not** provided by the Tyk charts. Install them separately; each Helm
  README gives the Bitnami commands and pinned chart versions used for testing.
- An ingress controller, or use `kubectl port-forward` while evaluating.
- cert-manager, if the Tyk Operator is deployed.

## OpenShift

Everything above, plus:

- The `oc` CLI, and a user able to create Routes.
- Cluster-admin for the cert-manager install, if the Operator is used.
- The containers must not run as a fixed UID. Activate the bundled overlay rather than editing
  values by hand:

  ```bash
  python3 skills/tyk-production-readiness/scripts/profiles.py \
    apply kubernetes/helm-self-managed/values.yaml --profile openshift -o openshift-values.yaml
  ```

- Bitnami PostgreSQL needs SCC-compatible settings; the commented `--set` flags are in the Helm
  READMEs next to its install command. **Bitnami Redis needs them too, and the READMEs do not
  supply them** — a standalone Bitnami Redis sets `runAsUser` and needs `volumePermissions`
  disabled on OpenShift exactly as PostgreSQL does. Derive the flags from the Redis chart version
  you are installing and verify them before use; do not assume this repository has them.

## Licences

Free trials: https://tyk.io/sign-up/

| Variable | Needed for |
| --- | --- |
| `TYK_LICENSE_KEY` | Dashboard, on any Self-Managed or MDCB control plane |
| `TYK_PORTAL_LICENSE` | Developer Portal |
| `TYK_MDCB_LICENSE` | MDCB control plane |
| `TYK_OPERATOR_LICENSE` | standalone Operator |

Put values only in a gitignored `.env`, copied from the `.env.example` in the target directory.
`preflight.py --licence` reports presence only and never prints a value. Ask the user to supply
their own; do not copy one out of an unrelated deployment.

## Reference

- https://tyk.io/docs/tyk-self-managed#installation-options
- https://tyk.io/docs/planning-for-production
