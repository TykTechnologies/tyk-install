#!/usr/bin/env bash
# Helm post-renderer for the AI Studio chart.
#
# The chart has no extraEnv or extra volumes for AI Studio, so settings such as
# CSRF_KEY, CORS_ALLOWED_ORIGINS or the gRPC TLS paths cannot be set through
# values. This adds, all optional (nothing breaks when they do not exist):
#   - ConfigMap tyk-ai-studio-extra and Secret tyk-ai-studio-extra as env for AI Studio
#   - Secret tyk-ai-studio-grpc-tls at /opt/tyk-ai-studio/certs/grpc (AI Studio)
#     and its tls.crt at /opt/tyk-microgateway/certs/grpc (Edge Gateway)
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
      name: tyk-ai-studio
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/envFrom/-
        value:
          configMapRef:
            name: tyk-ai-studio-extra
            optional: true
      - op: add
        path: /spec/template/spec/containers/0/envFrom/-
        value:
          secretRef:
            name: tyk-ai-studio-extra
            optional: true
      - op: add
        path: /spec/template/spec/volumes/-
        value:
          name: grpc-tls
          secret:
            secretName: tyk-ai-studio-grpc-tls
            optional: true
      - op: add
        path: /spec/template/spec/containers/0/volumeMounts/-
        value:
          name: grpc-tls
          mountPath: /opt/tyk-ai-studio/certs/grpc
          readOnly: true
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
