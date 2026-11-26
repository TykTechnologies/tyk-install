# Tyk AI Studio Kubernetes Install - Quick Guide

Deploys Tyk AI Studio (control plane), an Edge Gateway (data plane) and PostgreSQL with the
Helm chart from the [Tyk AI Studio repository](https://github.com/TykTechnologies/ai-studio/tree/main/helm).
The chart version is `AI_STUDIO_VERSION` in `.env.example`, and the image tags are in the values
files.

> The chart is named `midsommar`, and the Edge Gateway is still called `microgateway` in the
> chart values and image names. This guide uses "Edge Gateway" for the same component.

## Prerequisites

- Kubernetes cluster running, `kubectl` configured and connected
- Helm 3 or Helm 4, and `git`
- `openssl` to generate secrets
- Enterprise Edition only: a Tyk AI license issued for the AI Studio version you run. AI Studio
  2.3 refuses a license issued for 2.2 or earlier: ask your Tyk account manager for a 2.3 license.
- Ingress + TLS only: an Ingress controller and cert-manager

## Files

| File                     | Purpose                                                              |
| ------------------------ | -------------------------------------------------------------------- |
| `.env.example`           | Chart version, license and secrets, loaded into the shell            |
| `values.yaml`            | Community Edition, ClusterIP services, internal PostgreSQL           |
| `values-enterprise.yaml` | Overlay: Enterprise images (`tyk-ai-studio-ent`, `tyk-microgateway-ent`) |
| `values-ingress.yaml`    | Overlay: Ingress + TLS for AI Studio and the Edge Gateway             |
| `values-rag.yaml`        | Optional: Reranker and Transformer Server                            |
| `values-production.yaml` | Optional: production settings (gRPC TLS, metrics token, CORS, CSRF key) |
| `post-render.sh`         | Optional: mounts a private gRPC CA into the Edge Gateway             |
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
Never change `TYK_AI_SECRET_KEY` after the first install: it encrypts LLM credentials, App keys and
the secret store, and App keys stop validating with another value.

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

Install the release as `tyk-ai-studio`. `values.yaml` names the AI Studio resources
`tyk-ai-studio` (`fullnameOverride`) and points the Edge Gateway at `tyk-ai-studio:50051`
(`microgateway.config.controlEndpoint`). AI Studio reaches the Edge Gateway at
`<release>-microgateway`, and the post-renderer patches `tyk-ai-studio-microgateway`, so the
release name must match. The chart refuses to render when the control endpoint does not match its
AI Studio Service.

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

On the first install, AI Studio waits for PostgreSQL (up to `DATABASE_STARTUP_TIMEOUT`, 60
seconds), and the Edge Gateway restarts until the AI Studio gRPC server is ready. This is expected.

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
     --version v1.21.3 \
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

## Internal Network Addresses

AI Studio and the Edge Gateway refuse calls to internal addresses (loopback, private ranges,
link-local and other internal ranges, by IP or by a name that resolves to one) unless the host is
allowed. This covers LLMs, embedders, tools, data sources, vector stores and guardrail providers.
A refused call answers `502` with `blocked by LLM_UPSTREAM_BLOCK_INTERNAL`.

Every in-cluster Service has a private address. `values.yaml` allows the optional Services by name
in `config.allowedInternalHosts` and `microgateway.config.allowedInternalHosts`
(`tyk-ai-studio-transformer`, `tyk-ai-studio-reranker`, `presidio-analyzer`,
`presidio-anonymizer`) and keeps blocking on for everything else. Add your own in-cluster hosts to
both values, for example an Ollama Service; `.svc.cluster.local` allows every Service. Each process
applies its own setting, so keep the two lists the same. An administrator can instead turn on
**Allow internal host** on a single LLM, embedder, tool, data source, guardrail or plugin.

## Usage Telemetry

AI Studio sends anonymised usage statistics to Tyk by default. To stop it, add
`--set extraEnv[0].name=TELEMETRY_ENABLED --set-string extraEnv[0].value=false` to the install
command, and on Enterprise also `LICENSE_DISABLE_TELEMETRY=true` the same way as `extraEnv[1]`
([Telemetry and privacy](https://tyk.io/docs/ai-management/ai-studio/telemetry)).

---

## Optional Components

The [Kubernetes install docs](https://tyk.io/docs/ai-management/ai-studio/deployment-k8s) list the
Reranker and Transformer Server as optional components,
[Guardrails](https://tyk.io/docs/ai-management/ai-studio/guardrails) can use
Microsoft Presidio, and the reference architecture lists production settings. Pick what you need;
each part adds to the install command from step 3.

### The Post-Renderer

Only [Production Settings](#production-settings) with a private or self-signed CA need it. The
Edge Gateway reads the CA for AI Studio's gRPC certificate only from a file, and its subchart
cannot mount extra volumes. `post-render.sh` mounts `tls.crt` from Secret `tyk-ai-studio-grpc-tls`
into the Edge Gateway at install time. Everything for AI Studio itself is set with chart values.

The post-renderer needs `kubectl` (for `kubectl kustomize`). With Helm 3, add this to the install
command:

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
- Both Services are in the internal host allow list (see
  [Internal Network Addresses](#internal-network-addresses)).
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

Guardrail providers follow the same outbound rules as LLM upstreams. `values.yaml` allows both
hosts (see [Internal Network Addresses](#internal-network-addresses)); if you rename them, change
the allow lists too. From 2.3, guardrails also scan tool results, so Presidio receives tool output
as well as prompts.

### Production Settings

From the AI Studio reference architecture. `values-production.yaml` turns on TLS for the gRPC
control connection, protects `/metrics`, sets the CORS origins and a shared CSRF key, all through
chart values.

1. Create a certificate for the gRPC control connection. Its name must match the AI Studio service,
   `tyk-ai-studio`. A self-signed certificate works, because the Edge Gateway trusts the
   certificate from the same Secret through the post-renderer.

   ```bash
   mkdir -p grpc-tls
   openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 365 \
     -subj "/CN=tyk-ai-studio" \
     -addext "subjectAltName=DNS:tyk-ai-studio,DNS:tyk-ai-studio.tyk-ai.svc,DNS:tyk-ai-studio.tyk-ai.svc.cluster.local" \
     -keyout grpc-tls/tls.key -out grpc-tls/tls.crt

   kubectl create secret tls tyk-ai-studio-grpc-tls -n tyk-ai \
     --cert=grpc-tls/tls.crt --key=grpc-tls/tls.key
   ```

2. Create the Secret for the metrics token, which AI Studio and the Edge Gateway both read:

   ```bash
   kubectl create secret generic tyk-ai-studio-extra -n tyk-ai \
     --from-literal=METRICS_AUTH_TOKEN=$(openssl rand -hex 16)
   ```

3. Set `CSRF_KEY` in `.env` (`openssl rand -hex 32`). It keeps logins valid across restarts, and
   the chart refuses `replicaCount` above 1 without it.
4. Set `CORS_ALLOWED_ORIGINS` in `values-production.yaml` to the AI Studio URL.
5. Add `--values values-production.yaml --set config.csrfKey=$CSRF_KEY` to the install command.
   For a self-signed or private CA, also add `--post-renderer ./post-render.sh` (on Helm 4,
   `--post-renderer tyk-ai-studio` after `helm plugin install .`). With a certificate from a CA in
   the system roots, skip the post-renderer and remove `EDGE_TLS_CA_PATH` from
   `values-production.yaml`.

AI Studio then logs `gRPC TLS enabled`, the Edge Gateway connects over TLS, and `/metrics` answers
`401` without `Authorization: Bearer <METRICS_AUTH_TOKEN>`.

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
  --set config.csrfKey=$CSRF_KEY \
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

Upgrade AI Studio and the Edge Gateway together. Back up the database first: rolling back means
restoring it. Clone the new tag, update the image tags in the values files, and rerun the install
command.

With one replica (`replicaCount: 1`, the default) the AI Studio Deployment uses the `Recreate`
strategy, so AI Studio is briefly unavailable during an upgrade. The Edge Gateway keeps serving
traffic.

### Upgrading from 2.2 to 2.3

Changes made in this install:

- **The Edge Gateway's control endpoint is set** (`microgateway.config.controlEndpoint:
  tyk-ai-studio:50051`). The 2.3 chart refuses to render when the endpoint does not match its AI
  Studio Service.
- **Internal addresses are blocked by default** (`config.blockInternalUpstreams` and
  `microgateway.config.blockInternalUpstreams`). `values.yaml` allows the optional Services by
  name. Add any other in-cluster host you use, such as an Ollama Service, before upgrading. See
  [Internal Network Addresses](#internal-network-addresses).
- **OCI plugin signatures are required** (`config.ociRequireSignature: "true"`). 2.3 verifies them
  without `cosign`, so the install no longer turns the check off. This only changes the Enterprise
  Edition: sign your own OCI plugins, configure their keys (`OCI_PLUGINS_PUBKEY_*`), or set
  `config.ociRequireSignature` and `microgateway.config.ociPluginsRequireSignature` to `"false"`.

Before you upgrade:

- **Enterprise: get a 2.3 license.** A 2.2 license is refused and AI Studio and the Edge Gateway do
  not start. Keep the 2.2 license until the upgrade is confirmed.
- **List your `$ENV/` references.** They resolve only for names in `AI_STUDIO_ENV_REF_ALLOWLIST`
  (set it with `extraEnv`). Prefer the secret store (`$SECRET/` references).
- **Vendor keys are no longer read from the environment** (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`
  and others). Set the key on each LLM, embedder and data source.
- **Plugins no longer inherit the pod environment.** List the variables a plugin needs in
  `PLUGIN_ENV_PASSTHROUGH`. Upgrade the marketplace plugins to their 2.3 releases (the
  changelog's "Plugin releases" table). If the Marketplace page still offers an older version,
  add the plugin by its OCI reference, for example
  `oci://docker.tyk.io/studio-plugins/llm-cache:1.3.1`.
- **Back up the database.** The first 2.3 start encrypts LLM keys and App keys with
  `TYK_AI_SECRET_KEY`. A 2.2 AI Studio started on that database afterwards refuses every App key,
  so stop every 2.2 replica before the first 2.3 replica starts. With one replica the `Recreate`
  strategy does this; with `replicaCount` above 1, set `midsommar.strategy.type: Recreate` for this
  upgrade.
- **Upload a custom logo again.** 2.3 keeps the logo and favicon in the database. Here they were
  stored in the `emptyDir`, so a logo uploaded on 2.2 is gone after the upgrade.

Behavior changes in 2.3 to check:

- **The chart adds a startup probe and a 10-second `preStop` delay** for AI Studio (Kubernetes
  1.30 and later), and the Edge Gateway's default memory limit rises from 512Mi to 1Gi.
- **Existing guardrails scan tool results** (Enterprise), and remote providers such as Presidio
  receive tool output.
- **Edges older than 2.3** block guardrailed traffic, fail Bedrock calls and do not enforce LLM
  budgets against a 2.3 AI Studio. Upgrade the Edge Gateway with AI Studio.
- **The Edge Gateway answers `404` on `/api/v1`.** Configure edges from AI Studio.
- **API keys are shown in full only when issued.** Roll a key to see a new one.

See the [2.3.0 changelog](https://github.com/TykTechnologies/ai-studio/blob/v2.3.0-rc6/CHANGELOG-v2.3.0.md#upgrade-notes) for the full list.

### Upgrading from 2.1 to 2.2

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

- `CONTROL_ENDPOINT` must be `tyk-ai-studio:50051` (`microgateway.config.controlEndpoint` in
  `values.yaml`). Install the release as `tyk-ai-studio`.
- `microgateway.secrets.edgeAuthToken` must match `config.grpcAuthToken`.
- `microgateway.secrets.encryptionKey` must match `config.microgatewayEncryptionKey`.

### Calls Answer 502 `blocked by LLM_UPSTREAM_BLOCK_INTERNAL`

The upstream resolves to an internal address. Add its host to `config.allowedInternalHosts` and
`microgateway.config.allowedInternalHosts`, then rerun the install command. See
[Internal Network Addresses](#internal-network-addresses).

### AI Studio Exits at Startup with `license validation failed at boot`

The Enterprise license is missing, expired or issued for an older version. AI Studio 2.3 needs a
license issued for 2.3.

### Login Fails over HTTP

Set `config.devMode: "true"`. Session cookies need it without HTTPS.

### Marketplace Page Is Empty

`config.ociCacheDir` must be set (`values.yaml` sets `./data/cache/plugins`).

### Data on Restart

AI Studio's `data/` directory (plugin and marketplace caches, exports) is an `emptyDir`. All
configuration, and from 2.3 the custom logo and favicon, is stored in PostgreSQL.

---

## Cleanup

```bash
helm uninstall tyk-ai-studio -n tyk-ai
kubectl delete namespace tyk-ai
```

On Helm 4, also remove the post-renderer plugin if you installed it: `helm plugin uninstall tyk-ai-studio`.
