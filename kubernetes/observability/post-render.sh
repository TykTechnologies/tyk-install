#!/usr/bin/env bash
# Helm post-renderer for the Tyk charts (tyk-stack, tyk-data-plane, tyk-control-plane).
#
# The Tyk charts have no envFrom, and layering a values file replaces extraEnvs instead of
# adding to it. This adds one ConfigMap as env to each Tyk container, all optional (nothing
# changes when they do not exist):
#   tyk-otel-gateway    Gateway
#   tyk-otel-dashboard  Dashboard
#   tyk-otel-portal     Developer Portal
#   tyk-otel-mdcb       MDCB
# assets.sh builds them from observability/env. Variables the chart sets itself (values.yaml,
# extraEnvs) win over the ConfigMaps. Workloads are matched by the charts' default names
# (gateway-<release>-tyk-gateway, ...); a fullnameOverride needs the patterns below changed.
#
# Usage, Helm 3: helm upgrade --install ... --post-renderer ../observability/post-render.sh
# Usage, Helm 4: helm plugin install ../observability (once), then --post-renderer tyk-otel
# Needs kubectl (for kustomize).
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/all.yaml"
cat > "$tmp/kustomization.yaml" <<'EOF'
resources:
  - all.yaml
patches:
  - target:
      kind: Deployment
      name: gateway-.*-tyk-gateway
    patch: |-
      kind: Deployment
      metadata:
        name: gateway
      spec:
        template:
          spec:
            containers:
              - name: gateway-tyk-gateway
                envFrom:
                  - configMapRef:
                      name: tyk-otel-gateway
                      optional: true
  - target:
      kind: DaemonSet
      name: gateway-.*-tyk-gateway
    patch: |-
      kind: DaemonSet
      metadata:
        name: gateway
      spec:
        template:
          spec:
            containers:
              - name: gateway-tyk-gateway
                envFrom:
                  - configMapRef:
                      name: tyk-otel-gateway
                      optional: true
  - target:
      kind: StatefulSet
      name: gateway-.*-tyk-gateway
    patch: |-
      kind: StatefulSet
      metadata:
        name: gateway
      spec:
        template:
          spec:
            containers:
              - name: gateway-tyk-gateway
                envFrom:
                  - configMapRef:
                      name: tyk-otel-gateway
                      optional: true
  - target:
      kind: Deployment
      name: dashboard-.*-tyk-dashboard
    patch: |-
      kind: Deployment
      metadata:
        name: dashboard
      spec:
        template:
          spec:
            containers:
              - name: dashboard-tyk-dashboard
                envFrom:
                  - configMapRef:
                      name: tyk-otel-dashboard
                      optional: true
  - target:
      kind: StatefulSet
      name: portal-.*-tyk-dev-portal
    patch: |-
      kind: StatefulSet
      metadata:
        name: portal
      spec:
        template:
          spec:
            containers:
              - name: dev-portal-tyk-dev-portal
                envFrom:
                  - configMapRef:
                      name: tyk-otel-portal
                      optional: true
  - target:
      kind: Deployment
      name: mdcb-.*-tyk-mdcb
    patch: |-
      kind: Deployment
      metadata:
        name: mdcb
      spec:
        template:
          spec:
            containers:
              - name: mdcb-tyk-mdcb
                envFrom:
                  - configMapRef:
                      name: tyk-otel-mdcb
                      optional: true
EOF
kubectl kustomize "$tmp"
