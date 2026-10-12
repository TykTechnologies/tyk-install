# Tyk AI Studio Docker Install - Quick Guide

Runs Tyk AI Studio 2.2.1 (control plane), an Edge Gateway (data plane) and PostgreSQL with
Docker Compose. For Kubernetes, see [helm-ai-studio](../../kubernetes/helm-ai-studio/).

> The Edge Gateway's image and file names use the older name `microgateway` (for example
> `tykio/tyk-microgateway` and `mgw-data/`). This guide uses "Edge Gateway" for the same component.

## Prerequisites

- Docker Engine 20.10+ and Docker Compose v2
- At least 4 GB RAM available
- OpenSSL for local TLS certificate generation
- Enterprise Edition only: a Tyk AI license key

---

## Quick Start

### 1. Clone and Configure

```bash
cd docker/ai-studio

# Copy example env file (images, versions, Enterprise license)
cp .env.example .env
```

Generate the secrets (`openssl rand -hex 16` for each) and update them in `confs/studio.env` and
`confs/microgateway.env`:

| AI Studio (`studio.env`)      | Edge Gateway (`microgateway.env`) | Requirement |
| ----------------------------- | --------------------------------- | ----------- |
| `GRPC_AUTH_TOKEN`             | `EDGE_AUTH_TOKEN`                 | Must match  |
| `MICROGATEWAY_ENCRYPTION_KEY` | `ENCRYPTION_KEY`                  | Must match  |
| `TYK_AI_SECRET_KEY`           | -                                 | AI Studio   |
| `CSRF_KEY`                    | -                                 | AI Studio   |

**CRITICAL:** Ensure NO SPACES around the `=` sign in your env files:

```bash
# Correct
GRPC_AUTH_TOKEN=change-this-token

# Wrong - will fail
GRPC_AUTH_TOKEN = change-this-token
```

Ensure `ai-studio.localhost` resolves to your local machine. Add a local hosts entry:

```bash
echo "127.0.0.1 ai-studio.localhost" | sudo tee -a /etc/hosts
```

---

### 2. Generate Local TLS Certificates

Serve on `ai-studio.localhost`.

```bash
mkdir -p studio-certs

openssl req \
  -x509 \
  -newkey rsa:4096 \
  -sha256 \
  -nodes \
  -days 365 \
  -subj "/CN=ai-studio.localhost" \
  -addext "subjectAltName=DNS:ai-studio.localhost" \
  -keyout studio-certs/tls-private-key.pem \
  -out studio-certs/tls-certificate.pem
```

---

### 3. Start Services

```bash
# Start all services
docker compose up -d

# Verify services are running
docker compose ps
```

**Expected containers:**

- `tyk-ai-studio` - Running (ports 4000, 9090)
- `tyk-ai-microgateway` - Running (port 9091)
- `tyk-ai-postgres` - Running (port 5433)

On the first start, the Edge Gateway can start before the AI Studio gRPC server is ready. It logs
`Failed to connect to control server` and restarts until the connection succeeds (~30 seconds).

```bash
# Check logs if needed
docker compose logs -f
```

---

### 4. Test the Installation

```bash
# AI Studio health over HTTPS
curl -k https://ai-studio.localhost:4000/health

# Edge Gateway health
curl http://localhost:9091/health

# Edition and version (community / enterprise)
curl -k https://ai-studio.localhost:4000/auth/features
```

### 5. First Login

1. Open `https://ai-studio.localhost:4000`, accept the self-signed certificate, and select
   **Sign up**. The first user becomes the administrator.
2. Go to **Settings → Secrets** and fill in `OPENAI_KEY` / `ANTHROPIC_KEY`.
3. Go to **AI Portal → Edge Gateways**. `edge-1` shows as **Connected**. Select
   **Push Configuration**.

---

## Access URLs

| Service             | URL                                | Description                |
| ------------------- | ---------------------------------- | -------------------------- |
| AI Studio           | `https://ai-studio.localhost:4000` | Admin UI and REST API      |
| Embedded AI Gateway | `http://localhost:9090`            | AI Studio embedded gateway |
| Edge Gateway        | `http://localhost:9091`            | External edge gateway      |
| PostgreSQL          | `localhost:5433`                   | AI Studio database         |

---

## Configuration Details

### Files

| File                         | Purpose                                                        |
| ---------------------------- | -------------------------------------------------------------- |
| `.env`                       | Images, versions and Enterprise license (`TYK_AI_LICENSE`)     |
| `confs/studio.env`           | AI Studio control plane configuration                          |
| `confs/microgateway.env`     | Edge Gateway configuration                                     |
| `confs/analytics-pulse.yaml` | Analytics pulse: sends Edge Gateway analytics and spend to AI Studio |
| `studio-certs/`              | TLS certificate and key for AI Studio                          |
| `plugins/`                   | Local plugin binaries, mounted at `/opt/plugins`               |
| `docker-compose.rag.yml`     | Optional: Reranker and Transformer Server                      |
| `docker-compose.presidio.yml` | Optional: Microsoft Presidio for PII Guardrails (Enterprise)  |
| `docker-compose.production.yml` | Optional: production settings (gRPC TLS, CORS, metrics token) |

The optional files are described in [Optional Components](#optional-components).

The 2.2 images are distroless and run as a non-root user (UID `65532`) from
`/opt/tyk-ai-studio` and `/opt/tyk-microgateway`. Relative paths such as `./data/...` resolve
against those directories.

| Host directory | Container path                 | Contents                                    |
| -------------- | ------------------------------ | ------------------------------------------- |
| `studio-data/` | `/opt/tyk-ai-studio/data`      | Plugin and marketplace caches, branding, exports |
| `mgw-data/`    | `/opt/tyk-microgateway/data`   | Edge Gateway SQLite database                |
| `mgw-plugins/` | `/var/lib/microgateway`        | Edge Gateway OCI plugin cache               |

On Linux hosts, make these directories writable for the container user before the first start:

```bash
mkdir -p studio-data mgw-data mgw-plugins plugins
sudo chown -R 65532:65532 studio-data mgw-data mgw-plugins
```

### Databases

- **AI Studio** uses PostgreSQL (`tyk_ai_studio`).
- **Edge Gateway** uses SQLite in `mgw-data/`. It is a cache that is rebuilt from AI Studio on
  every start.

### Secrets Management

**Main secrets in config files:**

- **TYK_AI_SECRET_KEY** - AI Studio secret for encrypting stored secrets and SSO
- **GRPC_AUTH_TOKEN** - Control-plane token used by the Edge Gateway
- **MICROGATEWAY_ENCRYPTION_KEY** - Shared encryption key for synced configuration
- **CSRF_KEY** - Keeps CSRF tokens valid across AI Studio restarts
- **DATABASE_URL** - Database credentials for the `tyk_ai_studio` database

### Enterprise Edition

This bundle defaults to the open source Community Edition images. To use Enterprise, set these in
`.env` before the first start:

```bash
AI_STUDIO_IMAGE=tykio/tyk-ai-studio-ent
MICROGATEWAY_IMAGE=tykio/tyk-microgateway-ent
TYK_AI_LICENSE=your-license-key
```

`docker-compose.yml` passes `TYK_AI_LICENSE` to both AI Studio and the Edge Gateway.
Enterprise containers validate the license at startup.

### Optional Settings

- **Metrics:** `/metrics` is not served unless `METRICS_AUTH_TOKEN` or
  `METRICS_ALLOW_UNAUTHENTICATED=true` is set.
- **Request/response bodies:** the Edge Gateway stores them (and the analytics pulse sends them)
  only with `ANALYTICS_STORE_REQUESTS=true` / `ANALYTICS_STORE_RESPONSES=true`.
- **SMTP:** required to invite users. Other users must verify their email before they can log in.

See the [AI Studio](https://tyk.io/docs/ai-management/ai-studio/ai-studio-env) and
[Edge Gateway](https://tyk.io/docs/ai-management/ai-studio/edge-gateway-env) environment variable
references.

---

## Optional Components

Each optional component is a Compose override file. Add `-f <file>` after `-f docker-compose.yml`
to every `docker compose` command (`up`, `ps`, `logs`, `down`). For example, everything at once:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.rag.yml \
  -f docker-compose.presidio.yml \
  -f docker-compose.production.yml \
  up -d
```

### Reranker and Transformer Server

Listed as optional components in the
[Kubernetes install docs](https://tyk.io/docs/ai-management/ai-studio/deployment-k8s).
`docker-compose.rag.yml` adds:

| Service              | URL                     | API                   | Purpose                                       |
| -------------------- | ----------------------- | --------------------- | --------------------------------------------- |
| `reranker`           | `http://localhost:8081` | `POST /rerank`        | Scores text pairs (model `BAAI/bge-reranker-large`) |
| `transformer-server` | `http://localhost:8082` | `POST /v1/embeddings` | OpenAI-compatible embeddings from any sentence-transformers model |

- Both images only publish a `latest` tag and download their models from Hugging Face on first
  use. The first request can take several minutes; the cache volumes keep the models afterwards.
- The reranker uses about 2.5 GB of memory.
- AI Studio does not call either service on its own. To embed with the Transformer Server, create a
  standalone **Embedder** with API compatibility `openai`, endpoint
  `http://transformer-server:8000/v1` and a model such as `sentence-transformers/all-MiniLM-L6-v2`.

### Microsoft Presidio (PII Guardrails)

Guardrails are an Enterprise feature. The built-in pattern library can already redact PII with
nothing to deploy. Presidio adds entity recognition, for example of names and places.
`docker-compose.presidio.yml` adds `presidio-analyzer` (`localhost:5002`) and
`presidio-anonymizer` (`localhost:5001`). In a Guardrail filter, choose the **Microsoft Presidio**
provider and set:

- **Analyzer URL**: `http://presidio-analyzer:3000`
- **Anonymizer URL** (optional): `http://presidio-anonymizer:3000`

### Production Settings

From the AI Studio reference architecture. Set `METRICS_AUTH_TOKEN` in `.env` first
(`openssl rand -hex 16`). `docker-compose.production.yml`:

- Serves the gRPC control connection over TLS with the certificate in `studio-certs/`. The Edge
  Gateway trusts that certificate (`EDGE_TLS_CA_PATH`) and checks it as `ai-studio.localhost`.
- Sets `CORS_ALLOWED_ORIGINS` to the AI Studio URL and `PLUGIN_BLOCK_INTERNAL_URLS=true`.
- Requires `Authorization: Bearer <METRICS_AUTH_TOKEN>` on `/metrics` for AI Studio and the Edge
  Gateway.

For a real deployment, also use certificates from your own CA, an external PostgreSQL, and
`DEVMODE=false` (already set). Never set `EDGE_SKIP_TLS_VERIFY` or `EDGE_ALLOW_INSECURE=true`.

---

## Upgrading

Upgrade AI Studio and the Edge Gateway together. Update the versions in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

### Upgrading from 2.1 to 2.2

The 2.2 images changed paths and some settings. Changes made in this bundle:

- Container paths moved from `/app/...` to `/opt/tyk-ai-studio/...` and `/opt/tyk-microgateway/...`.
- `DEV_MODE` was never read. The variable is `DEVMODE`, set to `false` because this bundle serves HTTPS.
- `ADMIN_EMAIL` is deprecated and ignored. The first user who signs up becomes the administrator.
- The Edge Gateway now uses SQLite, so `utils/dbs.sql` and the `tyk_ai_microgateway` database
  are no longer used.

Behavior changes in 2.2 to check:

- **New tools are chat-only by default.** Enable REST or MCP access on each tool.
- **A budget of `0` now means zero spend.** Use an empty budget for no limit.
- **Edge Gateway analytics are deleted after a retention period.** This bundle keeps 90 days
  (`ANALYTICS_RETENTION_DAYS`).
- **Edge Gateway rate limit settings** (`ENABLE_RATE_LIMITING`, `GATEWAY_DEFAULT_RATE_LIMIT`)
  are removed. Use a rate limiting plugin.

See the [AI Studio release notes](https://tyk.io/docs/developer-support/release-notes/ai-studio).

---

## Troubleshooting

### Browser Cannot Open AI Studio

**Symptom:** Browser shows a TLS or host error for `https://ai-studio.localhost:4000`

1. Confirm `ai-studio.localhost` resolves to `127.0.0.1`
2. Confirm certificate files exist in `studio-certs/`
3. Use `https://ai-studio.localhost:4000`, not plain HTTP
4. Accept the self-signed certificate warning for local development

### Edge Gateway Not Connecting to AI Studio

**Symptom:** Edge Gateway logs show edge/control connection errors

```bash
docker compose logs microgateway
```

Common issues:

1. `EDGE_AUTH_TOKEN` does not match `GRPC_AUTH_TOKEN`
2. `ENCRYPTION_KEY` does not match `MICROGATEWAY_ENCRYPTION_KEY`
3. AI Studio did not start because TLS files are missing (`CERT_FILE` / `KEY_FILE`)
4. AI Studio and the Edge Gateway run different versions

### Permission Denied on Data Directories

**Symptom:** Logs show `permission denied` under `/opt/tyk-ai-studio/data` or
`/opt/tyk-microgateway/data` (Linux hosts).

The containers run as UID `65532`. Fix the ownership and restart:

```bash
sudo chown -R 65532:65532 studio-data mgw-data mgw-plugins
docker compose restart
```

### Marketplace Page Is Empty

`AI_STUDIO_OCI_CACHE_DIR` must be set in `confs/studio.env`. Without it, the marketplace service
does not start.

### Registration Returns 400

**Symptom:** The register page returns HTTP 400.

Check the response body for the exact reason:

- `password must contain at least one uppercase letter, one lowercase letter, one number, and one special character` means the password failed backend validation.

Backend password validation accepts special characters from this set:

```text
! @ # $ % ^ & * ( ) , . ? " : { } | < >
```

For local testing, a password like `ChangeMe123!` satisfies the backend rule.

### Start Fresh

For disposable local PoCs, remove the containers, the database volume and the local data:

```bash
docker compose down -v
rm -rf studio-data mgw-data mgw-plugins
docker compose up -d
```
