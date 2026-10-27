#!/usr/bin/env bash
# Prints the Kubernetes manifests for the shared observability assets in ../../observability:
#   MONITORING_NAMESPACE (default monitoring):
#     a ConfigMap per Grafana dashboard (label grafana_dashboard=1, folder "Tyk"), for the Grafana sidecar
#     a PrometheusRule per alert rules file, for the Prometheus Operator
#   TYK_NAMESPACE (default tyk):
#     otel-collector and otel-collector-extra, the collector's configuration
#     tyk-otel-gateway, -dashboard, -portal and -mdcb, the components' OpenTelemetry settings (post-render.sh)
#
# ASSETS selects the parts, default "dashboards rules collector env". Without the Prometheus
# Operator, leave out "rules" (PrometheusRule needs its CRD) and load observability/rules directly.
#
# Usage: ./assets.sh | kubectl apply --server-side -f -
# Or write it to a file for GitOps. Needs kubectl; does not contact the cluster.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../observability" && pwd)"
tyk_ns="${TYK_NAMESPACE:-tyk}"
mon_ns="${MONITORING_NAMESPACE:-monitoring}"
assets=" ${ASSETS:-dashboards rules collector env} "
want() { [[ "$assets" == *" $1 "* ]]; }

want dashboards && for f in "$root"/dashboards/*.json; do
  name="$(basename "$f" .json)"
  echo "---"
  kubectl create configmap "grafana-dashboard-$name" -n "$mon_ns" --from-file="$name.json=$f" --dry-run=client -o yaml |
    kubectl label --local -f - grafana_dashboard=1 -o yaml |
    kubectl annotate --local -f - grafana_folder=Tyk -o yaml
done

want rules && for f in "$root"/rules/*.rules.yml; do
  name="$(basename "$f" .rules.yml)"
  printf -- '---\napiVersion: monitoring.coreos.com/v1\nkind: PrometheusRule\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n' "$name" "$mon_ns"
  sed -e '/^---$/d' -e 's/^/  /' "$f"
done

if want collector; then
  echo "---"
  kubectl create configmap otel-collector -n "$tyk_ns" --from-file=relay="$root/collector/config.yaml" --dry-run=client -o yaml

  extra=(--from-file=logs-kubernetes.yaml="$root/collector/logs-kubernetes.yaml")
  for f in "$root"/collector/exporters/*.yaml; do
    extra+=(--from-file="exporter-$(basename "$f")=$f")
  done
  echo "---"
  kubectl create configmap otel-collector-extra -n "$tyk_ns" "${extra[@]}" --dry-run=client -o yaml
fi

want env && for c in gateway dashboard portal mdcb; do
  echo "---"
  kubectl create configmap "tyk-otel-$c" -n "$tyk_ns" --from-env-file="$root/env/$c.env" --dry-run=client -o yaml
done
exit 0
