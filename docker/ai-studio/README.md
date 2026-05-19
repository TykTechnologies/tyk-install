# Tyk AI Studio Docker Install - Quick Guide

## Prerequisites

- Docker Engine 24.0+ installed
- Docker Compose v2.20+ installed
- OpenSSL installed for local TLS certificate generation
- 4GB+ RAM available

---

## Quick Start

### 1. Clone and Configure

```bash
cd docker/ai-studio

# Copy example env file
cp .env.example .env
```

Update the matching security values in `confs/studio.env` and `confs/microgateway.env`:

| Value                                            | Files                            | Requirement |
| ------------------------------------------------ | -------------------------------- | ----------- |
| `GRPC_AUTH_TOKEN` / `EDGE_AUTH_TOKEN`            | `studio.env`, `microgateway.env` | Must match  |
| `MICROGATEWAY_ENCRYPTION_KEY` / `ENCRYPTION_KEY` | `studio.env`, `microgateway.env` | Must match  |

**CRITICAL:** Ensure NO SPACES around the `=` sign in your env files:

```bash
# Correct
GRPC_AUTH_TOKEN=change-this-token

# Wrong - will fail
GRPC_AUTH_TOKEN = change-this-token
```

Ensure `ai-studio.localhost` resolves to your local machine. add a local hosts entry:

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
docker-compose up -d

# Verify services are running
docker-compose ps
```

**Expected containers:**

- `tyk-ai-studio` - Running (port 4000)
- `tyk-ai-microgateway` - Running (port 9091)
- `tyk-ai-postgres` - Running (port 5433)

Wait for all health checks to pass (~30-60 seconds):

```bash
# Watch container status
docker-compose ps

# Check logs if needed
docker-compose logs -f
```

---

### 4. Test the Installation

```bash
# Test AI Studio UI/API over HTTPS
curl -k https://ai-studio.localhost:4000/

# Test external Microgateway listener
curl http://localhost:9091/

# Confirm the default image set is Community Edition
curl -k https://ai-studio.localhost:4000/auth/features
```

---

## Access URLs

| Service             | URL                                | Description                          |
| ------------------- | ---------------------------------- | ------------------------------------ |
| AI Studio           | `https://ai-studio.localhost:4000` | Admin UI and REST API                |
| Embedded AI Gateway | `http://localhost:9090`            | AI Studio embedded gateway           |
| Microgateway        | `http://localhost:9091`            | External edge gateway                |
| PostgreSQL          | `localhost:5433`                   | AI Studio and Microgateway databases |

---

## Configuration Details

### Environment Files

| File                         | Purpose                                                        |
| ---------------------------- | -------------------------------------------------------------- |
| `.env`                       | Component versions                                             |
| `confs/studio.env`           | AI Studio control plane configuration                          |
| `confs/microgateway.env`     | Edge Microgateway configuration                                |
| `confs/analytics-pulse.yaml` | Analytics pulse plugin configuration                           |
| `utils/dbs.sql`              | PostgreSQL initialization script for the Microgateway database |

### Secrets Management

**Main secrets in config files:**

- **TYK_AI_SECRET_KEY** - AI Studio application secret
- **GRPC_AUTH_TOKEN** - Control-plane token used by the edge Microgateway
- **MICROGATEWAY_ENCRYPTION_KEY** - Shared encryption key for Microgateway data
- **DATABASE_URL** - Database credentials for the `tyk_ai_studio` database
- **DATABASE_DSN** - Database credentials for the `tyk_ai_microgateway` database

### Enterprise Images

This bundle defaults to the open source Community Edition images:

- `tykio/tyk-ai-studio`
- `tykio/tyk-microgateway`

Enterprise images are available separately:

- `tykio/tyk-ai-studio-enterprise`
- `tykio/tyk-microgateway-ent`

If you switch to the Enterprise images, set `TYK_AI_LICENSE` before the first start and pass it to both AI Studio and Microgateway. Enterprise containers validate the license at startup.

---

## Troubleshooting

### Browser Cannot Open AI Studio

**Symptom:** Browser shows a TLS or host error for `https://ai-studio.localhost:4000`

1. Confirm `ai-studio.localhost` resolves to `127.0.0.1`
2. Confirm certificate files exist in `studio-certs/`
3. Use `https://ai-studio.localhost:4000`, not plain HTTP
4. Accept the self-signed certificate warning for local development

### Microgateway Not Connecting to AI Studio

**Symptom:** Microgateway logs show edge/control connection errors

```bash
docker-compose logs microgateway
```

Common issues:

1. `EDGE_AUTH_TOKEN` does not match `GRPC_AUTH_TOKEN`
2. `ENCRYPTION_KEY` does not match `MICROGATEWAY_ENCRYPTION_KEY`
3. AI Studio did not start successfully because TLS files are missing
4. Existing Postgres volume was created before `utils/dbs.sql` added Microgateway compatibility domains

If Microgateway fails with `type "blob" does not exist`, add the compatibility domains to the existing Microgateway database and restart Microgateway:

```bash
docker-compose exec -T postgres psql -U tykuser -d tyk_ai_microgateway <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'blob') THEN
    CREATE DOMAIN blob AS bytea;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'string') THEN
    CREATE DOMAIN string AS text;
  END IF;
END
$$;
SQL

docker-compose restart microgateway
```

For disposable local PoCs, you can also recreate the Postgres volume so the init script runs again:

```bash
docker-compose down -v
docker-compose up -d
```

### Registration Returns 400

**Symptom:** The register page returns HTTP 400.

Check the response body for the exact reason:

- `password must contain at least one uppercase letter, one lowercase letter, one number, and one special character` means the password failed backend validation.

Backend password validation accepts special characters from this set:

```text
! @ # $ % ^ & * ( ) , . ? " : { } | < >
```

For local testing, a password like `ChangeMe123!` satisfies the backend rule.

---
