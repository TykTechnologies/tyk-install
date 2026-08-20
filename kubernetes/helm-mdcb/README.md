# Tyk MDCB — Kubernetes / Helm

A self-managed control plane (`tyk-helm/tyk-control-plane`) and remote data planes
(`tyk-helm/tyk-data-plane`), bridged by MDCB over RPC.

For when MDCB is the right choice — and when it is not — see
[`../../docker/mdcb/README.md`](../../docker/mdcb/README.md#when-you-need-this). If someone wants
"HA Tyk" rather than multi-region, [`../helm-self-managed/`](../helm-self-managed/) is simpler and
usually correct.

For a Tyk Cloud control plane instead of a self-hosted one, use
[`../helm-hybrid/`](../helm-hybrid/) — the only real difference is who runs MDCB.

## Prerequisites

- Two clusters, usually. The control plane and each data plane are normally separate.
- `helm`, `kubectl`, a default StorageClass
- Redis and PostgreSQL for the control plane; Redis for each data plane. Neither is installed by
  the Tyk charts.
- Licences: `TYK_LICENSE_KEY` (Dashboard) and an MDCB licence. Data planes need neither.

```bash
python3 ../../skills/tyk-deployment-planner/scripts/preflight.py --platform helm --namespace tyk
```

## 1. Control plane

```bash
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ && helm repo update
kubectl create namespace tyk
kubectl config current-context      # confirm the target before installing
```

Dependencies first:

```bash
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis --namespace tyk \
  --set auth.enabled=false --version 19.0.2

helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set image.repository=bitnamilegacy/postgresql --namespace tyk \
  --set auth.username=tykuser --set auth.password=CHANGEME \
  --set auth.database=tyk_analytics \
  --set primary.persistence.size=20Gi --version 12.12.10

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n tyk --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n tyk --timeout=300s
```

Licences as a secret rather than plaintext in a values file:

```bash
kubectl create secret generic tyk-conf -n tyk \
  --from-literal=APISecret="$(openssl rand -hex 32)" \
  --from-literal=DashLicense="$TYK_LICENSE_KEY" \
  --from-literal=MDCBLicense="$TYK_MDCB_LICENSE"
```

Then set `global.secrets.useSecretName: tyk-conf` in `values-control-plane.yaml` and install:

```bash
helm upgrade --install tyk-cp tyk-helm/tyk-control-plane -n tyk --version 5.3.0 -f values-control-plane.yaml
kubectl get pods -n tyk
```

Verify MDCB is actually serving before touching a data plane:

```bash
kubectl logs -n tyk deploy/mdcb-tyk-cp-tyk-mdcb | tail -20
kubectl get svc -n tyk | grep mdcb
```

## 2. Expose MDCB to the data planes

Data planes are usually in a different cluster, so a `ClusterIP` will not reach them. MDCB speaks
gRPC on 9091 — an ingress in front of it must support gRPC.

```bash
kubectl patch svc mdcb-svc-tyk-cp-tyk-mdcb -n tyk -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc mdcb-svc-tyk-cp-tyk-mdcb -n tyk -o wide
```

Note the address; it becomes `global.remoteControlPlane.connectionString`.

## 3. Data plane

Collect the three identifiers from the control-plane Dashboard first —
[the Docker README explains where each comes from](../../docker/mdcb/README.md#2-collect-the-three-identifiers).

```bash
kubectl create namespace tyk-dp

kubectl create secret generic tyk-data-plane-conf -n tyk-dp \
  --from-literal=APISecret="$(openssl rand -hex 32)" \
  --from-literal=orgId="<organisation-id>" \
  --from-literal=userApiKey="<dashboard-user-api-key>" \
  --from-literal=groupID="<name-for-this-cluster>"

kubectl get secret tyk-data-plane-conf -n tyk-dp -o yaml   # confirm all four keys exist
```

The data plane needs its **own** Redis — not the control plane's:

```bash
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis --namespace tyk-dp \
  --set auth.enabled=false --version 19.0.2
```

Set `connectionString` in `values-data-plane.yaml` to the address from step 2, then:

```bash
helm upgrade --install tyk-dp tyk-helm/tyk-data-plane -n tyk-dp --version 5.3.0 -f values-data-plane.yaml
```

## 4. Verify the bridge

```bash
kubectl logs -n tyk-dp deploy/gateway-tyk-dp-tyk-gateway | grep -i rpc
kubectl port-forward -n tyk-dp svc/gateway-svc-tyk-dp-tyk-gateway 8081:8080 &
curl -s localhost:8081/hello | jq
```

Then prove it end to end: create an API on the control-plane Dashboard, tag it for this data
plane's group, and call it through 8081. An RPC connection with no APIs flowing is a group or
tagging problem, not connectivity.

Service names derive from the release name — confirm with `kubectl get svc` rather than assuming.

## Production and OpenShift

Both values files are annotated with `# PROD:`, `# PROD/PERFORMANCE:`, `# SECURITY:`, and
OpenShift overlay blocks. Generate overlays rather than editing them:

```bash
P=../../skills/tyk-production-readiness/scripts/profiles.py

python3 $P audit values-control-plane.yaml --profile prod --profile security
python3 $P audit values-data-plane.yaml    --profile prod --profile security

# OpenShift is the one profile safe to generate as an overlay
python3 $P apply values-data-plane.yaml --profile openshift -o dp-openshift.yaml
helm template check tyk-helm/tyk-data-plane -f values-data-plane.yaml -f dp-openshift.yaml
```

`apply` refuses prod/performance/security: a commented-out value is often an illustrative default
rather than a recommendation, and a Helm overlay replaces lists instead of merging them, so a
generated `extraEnvs` would delete base settings while `helm template` still exits 0. Act on the
`audit` output by editing a copy of the values file.

Install base first, then overlay.

### OpenShift Routes

```bash
oc expose svc dashboard-svc-tyk-cp-tyk-dashboard -n tyk --port=3000
oc expose svc gateway-svc-tyk-dp-tyk-gateway -n tyk-dp --port=8080
oc get routes -n tyk
```

Routes are HTTP; MDCB's RPC link needs a gRPC-capable path, so expose MDCB with a LoadBalancer or
a gRPC-aware ingress rather than a plain Route.

> On OpenShift Local (CRC), prefer `kubectl port-forward` — it avoids DNS configuration.

## Before production

Beyond the markers:

- **Enable the synchroniser** — `global.mdcbSynchronizer.enabled: true` on the control plane and
  the matching gateway setting on each data plane. Without it, data planes hold no keyspace copy,
  and surviving a control-plane outage is why you chose MDCB.
- **TLS on the RPC link**, which crosses a network boundary between sites. Set `useSSL: true` and
  `sslInsecureSkipVerify: false`.
- **Two or more MDCB replicas**, and two or more gateways per data plane.
- `APISecret: CHANGEME` and the Postgres password above are placeholders.
- No resource requests or limits are set in either file.

## Teardown

```bash
helm uninstall tyk-dp -n tyk-dp && kubectl delete namespace tyk-dp
helm uninstall tyk-cp -n tyk
helm uninstall tyk-redis -n tyk && helm uninstall tyk-postgres -n tyk
kubectl delete namespace tyk      # destroys PVCs
```

## Reference

- https://tyk.io/docs/tyk-multi-data-centre
- https://github.com/TykTechnologies/tyk-charts
- https://tyk.io/docs/planning-for-production
