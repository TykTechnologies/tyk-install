# Tyk OSS (Open Source) — Kubernetes / Helm

The open source Tyk Gateway on Kubernetes via the `tyk-helm/tyk-oss` chart. No licence, no
Dashboard, no PostgreSQL.

For the differences between OSS and Self-Managed, see [`../../docker/oss/README.md`](../../docker/oss/README.md).

## Prerequisites

- A cluster and a kubeconfig context, plus `helm` and `kubectl`
- A default StorageClass, for Redis persistence
- Redis — **not** installed by this chart

```bash
python3 ../../skills/tyk-deployment-planner/scripts/preflight.py --platform helm --namespace tyk
```

`preflight.py` echoes the current context. Check it: installing into the wrong cluster is the
easiest mistake here.

## Install

```bash
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/
helm repo update
kubectl create namespace tyk
```

Redis first. These are the versions this configuration was tested against:

```bash
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis \
  --namespace tyk \
  --set auth.enabled=false \
  --version 19.0.2

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n tyk --timeout=300s
```

Then the Gateway:

```bash
helm upgrade --install tyk-oss tyk-helm/tyk-oss -n tyk --version 5.3.0 -f values.yaml
```

Pin `--version`. Without it `helm repo update` can move the chart under you, and the chart
version is independent of the Tyk component versions.

`helm upgrade --install` is idempotent — running it twice must produce the same result, which is
what makes the idempotency check meaningful.

## Verify

```bash
kubectl get pods -n tyk
kubectl port-forward -n tyk svc/gateway-svc-tyk-oss-tyk-gateway 8080:8080 &

curl -s localhost:8080/hello | jq
../../skills/tyk-deployment-runner/scripts/verify_deployment.sh --edition oss
```

Service names are derived from the release name; confirm with `kubectl get svc -n tyk` rather than
assuming.

## API definitions

OSS reads definitions from disk, so on Kubernetes they must come from a mount. Either:

- **A ConfigMap** mounted at the Gateway's `TYK_GW_APPPATH`. Simple, and version-controlled with
  the rest of your manifests.
- **The Tyk Operator**, managing APIs as Kubernetes custom resources. Set
  `global.components.operator: true`; it needs cert-manager and an Operator licence.

```bash
kubectl create configmap tyk-apis -n tyk --from-file=./apis/
```

Then mount it in an overlay via `tyk-gateway.gateway.extraVolumes` and `extraVolumeMounts`.

## Production and OpenShift

`values.yaml` is annotated with `# PROD:`, `# PROD/PERFORMANCE:`, `# SECURITY:`, and an OpenShift
overlay block. Generate an overlay rather than editing the file:

```bash
# What production would change
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  audit values.yaml --profile prod --profile security

# Generate the OpenShift overlay - the one profile that is safe to generate
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  apply values.yaml --profile openshift -o openshift-values.yaml
helm template check tyk-helm/tyk-oss -f values.yaml -f openshift-values.yaml
```

`apply` refuses `--profile prod`/`performance`/`security`. A commented-out setting here is often
the current default shown for illustration rather than a recommendation, and a Helm overlay
*replaces* a list rather than merging it — a generated `extraEnvs` would delete entries the base
file set, and `helm template` exits 0 regardless. Take the `audit` output and edit a copy of
`values.yaml` in place instead.

Install with the base file first, then any overlay, so a repository update never conflicts with
your choices:

```bash
helm upgrade --install tyk-oss tyk-helm/tyk-oss -n tyk -f values.yaml -f openshift-values.yaml
```

### OpenShift

The containers must not run as a fixed UID:

```bash
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  apply values.yaml --profile openshift -o openshift-values.yaml

helm upgrade --install tyk-oss tyk-helm/tyk-oss -n tyk -f values.yaml -f openshift-values.yaml
```

Bitnami Redis needs SCC-compatible settings too:

```bash
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis --namespace tyk \
  --set auth.enabled=false --version 19.0.2 \
  --set master.podSecurityContext.enabled=false \
  --set master.containerSecurityContext.enabled=false
```

#### OpenShift Routes

OpenShift uses Routes rather than Ingress. Routes are created with `oc` and get a hostname under
your cluster's `*.apps` domain.

```bash
oc expose svc gateway-svc-tyk-oss-tyk-gateway -n tyk --port=8080
oc get routes -n tyk
```

> On OpenShift Local (CRC), prefer `kubectl port-forward` — it avoids DNS configuration.

## Before production

Beyond the markers:

- `global.secrets.APISecret` ships as `CHANGEME`. It is the Gateway API credential — replace it,
  and prefer `useSecretName` over a plaintext value in the file.
- Redis is installed above as a single instance with authentication disabled. Neither is
  acceptable outside a throwaway cluster.
- `replicaCount: 1`. Gateways are stateless, so raise it and put a load balancer in front.
- No resource requests or limits are set. Without requests the scheduler cannot place pods
  sensibly; without limits one Gateway can starve its neighbours.

## Teardown

```bash
helm uninstall tyk-oss -n tyk
helm uninstall tyk-redis -n tyk
kubectl delete namespace tyk     # destroys PVCs
```

## Reference

- https://tyk.io/docs/tyk-oss-gateway
- https://github.com/TykTechnologies/tyk-charts
- https://tyk.io/docs/planning-for-production
