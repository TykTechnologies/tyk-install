#!/usr/bin/env bash
# Helm post-renderer for the AI Studio chart: mounts the gRPC CA into the Edge Gateway.
#
# The Edge Gateway reads the CA for AI Studio's gRPC certificate only from a file
# (EDGE_TLS_CA_PATH), and its subchart cannot mount extra volumes. This mounts tls.crt
# from Secret tyk-ai-studio-grpc-tls at /opt/tyk-microgateway/certs/grpc (optional:
# nothing breaks when the Secret does not exist). Not needed when the gRPC certificate
# chains to a CA in the system roots. Everything for AI Studio itself is set with chart
# values (values-production.yaml).
#
# Usage, Helm 3: helm upgrade --install ... --post-renderer ./post-render.sh
# Usage, Helm 4: helm plugin install . (once), then --post-renderer tyk-ai-studio
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
      name: tyk-ai-studio-microgateway
    patch: |-
      - op: add
        path: /spec/template/spec/volumes/-
        value:
          name: grpc-tls-ca
          secret:
            secretName: tyk-ai-studio-grpc-tls
            optional: true
            items:
              - key: tls.crt
                path: tls.crt
      - op: add
        path: /spec/template/spec/containers/0/volumeMounts/-
        value:
          name: grpc-tls-ca
          mountPath: /opt/tyk-microgateway/certs/grpc
          readOnly: true
EOF

kubectl kustomize "$tmp"
