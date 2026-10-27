# Tyk Observability on Kubernetes

Optional add-on for the [Self-Managed](../helm-self-managed/) and [Hybrid](../helm-hybrid/) Helm
deployments: an OpenTelemetry Collector, Prometheus, Alertmanager, Grafana, Tempo and Loki, with the
Tyk dashboards and alert rules. What it collects, the dashboards and the alerts are described in
[observability/README.md](../../observability/README.md).

## Prerequisites

- A Tyk install from [helm-self-managed](../helm-self-managed/) or [helm-hybrid](../helm-hybrid/)
  (or your own tyk-charts install)
- Helm 3.12+ or Helm 4, and `kubectl` (the post-renderer runs `kubectl kustomize`)
- About 3 GB of memory for the stack
- For log collection: a namespace that allows a root pod with a `hostPath` mount (the collector
  reads `/var/log/pods`); see [Production Considerations](#production-considerations)

## Files

| File                                | Purpose                                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------------------ |
| `values-kube-prometheus-stack.yaml` | Prometheus (with the Operator), Alertmanager and Grafana 13, only what Tyk needs                 |
| `values-tempo.yaml`                 | Tempo for traces                                                                                 |
| `values-loki.yaml`                  | Loki for logs                                                                                    |
| `values-otel-collector.yaml`        | The collector, as a DaemonSet in the Tyk namespace                                               |
| `assets.sh`                         | Prints the dashboards, alert rules, collector config and `tyk-otel-*` ConfigMaps as manifests     |
| `post-render.sh`                    | Helm post-renderer: gives the Tyk containers their `tyk-otel-*` ConfigMap as environment          |
| `plugin.yaml`                       | Wraps `post-render.sh` as a Helm 4 post-renderer plugin (`tyk-otel`)                             |
| `../helm-*/values-otel.yaml`        | Tyk chart overlay: JSON logs and access logs on the Gateway                                      |

Why the post-renderer: the Tyk charts have no `envFrom`, and layering a values file replaces
`extraEnvs` instead of adding to it. The post-renderer adds an optional ConfigMap to the Gateway,
Dashboard, Developer Portal and MDCB containers, so the OpenTelemetry settings come from the same
`observability/env` files as on Docker. Variables the chart sets itself win over the ConfigMap, which
is why the Gateway's log format and access logs are set in `values-otel.yaml`.

## Install

Run the commands from this folder. For Hybrid, use `tyk-dp` instead of `tyk` as the Tyk namespace.

### 1. Add the Chart Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

### 2. Install Prometheus, Grafana, Tempo and Loki

```bash
kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 92.0.0 \
  --namespace monitoring --values values-kube-prometheus-stack.yaml
helm install tempo grafana-community/tempo --version 3.1.0 \
  --namespace monitoring --values values-tempo.yaml
helm install loki grafana-community/loki --version 18.13.8 \
  --namespace monitoring --values values-loki.yaml
```

Keep the release names `tempo` and `loki`: Grafana and the collector use them as hostnames.
Grafana Labs moved the open-source Tempo and Loki charts to `grafana-community`; the `grafana/tempo`
chart is deprecated and `grafana/loki` is maintenance-only.

### 3. Apply the Tyk Assets

```bash
# Self-Managed (Tyk in namespace tyk)
./assets.sh | kubectl apply --server-side -f -

# Hybrid (Tyk in namespace tyk-dp)
TYK_NAMESPACE=tyk-dp ./assets.sh | kubectl apply --server-side -f -
```

This creates the dashboards and the alert rules (PrometheusRule) in `monitoring`, and the collector
config and `tyk-otel-*` ConfigMaps in the Tyk namespace. `assets.sh` does not contact the cluster, so
its output can also go into your GitOps repository. `--server-side` is needed: some dashboards are
too large for client-side apply.

### 4. Install the Collector

```bash
helm install otel-collector open-telemetry/opentelemetry-collector --version 0.175.1 \
  --namespace tyk --values values-otel-collector.yaml
```

### 5. Point Tyk at It

Add the overlay and the post-renderer to your Tyk install or upgrade. Helm 3 takes the script path,
as below. Helm 4 takes a post-renderer plugin instead: install this folder as one once, then pass its
name, `--post-renderer tyk-otel`, in place of `--post-renderer ./post-render.sh`:

```bash
# Helm 4 only, once
helm plugin install .
```

```bash
# Self-Managed
helm upgrade --install tyk tyk-helm/tyk-stack --version 5.4.0 \
  --namespace tyk \
  --values ../helm-self-managed/values.yaml \
  --values ../helm-self-managed/values-otel.yaml \
  --post-renderer ./post-render.sh

# Hybrid
helm upgrade --install tyk-dp tyk-helm/tyk-data-plane --version 5.4.0 \
  --namespace tyk-dp \
  --values ../helm-hybrid/values.yaml \
  --values ../helm-hybrid/values-otel.yaml \
  --post-renderer ./post-render.sh
```

Keep any other overlays you use (for example `values-openshift.yaml`).

### 6. Open Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3002:80
# http://localhost:3002, no login, folder "Tyk"
```

### 7. Verify

Send a few requests through the Gateway, then:

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
# From the repository root
observability/scripts/smoke-test.sh
observability/scripts/check-panels.py --show-empty
```

## Using Your Own Prometheus and Grafana

Skip step 2 and wire the pieces into what you run:

- **Prometheus Operator**: the collector's PodMonitor (step 4) and the PrometheusRules from
  `assets.sh` need your Prometheus to select them (by namespace and labels; add labels with
  `podMonitor.extraLabels` and to the PrometheusRule manifests).
- **Plain Prometheus**: install the collector with `--set podMonitor.enabled=false`, and apply the
  assets without the PrometheusRules: `ASSETS="dashboards collector env" ./assets.sh`. Scrape port
  `8889` of every collector pod (Kubernetes pod discovery, `honor_labels: true`): each pod only holds
  the metrics of the Tyk pods on its own node, so scraping the Service misses the others. Load
  `observability/rules/*.rules.yml` as rule files.
- **Grafana**: the dashboard ConfigMaps carry the `grafana_dashboard: "1"` label and a
  `grafana_folder: Tyk` annotation for the Grafana sidecar. Or import the JSON files from
  `observability/dashboards`. Each dashboard picks its datasources from variables; links between
  traces, logs and metrics expect the UIDs `tyk-prometheus`, `tyk-tempo` and `tyk-loki`.
- **Tempo and Loki elsewhere**: set `TEMPO_OTLP_ENDPOINT` and `LOKI_OTLP_ENDPOINT` in
  `values-otel-collector.yaml`.

## Sending to Another Backend

Pick a file from `observability/collector/exporters` (see
[Sending to Another Backend](../../observability/README.md#sending-to-another-backend)), then in
`values-otel-collector.yaml` replace `exporter-none.yaml` in `command.extraArgs` with
`exporter-<name>.yaml` and add its variables to `extraEnvs`, from a Secret for credentials:

```yaml
command:
  extraArgs:
    - --config=/etc/otelcol-tyk/logs-kubernetes.yaml
    - --config=/etc/otelcol-tyk/exporter-prometheus-remote-write.yaml
extraEnvs:
  - name: PROMETHEUS_REMOTE_WRITE_ENDPOINT
    value: https://mimir.example.com/api/v1/push
  - name: PROMETHEUS_REMOTE_WRITE_HEADERS
    valueFrom:
      secretKeyRef:
        name: tyk-remote-write
        key: headers
```

## Changing Settings

The components read the `tyk-otel-*` ConfigMaps when their pods start. After editing
`observability/env`, apply `assets.sh` again and restart the Tyk workloads (not the whole namespace:
the Self-Managed guide also runs PostgreSQL and Redis there):

```bash
./assets.sh | kubectl apply --server-side -f -

# Self-Managed (release tyk)
kubectl rollout restart -n tyk deployment/gateway-tyk-tyk-gateway \
  deployment/dashboard-tyk-tyk-dashboard statefulset/portal-tyk-tyk-dev-portal

# Hybrid (release tyk-dp)
kubectl rollout restart -n tyk-dp deployment/gateway-tyk-dp-tyk-gateway
```

If you set `gateway.kind` to `DaemonSet` or `StatefulSet`, use `daemonset/` or `statefulset/` for the
Gateway.

## Production Considerations

See the [production checklist](../../observability/README.md#production-checklist). On Kubernetes in
particular:

- **Pod security**: the collector runs as root with `hostPath` mounts to read the pod logs, which the
  `baseline` and `restricted` Pod Security levels reject. Label its namespace `privileged`, or run log
  collection in a separate namespace, or drop it (remove `logs-kubernetes.yaml` from `extraArgs`, set
  `presets.logsCollection.enabled: false` and remove `securityContext`). On OpenShift, grant the
  collector's service account an SCC that allows it.
- **Storage**: Tempo and Loki keep data on the pod (Loki on a 10Gi volume). Use persistent volumes or
  object storage, and give Prometheus a `storageSpec`.
- **Grafana**: expose it through an Ingress with authentication; turn anonymous Admin off and set
  `admin.existingSecret`.
- **Cluster monitoring**: `values-kube-prometheus-stack.yaml` turns off the cluster's own dashboards,
  rules and exporters. Turn them back on if this Prometheus should also watch the cluster.
- **Scale**: on large clusters, run the collector as a Deployment for OTLP and keep a DaemonSet for
  logs only.
- **Node coverage**: the collector Service only routes to the collector on the caller's node
  (`internalTrafficPolicy: Local`), so every node running Tyk needs a collector pod. The DaemonSet
  tolerates all taints for that reason; narrow `tolerations` or add a `nodeSelector` if you restrict it.
- **Workload names**: the post-renderer matches the charts' default names (`gateway-<release>-tyk-gateway`,
  ...). With a `fullnameOverride`, change the patterns in `post-render.sh`.
- **Gateway OpenTelemetry block**: leave `tyk-gateway.gateway.opentelemetry` disabled. It sets the
  resource name to `tyk`, and the dashboards and alerts expect the Gateway's default `tyk-gateway`.

## Troubleshooting

### No Tyk metrics in Prometheus

```bash
kubectl get podmonitor -n tyk
kubectl logs -n tyk daemonset/otel-collector-agent | grep -i error
```

Check Prometheus selects the PodMonitor (Status > Targets in Prometheus), and the Tyk pods have the
`tyk-otel-*` ConfigMaps in `envFrom` (`kubectl get deploy -n tyk -o yaml | grep tyk-otel`). If not,
the install was run without `--post-renderer`.

### Dashboards missing in Grafana

The Grafana sidecar watches ConfigMaps labelled `grafana_dashboard: "1"`:

```bash
kubectl get configmap -n monitoring -l grafana_dashboard=1
```

### Tempo logs "error calling scheduler ... no jobs found"

Harmless: Tempo 3's background worker polls for compaction work and logs this at error level while
there is none.

### Settings not applied

The ConfigMaps are read at pod start: restart the pods after applying `assets.sh`.

## Uninstall

```bash
helm uninstall otel-collector -n tyk
./assets.sh | kubectl delete -f -
helm uninstall loki tempo kube-prometheus-stack -n monitoring
```

Then run the Tyk upgrade again without `values-otel.yaml` and the post-renderer.
