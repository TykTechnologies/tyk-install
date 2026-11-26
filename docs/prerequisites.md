# Prerequisites

Run `tools/preflight.py --platform <docker|helm|openshift|baremetal>` rather than checking by
hand. It reports every gap with the command that fixes it, and exits non-zero so it can gate a
deployment.

**Always pass `--target <deployment dir>` on Docker.** Without it, preflight checks the union of
every Docker topology's ports — so it reports the Dashboard's 3000 and Postgres' 5432 as blockers
for an OSS deployment that binds neither. `--target` reads the ports from that directory's own
`.env.example` and checks only those. A false blocker is worse than none: it stops a planner that
is obeying "resolve every blocker" and pushes the user to kill unrelated services.

```bash
python3 tools/preflight.py --platform docker --target docker/oss
python3 tools/preflight.py --platform helm --namespace tyk
python3 tools/preflight.py --platform docker \
  --licence TYK_LICENSE_KEY --env-file docker/self-managed/.env
```

## By platform

| Platform | Required | Optional |
| --- | --- | --- |
| Docker | `docker`, `docker compose`, `curl` | `jq`, `openssl`, `git` |
| Helm | `helm`, `kubectl`, `curl` | `jq`, `openssl`, `git` |
| OpenShift | `helm`, `kubectl`, `oc`, `curl` | `jq`, `openssl`, `git` |
| Bare metal | `curl`, plus a Linux host with systemd and apt or yum | `jq`, `openssl` |

`jq` is optional but worth having: without it, `verify_deployment.sh` cannot break the gateway's
`/hello` response down per component, so a partial failure is harder to see.

## Host ports

The Docker stacks bind these by default. `preflight.py --target` checks the ones its directory
declares and reports what is already listening.

| Port | Used by | Variable in `.env` |
| --- | --- | --- |
| 8080 | Gateway (OSS, Self-Managed, hybrid, MDCB control plane) | `GATEWAY_PORT` |
| 3000 | Dashboard | `DASHBOARD_PORT` |
| 3001 | Developer Portal | `PORTAL_PORT` |
| 6379 | Redis | `REDIS_PORT` |
| 5432 | PostgreSQL | `POSTGRES_PORT` |
| 9091 | MDCB RPC (MDCB control plane) | `MDCB_PORT` |
| 8081, 6380 | MDCB data plane Gateway and Redis | `GATEWAY_PORT`, `REDIS_PORT` |
| 4000 | AI Studio admin UI and REST API | `STUDIO_PORT` |
| 9090 | AI Studio embedded AI Gateway | `AI_GATEWAY_PORT` |
| 9091 | AI Studio Edge Gateway | `EDGE_GATEWAY_PORT` |
| 5433 | AI Studio PostgreSQL | `POSTGRES_PORT` |
| 3002 | Grafana (observability overlay) | fixed in `docker/observability/docker-compose.yml` |
| 9090, 9093 | Prometheus, Alertmanager (observability overlay) | fixed |
| 4317, 4318 | OpenTelemetry Collector OTLP gRPC and HTTP (observability overlay) | fixed |

Two collisions are built in: the AI Studio Edge Gateway and MDCB both default to 9091, and the AI
Studio embedded gateway and the observability overlay's Prometheus both default to 9090. Change
one side's variable to run them on the same host.

A local PostgreSQL is the usual collision on 5432. Either stop it, or override the host port in
`.env`; every stack's `.env.example` exposes its mapping except the observability overlay. The MDCB
data plane deliberately uses different ports so it can run alongside a control plane on one host.

## Kubernetes

- A working cluster and a kubeconfig context. `preflight.py` echoes the current context so the
  target is visible before anything is installed — check it, since deploying to the wrong cluster
  is the easiest mistake to make here.
- A default StorageClass, for Redis and PostgreSQL persistence.
- Redis and PostgreSQL are **not** provided by the Tyk charts. Install them separately; each Helm
  README gives the Bitnami commands and pinned chart versions.
- An ingress controller, or use `kubectl port-forward` while evaluating.
- cert-manager, if the Tyk Operator is deployed.
- Kubernetes 1.34 or 1.35 when the Operator is deployed: those are the versions the Operator
  1.6.0 release notes list as compatible (tyk-charts 5.5.0 bundles it).
- For the Operator's Kubernetes Gateway API support: the Gateway API CRDs from the experimental
  channel of v1.6.2, applied with `kubectl apply --server-side` by a cluster admin, before the
  feature is turned on. With the flag on and the CRDs missing, the operator exits at startup.

## OpenShift

Everything above, plus:

- The `oc` CLI, and a user able to create Routes.
- Cluster-admin for the cert-manager install, if the Operator is used.
- The containers must not run as a fixed UID. Layer the committed overlay rather than editing
  values by hand — `kubernetes/helm-self-managed/values-openshift.yaml` and
  `kubernetes/helm-hybrid/values-openshift.yaml` exist for that (tyk-charts 5.4.0 or later). For
  `helm-oss` and `helm-mdcb`, generate one:

  ```bash
  python3 tools/profiles.py \
    apply kubernetes/helm-oss/values.yaml --profile openshift -o openshift-values.yaml
  ```

- Bitnami PostgreSQL needs SCC-compatible settings; the commented `--set` flags are in the Helm
  READMEs next to its install command. **Bitnami Redis needs them too, and the READMEs do not
  supply them** — a standalone Bitnami Redis sets `runAsUser` and needs `volumePermissions`
  disabled on OpenShift exactly as PostgreSQL does. Derive the flags from the Redis chart version
  you are installing and verify them before use; do not assume this repository has them.

## Licences

Free trials: <https://tyk.io/self-managed-trial/>

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

- <https://tyk.io/docs/tyk-self-managed#installation-options>
- <https://tyk.io/docs/planning-for-production>
