# Tyk Self-Managed Docker PoC - Quick Guide

## Prerequisites

- Docker Engine 24.0+ installed
- Docker Compose v2.20+ installed
- Tyk license key (Dashboard + Portal)
- 4GB+ RAM available

---

## Quick Start

### 1. Clone and Configure

```bash
cd docker/self-managed

# Copy example env file and add your license keys
cp .env.example .env

# Edit .env file with your license key
# Required: DASH_LICENSE
```

**CRITICAL:** Ensure NO SPACES around the `=` sign in your `.env` file:

```bash
# Correct
DASH_LICENSE=eyJhbGciOiJSUzI1NiIsInR5cCI6...

# Wrong - will fail
DASH_LICENSE = eyJhbGciOiJSUzI1NiIsInR5cCI6...

---

### 2. Start Services

```bash
# Start all services
docker-compose up -d

# Verify services are running
docker-compose ps
```

**Expected containers:**

- `tyk-dashboard` - Running (port 3000)
- `tyk-gateway` - Running (port 8080)
- `tyk-pump` - Running
- `tyk-portal` - Running (port 3001)
- `tyk-redis` - Running (port 6379)
- `tyk-postgres` - Running (port 5432)

Wait for all health checks to pass (~30-60 seconds):

```bash
# Watch container status
docker-compose ps

# Check logs if needed
docker-compose logs -f
```

---

### 3. Bootstrap the Stack

You have two options for bootstrapping:

#### Option A: Automated Bootstrap (Recommended)

Use the Bootstrap Utility for automated setup. See **[Bootstrap Utility README](https://github.com/TykTechnologies/tyk-pocs/blob/main/utils/bootstrap/README.md)** for complete instructions.

**Quick start:**

```bash
# Clone full repo (if you only have this folder)
git clone https://github.com/TykTechnologies/tyk-pocs.git
cd tyk-pocs/utils/bootstrap

# You will need to set env vars before running. Check the Bootstrap README
# Run the bootstrap script docker tools profile
docker-compose --profile tools run --rm tyk-bootstrap

# Run the bootstrap script directly
./bootstrap.sh

```

The script creates: organization, admin user, test API, policy, API key, and Portal configuration.

**Credentials saved to:** `utils/bootstrap/bootstrap-output/bootstrap-credentials.txt`

#### Option B: Manual Bootstrap (via Browser)

1. Open browser: `http://localhost:3000`
2. Complete the bootstrap form
3. Login with created credentials
4. Continue to [Phase 4: Bootstrap Process](#phase-4-bootstrap-process-manual) for Portal setup

---

### 4. Test the Installation

```bash
# Test Gateway health
curl http://localhost:8080/hello

# Test Dashboard health
curl http://localhost:3000/hello

# Test Portal health
curl http://localhost:3001/ready

# If using bootstrap script, test the API (use key from bootstrap output)
curl http://localhost:8080/httpbin/get -H "Authorization: <your-api-key>"
```

---

## Access URLs

| Service    | URL                     | Description           |
| ---------- | ----------------------- | --------------------- |
| Dashboard  | `http://localhost:3000` | Admin UI              |
| Gateway    | `http://localhost:8080` | API Gateway           |
| Portal     | `http://localhost:3001` | Developer Portal      |
| Redis      | `localhost:6379`        | Cache/Session storage |
| PostgreSQL | `localhost:5432`        | Analytics/Config DB   |

---

## Configuration Details

### Environment Files

| File                      | Purpose                        |
| ------------------------- | ------------------------------ |
| `.env`                    | License keys and versions      |
| `confs/tyk.env`           | Gateway configuration          |
| `confs/tyk_analytics.env` | Dashboard configuration        |
| `confs/pump.env`          | Pump configuration             |
| `confs/portal.env`        | Developer Portal configuration |

> **Note for AWS Fargate and similar platforms:** These env files serve as a reference for required environment variables. For Fargate/ECS deployments, configure these variables directly in your Task Definitions and use AWS Secrets Manager for sensitive values.

### Secrets Management

**Main secrets in `.env`:**

- **DASH_LICENSE** - Dashboard and Portal license (required)
**Service secrets in config files:**

- **TYK_GW_SECRET** - Gateway API secret (must match Dashboard)
- **TYK_GW_NODESECRET** - Node secret for Gateway-Dashboard sync
- **TYK_DB_ADMINSECRET** - Dashboard admin API authentication

---

## Phase 4: Bootstrap Process (Manual)

> **Note:** If you used the [Bootstrap Utility](https://github.com/TykTechnologies/tyk-pocs/blob/main/utils/bootstrap/README.md), skip to [Phase 5](#phase-5-first-api-test). The utility handles all steps below automatically.

If you prefer manual setup:

### Step 1: Bootstrap Dashboard (via Browser)

1. Navigate to `http://localhost:3000`
2. Fill in the bootstrap form:
   - Organization Name
   - Admin Email
   - Admin Password
3. Click "Bootstrap"

### Step 2: Get Dashboard API Credentials

1. Login to Dashboard
2. Go to: **System Management > Users**
3. Click on your user
4. Copy **"Tyk Dashboard API Access Credentials"**
5. Also copy your **"Organization ID"**

### Step 3: Bootstrap Portal (via API)

```bash
# Bootstrap Portal
curl "http://localhost:3001/portal-api/bootstrap" \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "portal-admin@example.com",
    "password": "portalpass123",
    "first_name": "Portal",
    "last_name": "Admin"
  }'
```

**Expected Response:**

```json
{
  "data": {
    "api_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    ...
  }
}
```

**Save the `api_token`** - you'll need it for Portal configuration.

### Alternative: Bootstrap Portal via Command

The portal image supports a `--bootstrap` CLI flag that runs bootstrap on first start. Add a `command` to the `tyk-portal` service in `docker-compose.yml`:

```yaml
tyk-portal:
  image: tykio/portal:${PORTAL_VERSION:-v1.17.1}
  command:
    - "--bootstrap"
    - "--user=portal-admin@example.com"
    - "--pass=portalpass123"
    - "--first=Portal"
    - "--last=Admin"
    - '--email-settings={"SMTP":{"Host":"smtp.example.com","Port":587,"User":"smtpuser","Pass":"smtppass"},"Admin":"admin@example.com","DefaultFrom":"noreply@example.com"}'
```

The same arguments can be passed directly to the container on platforms that don't use docker-compose (e.g. AWS Fargate, ECS, Kubernetes). In an ECS task definition, escape the inner JSON quotes:

```json
"command": [
  "--bootstrap",
  "--user=portal-admin@example.com",
  "--pass=portalpass123",
  "--first=Portal",
  "--last=Admin",
  "--email-settings={\"SMTP\":{\"Host\":\"smtp.example.com\",\"Port\":587,\"User\":\"smtpuser\",\"Pass\":\"smtppass\"},\"Admin\":\"admin@example.com\",\"DefaultFrom\":\"noreply@example.com\"}"
]
```

**Important notes on `--email-settings`:**

- The value must be valid JSON. In docker-compose, use the **array form** of `command` (as shown above) to preserve JSON double quotes. The single-string form strips inner quotes, producing invalid JSON that silently fails.
- SMTP settings are only written to the DB during bootstrap (`configuration_tables`). Changing the flag after bootstrap has no effect.

---

## Phase 5: First API Test

### Step 1: Create API via Dashboard

1. Login to Dashboard (`http://localhost:3000`)
2. Navigate to: **APIs > Add New API**
3. Fill in API details:
   - API Name: `Test API`
   - Target URL: `https://httpbingo.org`
   - Listen Path: `/test-api/`
   - Strip Listen Path: checked
   - Authentication: Auth Token
4. Click **"Save"**

### Step 2: Create API Key

1. Navigate to: **Keys > Add New Key**
2. Assign to Test API
3. Click **"Save"**
4. Copy the generated key

### Step 3: Test the API

```bash
curl http://localhost:8080/test-api/get -H "Authorization: <your-key>"
```

**Expected Response:**

```json
{
  "args": {},
  "headers": {
    ...
  },
  "url": "https://httpbingo.org/get"
}
```

---

## Phase 6: Developer Portal

> **Note:** If you used the [Bootstrap Utility](https://github.com/TykTechnologies/tyk-pocs/blob/main/utils/bootstrap/README.md), Portal is already configured. Skip to Step 2.

### Step 1: Configure Portal Provider

Connect the Portal to your Dashboard:

```bash
# Set variables
export PORTAL_TOKEN="<api_token_from_bootstrap>"
export DASHBOARD_API_KEY="<from_dashboard_user_page>"
export ORG_ID="<your_org_id>"

# Create Provider
curl "http://localhost:3001/portal-api/providers" \
  -H "Authorization: ${PORTAL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "Name": "Tyk Dashboard",
    "Type": "tyk-pro",
    "Configuration": {
      "MetaData": "{\"URL\":\"http://tyk-dashboard:3000\",\"Secret\":\"'${DASHBOARD_API_KEY}'\",\"OrgID\":\"'${ORG_ID}'\",\"InsecureSkipVerify\":false}"
    }
  }'
```

### Step 2: Publish API to Portal

Follow: [Publish API to Catalog](https://tyk.io/docs/portal/publish-api-catalog)

### Step 3: Developer Self-Service

1. Open Portal in incognito: `http://localhost:3001`
2. Click **"Sign Up"**
3. Create developer account
4. Request API access

---

## Phase 7: CI/CD with Tyk Sync

### Step 1: Extract API Definitions

```bash
cd docker/self-managed

export DASHBOARD_API_KEY="<from_System_Management_Users>"

# Extract all APIs
docker run --rm \
  --network tyk \
  -v $(pwd):/app \
  tykio/tyk-sync:v2.1 \
  dump \
  --dashboard http://tyk-dashboard:3000 \
  --secret ${DASHBOARD_API_KEY} \
  --target /app/backup

# View exported files
ls -la backup/
```

### Step 2: Modify API Definition

```bash
# Edit API definitions as needed
vi backup/<api-file>.json
```

### Step 3: Sync Changes Back

```bash
docker run --rm \
  --network tyk \
  -v $(pwd):/app \
  tykio/tyk-sync:v2.1 \
  sync \
  --dashboard http://tyk-dashboard:3000 \
  --secret ${DASHBOARD_API_KEY} \
  --path /app/backup
```

### Step 4: Verify Changes

1. Refresh Dashboard APIs page
2. Verify your changes are applied

**Workflow Examples:** [Tyk Sync Use Cases](https://tyk.io/docs/api-management/sync/use-cases)

---

## Production Considerations

- Check the env files under confs and apply the PROD recommendations noted in comments.

---

## Cleanup

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (DELETES ALL DATA)
docker-compose down -v

# Full cleanup including networks
docker-compose down -v --remove-orphans
docker network prune -f
```

**If using the full repo with Bootstrap Utility:** See [Bootstrap Utility - Cleanup](https://github.com/TykTechnologies/tyk-pocs/blob/main/utils/bootstrap/README.md#-cleanup) for removing bootstrap data and allowing fresh re-bootstrap.

---

## Component Versions

Update versions in `.env`, use the latest versions:

```bash
DASHBOARD_VERSION=v5.12.1
GATEWAY_VERSION=v5.12.1
PUMP_VERSION=v1.14.1
PORTAL_VERSION=v1.17.1
```

---

### Troubleshooting: Portal Login Returns "Bad Request"

Set `PORTAL_DISABLECSRFCHECK=true` in `confs/portal.env`. This is needed when accessing the Portal via HTTP without a proper domain. Set to `false` when using a domain with TLS.

---

## Resources

- [Installation Documentation](https://tyk.io/docs/tyk-self-managed/docker)
- [Tyk Dashboard API](https://tyk.io/docs/tyk-dashboard-api/)
- [Developer Portal](https://tyk.io/docs/portal/overview/getting-started)
- [Tyk Sync](https://tyk.io/docs/api-management/sync/use-cases)
- [Release Notes](https://tyk.io/docs/developer-support/release-notes/overview)
- [Support](https://support.tyk.io/hc/en-gb)
