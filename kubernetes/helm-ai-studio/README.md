# Tyk AI Studio Kubernetes Install - Quick Guide

Deploys Tyk AI Studio 2.2.1 (control plane), an Edge Gateway (data plane) and PostgreSQL with the
Helm chart from the [Tyk AI Studio repository](https://github.com/TykTechnologies/ai-studio/tree/main/helm).

> The chart is named `midsommar`, and the Edge Gateway is still called `microgateway` in the
> chart values and image names. This guide uses "Edge Gateway" for the same component.

## Prerequisites

- Kubernetes cluster running, `kubectl` configured and connected
- Helm 3 or Helm 4, and `git`
- `openssl` to generate secrets
- Enterprise Edition only: a Tyk AI license key
- Ingress + TLS only: an Ingress controller and cert-manager

## Files

| File                     | Purpose                                                              |
| ------------------------ | -------------------------------------------------------------------- |
| `.env.example`           | Chart version, license and secrets, loaded into the shell            |
| `values.yaml`            | Community Edition, ClusterIP services, internal PostgreSQL           |
| `values-enterprise.yaml` | Overlay: Enterprise images (`tyk-ai-studio-ent`, `tyk-microgateway-ent`) |
| `values-ingress.yaml`    | Overlay: Ingress + TLS for AI Studio and the Edge Gateway             |
| `values-rag.yaml`        | Optional: Reranker and Transformer Server                            |
| `values-production.yaml` | Optional: production settings (gRPC TLS, metrics token)              |
| `studio-extra.env.example` | Optional: production settings the chart cannot set               |
| `post-render.sh`         | Applies `studio-extra.env` and the gRPC TLS secret to the release    |
| `plugin.yaml`            | Helm 4 plugin that runs `post-render.sh` (name: `tyk-ai-studio`)     |
| `presidio.yaml`          | Optional: Microsoft Presidio for PII Guardrails (Enterprise)         |

The optional pieces are described in [Optional Components](#optional-components).

---

## Quick Start

### 1. Configure Environment

```bash
cd kubernetes/helm-ai-studio
cp .env.example .env
```

Generate the secrets and paste them into `.env`:

```bash
openssl rand -hex 16   # TYK_AI_SECRET_KEY
openssl rand -hex 16   # MICROGATEWAY_ENCRYPTION_KEY
openssl rand -hex 16   # GRPC_AUTH_TOKEN
openssl rand -hex 16   # POSTGRES_PASSWORD
```

Keep `POSTGRES_PASSWORD` to letters and digits: the chart puts it into the connection URL without escaping.

Set `TYK_AI_LICENSE` only for the Enterprise Edition. Then load the variables:

```bash
set -a; source .env; set +a
```

### 2. Get the Chart

The chart is not published to a Helm repository. Clone it at the release tag:

```bash
git clone --depth 1 --branch $AI_STUDIO_VERSION https://github.com/TykTechnologies/ai-studio.git
helm dependency build ai-studio/helm
```

### 3. Install

Install the release as `tyk-ai-studio`. `values.yaml` sets `fullnameOverride: tyk-ai-studio`, and
the Edge Gateway reaches AI Studio at `<release>:50051`, so the two names must match.

```bash
helm upgrade --install tyk-ai-studio ./ai-studio/helm \
  --namespace tyk-ai --create-namespace \
  --values values.yaml \
  --set config.tykAiSecretKey=$TYK_AI_SECRET_KEY \
  --set config.grpcAuthToken=$GRPC_AUTH_TOKEN \
  --set config.microgatewayEncryptionKey=$MICROGATEWAY_ENCRYPTION_KEY \
  --set config.tykAiLicense=$TYK_AI_LICENSE \
  --set database.password=$POSTGRES_PASSWORD \
  --set microgateway.secrets.edgeAuthToken=$GRPC_AUTH_TOKEN \
  --set microgateway.secrets.encryptionKey=$MICROGATEWAY_ENCRYPTION_KEY \
  --set microgateway.secrets.tykAiLicense=$TYK_AI_LICENSE
```

For the Enterprise Edition, add `--values values-enterprise.yaml` after `--values values.yaml`.

Use a dedicated namespace: the chart selects its PostgreSQL and Edge Gateway pods with the plain
labels `app: postgres` and `app: microgateway`.

Wait for the pods (~2 minutes):

```bash
kubectl wait --for=condition=available deploy --all -n tyk-ai --timeout=300s
kubectl get pods -n tyk-ai
```

On the first install, AI Studio restarts until PostgreSQL is ready, and the Edge Gateway restarts
until the AI Studio gRPC server is ready. This is expected.

### 4. Access Services

Port-forward in two terminals. `values.yaml` already uses these URLs for `siteUrl` and the
display URLs.

```bash
kubectl port-forward -n tyk-ai svc/tyk-ai-studio 8080:8080
```

```bash
kubectl port-forward -n tyk-ai svc/tyk-ai-studio-microgateway 9091:8080
```

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:9091/health
```

| Service             | URL                     | Description                              |
| ------------------- | ----------------------- | ---------------------------------------- |
| AI Studio           | `http://localhost:8080` | Admin UI and REST API                    |
| Edge Gateway        | `http://localhost:9091` | AI Gateway for Apps                      |
| Embedded AI Gateway | port `9090` on `svc/tyk-ai-studio` | Gateway built into AI Studio  |

### 5. First Login

1. Open `http://localhost:8080` and select **Sign up**. The first user becomes the administrator.
2. Go to **Settings → Secrets** and fill in `OPENAI_KEY` / `ANTHROPIC_KEY`.
3. Go to **AI Portal → Edge Gateways**. The Edge Gateway shows as **Connected**, with the pod name
   as its Edge ID. Select **Push Configuration**.

The password needs an uppercase letter, a lowercase letter, a number and a special character,
for example `ChangeMe123!`.

---

## Ingress and TLS

1. Install cert-manager:

   ```bash
   helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
     --version v1.21.2 \
     --namespace cert-manager \
     --create-namespace \
     --set crds.enabled=true
   ```

2. Create a `ClusterIssuer` named `letsencrypt-prod` (or change `certManager.issuer` in
   `values-ingress.yaml`). See the [cert-manager ACME docs](https://cert-manager.io/docs/configuration/acme/).
3. Replace `studio.example.com` and `gateway.example.com` in `values-ingress.yaml`, point DNS at
   your Ingress controller, and rerun the install command with
   `--values values-ingress.yaml` added after `--values values.yaml`.

The overlay sets `devMode: "false"` (session cookies need HTTPS) and leaves the display URLs
empty, so the chart derives them from the Edge Gateway Ingress host.

For an external database, set `database.internal=false` and
`database.url=postgres://user:password@host:5432/tyk_ai_studio?sslmode=require`.

---

## Optional Components

The [Kubernetes install docs](https://tyk.io/docs/ai-management/ai-studio/deployment-k8s) list the
Reranker and Transformer Server as optional components,
[Guardrails](https://tyk.io/docs/ai-management/ai-studio/guardrails) can use
Microsoft Presidio, and the reference architecture lists production settings. Pick what you need;
each part adds to the install command from step 3.

### The Post-Renderer

The AI Studio chart (2.2.1) has no way to add environment variables or volumes to AI Studio.
Its configmap ignores settings such as `CORS_ALLOWED_ORIGINS`, `PLUGIN_BLOCK_INTERNAL_URLS` or the
gRPC certificate paths.
`post-render.sh` fills that gap at install time. It adds to AI Studio:

- ConfigMap `tyk-ai-studio-extra` and Secret `tyk-ai-studio-extra` as environment variables
- Secret `tyk-ai-studio-grpc-tls` as files, for the gRPC control connection (the Edge Gateway gets
  its `tls.crt`)

All three are optional, so the post-renderer is safe to use without them. It needs `kubectl`
(for `kubectl kustomize`). To use it with Helm 3, add this to the install command:

```bash
  --post-renderer ./post-render.sh
```

Helm 4 does not run scripts as post-renderers, only plugins. Install this folder as a plugin once,
then add its name to the install command instead:

```bash
helm plugin install .
```

```bash
  --post-renderer tyk-ai-studio
```

Create the ConfigMap from your copy of `studio-extra.env.example`. Remove the sections you do not
use:

```bash
cp studio-extra.env.example studio-extra.env
kubectl create configmap tyk-ai-studio-extra -n tyk-ai \
  --from-env-file=studio-extra.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

After you change it later, restart AI Studio:

```bash
kubectl rollout restart deployment/tyk-ai-studio -n tyk-ai
```

### Reranker and Transformer Server

Add `--values values-rag.yaml`.

| Service                         | API                   | Purpose                                       |
| ------------------------------- | --------------------- | --------------------------------------------- |
| `tyk-ai-studio-reranker:80`     | `POST /rerank`        | Scores text pairs (model `BAAI/bge-reranker-large`) |
| `tyk-ai-studio-transformer:8000` | `POST /v1/embeddings` | OpenAI-compatible embeddings from any sentence-transformers model |

- Both images only publish a `latest` tag and download their models from Hugging Face on first
  use, so the pods need internet access. The first request can take several minutes.
- The reranker needs about 2.5 GiB of memory. `values-rag.yaml` sets a 4 GiB limit.
- AI Studio does not call either service on its own. To embed with the Transformer Server, create a
  standalone **Embedder** with API compatibility `openai`, endpoint
  `http://tyk-ai-studio-transformer:8000/v1` and a model such as
  `sentence-transformers/all-MiniLM-L6-v2`.
- The chart's own defaults point at `midsommar/...` images that do not exist; `values-rag.yaml`
  sets the `tykio/...` images.

### Microsoft Presidio (PII Guardrails)

Guardrails are an Enterprise feature. The built-in pattern library can already redact PII with
nothing to deploy. Presidio adds entity recognition, for example of names and places.

```bash
kubectl apply -n tyk-ai -f presidio.yaml
```

In a Guardrail filter, choose the **Microsoft Presidio** provider and set:

- **Analyzer URL**: `http://presidio-analyzer:3000`
- **Anonymizer URL** (optional): `http://presidio-anonymizer:3000`

Do not set `LLM_UPSTREAM_BLOCK_INTERNAL=true` without allowing these hosts in
`LLM_UPSTREAM_ALLOWED_INTERNAL_HOSTS`: Guardrail providers follow the same outbound rules as LLM
upstreams.

### Production Settings

From the AI Studio reference architecture. `values-production.yaml` turns on TLS for the gRPC
control connection and protects `/metrics`; `studio-extra.env` adds the settings the chart cannot
set.

1. Create a certificate for the gRPC control connection. Its name must match the AI Studio service,
   `tyk-ai-studio`. A self-signed certificate works, because the Edge Gateway trusts the
   certificate from the same Secret. With your own CA, put the CA in a separate file and adjust
   `EDGE_TLS_CA_PATH`.

   ```bash
   mkdir -p grpc-tls
   openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 365 \
     -subj "/CN=tyk-ai-studio" \
     -addext "subjectAltName=DNS:tyk-ai-studio,DNS:tyk-ai-studio.tyk-ai.svc,DNS:tyk-ai-studio.tyk-ai.svc.cluster.local" \
     -keyout grpc-tls/tls.key -out grpc-tls/tls.crt

   kubectl create secret tls tyk-ai-studio-grpc-tls -n tyk-ai \
     --cert=grpc-tls/tls.crt --key=grpc-tls/tls.key
   ```

2. Create the Secret for sensitive settings. `METRICS_AUTH_TOKEN` is needed on both AI Studio and
   the Edge Gateway; `CSRF_KEY` keeps logins valid across restarts.

   ```bash
   kubectl create secret generic tyk-ai-studio-extra -n tyk-ai \
     --from-literal=CSRF_KEY=$(openssl rand -hex 16) \
     --from-literal=METRICS_AUTH_TOKEN=$(openssl rand -hex 16)
   ```

3. Set `CORS_ALLOWED_ORIGINS` in `studio-extra.env` to the AI Studio URL, keep the production
   section, and create the ConfigMap.
4. Add `--values values-production.yaml --post-renderer ./post-render.sh` to the install command
   (on Helm 4, `--post-renderer tyk-ai-studio` after `helm plugin install .`).

AI Studio then logs `gRPC TLS enabled`, the Edge Gateway loads `EDGE_TLS_CA_PATH` and connects,
and `/metrics` answers `401` without `Authorization: Bearer <METRICS_AUTH_TOKEN>`.

Also for production: use `values-ingress.yaml`, an external PostgreSQL, and never set
`EDGE_SKIP_TLS_VERIFY` or `EDGE_ALLOW_INSECURE=true` on Edge Gateways.

### Everything Together

On Helm 4, run `helm plugin install .` once and replace `--post-renderer ./post-render.sh` with
`--post-renderer tyk-ai-studio` (see [The Post-Renderer](#the-post-renderer)).

```bash
helm upgrade --install tyk-ai-studio ./ai-studio/helm \
  --namespace tyk-ai --create-namespace \
  --values values.yaml \
  --values values-rag.yaml \
  --values values-production.yaml \
  --post-renderer ./post-render.sh \
  --set config.tykAiSecretKey=$TYK_AI_SECRET_KEY \
  --set config.grpcAuthToken=$GRPC_AUTH_TOKEN \
  --set config.microgatewayEncryptionKey=$MICROGATEWAY_ENCRYPTION_KEY \
  --set config.tykAiLicense=$TYK_AI_LICENSE \
  --set database.password=$POSTGRES_PASSWORD \
  --set microgateway.secrets.edgeAuthToken=$GRPC_AUTH_TOKEN \
  --set microgateway.secrets.encryptionKey=$MICROGATEWAY_ENCRYPTION_KEY \
  --set microgateway.secrets.tykAiLicense=$TYK_AI_LICENSE
```

---

## Upgrading

Upgrade AI Studio and the Edge Gateway together. Clone the new tag, update the image tags in the
values files, and rerun the install command.

From 2.2.1 the AI Studio Deployment uses the `Recreate` strategy, so AI Studio is briefly
unavailable during an upgrade. The Edge Gateway keeps serving traffic.

### Changes in 2.2 that affect this install

- **New tools are chat-only by default.** Enable REST or MCP access on each tool.
- **`/metrics` is off** unless `METRICS_AUTH_TOKEN` or `METRICS_ALLOW_UNAUTHENTICATED=true` is set.
- **A budget of `0` now means zero spend.** Use an empty budget for no limit.
- **Edge Gateway analytics are deleted after a retention period.** The product default is 7 days
  with the analytics pulse on; the chart sets 90 (`microgateway.config.analyticsRetentionDays`).
- **Edge Gateway rate limit settings** (`ENABLE_RATE_LIMITING`, `GATEWAY_DEFAULT_RATE_LIMIT`)
  are removed. Use a rate limiting plugin.
- **CSRF in DEVMODE** now trusts the host in `SITE_URL` as well as `localhost:3000`, so
  registration over plain HTTP (port-forward) works on 2.2 without extra settings.

See the [AI Studio release notes](https://tyk.io/docs/developer-support/release-notes/ai-studio).

---

## Troubleshooting

### Edge Gateway Not Connecting

```bash
kubectl logs -n tyk-ai -l app=microgateway
```

- `CONTROL_ENDPOINT` must be `tyk-ai-studio:50051`. Install the release as `tyk-ai-studio`.
- `microgateway.secrets.edgeAuthToken` must match `config.grpcAuthToken`.
- `microgateway.secrets.encryptionKey` must match `config.microgatewayEncryptionKey`.

### Login Fails over HTTP

Set `config.devMode: "true"`. Session cookies need it without HTTPS.

### Marketplace Page Is Empty

`config.ociCacheDir` must be set (`values.yaml` sets `./data/cache/plugins`).

### Data on Restart

AI Studio's `data/` directory (plugin and marketplace caches, branding uploads) is an `emptyDir`.
All configuration is stored in PostgreSQL.

---

## Cleanup

```bash
helm uninstall tyk-ai-studio -n tyk-ai
kubectl delete namespace tyk-ai
```

On Helm 4, also remove the post-renderer plugin if you installed it: `helm plugin uninstall tyk-ai-studio`.
