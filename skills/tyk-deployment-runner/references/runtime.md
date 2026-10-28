# Runtime

Per-platform commands. Every path is relative to the repository root.

## Docker

```bash
cd docker/<target>
cp .env.example .env          # then fill in licence values; .env is gitignored
docker compose up -d
docker compose ps
docker compose logs -f tyk-gateway
```

Startup ordering is encoded in the Compose files with healthchecks and
`depends_on: condition: service_healthy`, so `up -d` handles it. Redis and PostgreSQL become
healthy, then the Dashboard, then the Gateway.

```bash
docker compose restart tyk-gateway   # reload after editing confs/*.env or apps/
docker compose down                  # stop, keep volumes
docker compose down -v               # stop and DESTROY data - confirm first
```

The Gateway reads API definitions and policies at startup. In OSS, editing a file under
`docker/oss/apps/` requires `docker compose restart tyk-gateway`; the mount is read-only, so the
Gateway will not rewrite it.

**`docker/getting-started/` is the exception to all of the above.** It has no `.env.example`, and
its `docker-compose.yml` is a small override fragment — one `httpbin` service — not a standalone
stack. `docker compose up -d` there deploys no Tyk at all. Use its script, which layers the
fragment over the self-managed stack:

```bash
# The licence goes in ../self-managed/.env -- see below for why
cp ../self-managed/.env.example ../self-managed/.env   # then fill in the licence
cd docker/getting-started && ./start.sh
```

For reference, that runs:
`docker compose -p tyk-getting-started -f ../self-managed/docker-compose.yml -f docker-compose.yml up -d`

**The licence goes in `docker/self-managed/.env`, not in `getting-started/`.** Compose takes its
project directory from the *first* `-f` file, so it reads `docker/self-managed/.env`. A `.env`
placed in `getting-started/` is silently ignored — verified: with one there, `compose config` still
warns `"TYK_LICENSE_KEY" variable is not set`; with one in `../self-managed/`, it does not.

Compose profiles gate optional components:

```bash
docker compose --profile analytics up -d   # adds Pump in docker/oss/
```

## Kubernetes (Helm)

```bash
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/
helm repo update

kubectl create namespace tyk
kubectl config current-context          # confirm the target BEFORE installing

# Redis and PostgreSQL are not part of the Tyk charts. The exact Bitnami
# commands and pinned chart versions are in each kubernetes/*/README.md.

helm upgrade --install tyk tyk-helm/<chart> -n tyk \
  -f kubernetes/<target>/values.yaml \
  -f <overlay>.yaml
```

`helm upgrade --install` is idempotent, which is what makes the idempotency check meaningful:
running it twice must report the same revision content.

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n tyk --timeout=300s
kubectl get pods -n tyk
kubectl logs -n tyk deploy/gateway-tyk-tyk-gateway -f
kubectl port-forward -n tyk svc/gateway-svc-tyk-tyk-gateway 8080:8080
```

Charts by edition: `tyk-oss`, `tyk-stack`, `tyk-data-plane`, `tyk-control-plane`, `tyk-operator`.

## OpenShift

As Helm, plus the SCC overlay and Routes instead of Ingress. Self-Managed and hybrid ship the
overlay; pass it on the install and on every later upgrade:

```bash
helm upgrade --install tyk tyk-helm/tyk-stack -n tyk --version 5.4.0 \
  -f kubernetes/helm-self-managed/values.yaml \
  -f kubernetes/helm-self-managed/values-openshift.yaml

oc expose svc gateway-svc-tyk-tyk-gateway -n tyk --port=8080
oc get routes -n tyk
```

For `helm-oss` and `helm-mdcb`, generate the overlay first:

```bash
python3 skills/tyk-production-readiness/scripts/profiles.py \
  apply kubernetes/helm-oss/values.yaml --profile openshift -o openshift-values.yaml
```

On OpenShift Local (CRC), prefer `kubectl port-forward` over Routes to avoid DNS setup.

## Observability add-on

Self-Managed and hybrid can export traces, metrics and logs over OpenTelemetry to a bundled
collector, Prometheus, Tempo, Loki and Grafana. It is an overlay, so the base stack is unchanged:

```bash
# Docker: from docker/self-managed or docker/hybrid
docker compose -f docker-compose.yml -f ../observability/docker-compose.otel.yml up -d

# Helm: add the values-otel.yaml overlay to the install command
helm upgrade --install tyk tyk-helm/tyk-stack -n tyk --version 5.4.0 \
  -f kubernetes/helm-self-managed/values.yaml -f kubernetes/helm-self-managed/values-otel.yaml
```

Read `docker/observability/README.md` or `kubernetes/observability/README.md` first; the
Kubernetes path installs the backends with its own charts and a post-renderer.

## MDCB ordering

The control plane must be serving RPC before any data plane starts, or the data plane's handshake
fails and it retries with backoff:

1. Control plane: Redis, PostgreSQL, Dashboard, MDCB.
2. Read the org ID, API key, and group ID from the control-plane Dashboard.
3. Data plane: its own local Redis, then the Gateway in RPC mode.

A data plane started early is not broken — it will connect once the control plane is up. Confirm
rather than assuming, with `check_rpc` in `scripts/verify_deployment.sh`.

## Bare metal

```bash
sudo ./baremetal/install.sh --components gateway,dashboard,pump
./baremetal/install.sh --dry-run --components gateway   # prints the plan, changes nothing
sudo systemctl status tyk-gateway
sudo journalctl -u tyk-gateway -f
./baremetal/verify.sh
```

Configuration is supplied as systemd `EnvironmentFile` drop-ins under `baremetal/confs/`, using
the same `TYK_GW_*` variables and the same marker comments as the Docker `confs/*.env`. Reload
after editing:

```bash
sudo systemctl daemon-reload && sudo systemctl restart tyk-gateway
```

## Upgrading

Always control plane before data planes, and never split Gateway and Dashboard minor versions.

```bash
# Docker: change the version in .env, then
docker compose pull && docker compose up -d

# Helm
helm upgrade tyk tyk-helm/<chart> -n tyk -f ... --version <chart-version>
```

Re-run `verify_deployment.sh` after any upgrade. An upgrade that leaves components healthy but
stops proxying is the failure mode worth catching.
