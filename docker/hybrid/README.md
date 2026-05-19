# Tyk Hybrid Data Plane Docker Install - Quick Guide

## Prerequisites

- Docker installed
- Tyk Control Plane (Tyk Cloud or Self-Managed with MDCB) set up and running
- MDCB connection credentials from your control plane:
  - Connection String (MDCB endpoint)
  - Organization ID
  - Dashboard User API Key
  - Group ID

---

## Quick Start

### 1. Clone and Configure

```bash
cd docker/hybrid

# Copy example env file
cp .env.example .env

# Edit .env file (optional - mainly for version pinning)
```

---

### 2. Get MDCB Credentials from Control Plane

#### For Tyk Cloud

1. Login to [Tyk Cloud Console](https://account.cloud-ara.tyk.io/)
2. Navigate to **Deployments** > Select your Control Plane
3. Save the configuration:
   - **Connection String** (e.g., `xxx.cloud-ara.tyk.io:443`)
   - **Organization ID**
   - **API Key**
   - **Group ID**

#### For Self-Managed MDCB

1. Login to your Tyk Dashboard
2. Get your **Organization ID** from Dashboard settings
3. Create a Dashboard user and get their **API Key**
4. Use your **MDCB endpoint** as the connection string
5. Choose a **Group ID** to identify this data plane cluster

---

### 3. Configure Gateway and Pump

Edit `confs/tyk.env` and set the required MDCB credentials:

```bash
# REQUIRED: Set these values from your control plane
TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING=your-mdcb.cloud-ara.tyk.io:443
TYK_GW_SLAVEOPTIONS_RPCKEY=your-org-id
TYK_GW_SLAVEOPTIONS_APIKEY=your-dashboard-api-key
TYK_GW_SLAVEOPTIONS_GROUPID=your-group-id
```

Edit `confs/pump.env` with the same credentials:

```bash
# REQUIRED: Set these values (same as gateway)
TYK_PMP_PUMPS_HYBRID_META_CONNECTIONSTRING=your-mdcb.cloud-ara.tyk.io:443
TYK_PMP_PUMPS_HYBRID_META_RPCKEY=your-org-id
TYK_PMP_PUMPS_HYBRID_META_APIKEY=your-dashboard-api-key
TYK_PMP_PUMPS_HYBRID_META_GROUPID=your-group-id
```

---

### 4. Start Services

```bash
# Start all services
docker-compose up -d

# Verify services are running
docker-compose ps
```

**Expected containers:**

- `tyk-gateway` - Running (port 8080)
- `tyk-pump` - Running
- `tyk-redis` - Running (port 6379)

Wait for health checks to pass (~30 seconds):

```bash
# Watch container status
docker-compose ps

# Check logs if needed
docker-compose logs -f
```

---

### 5. Verify Connection to Control Plane

```bash
# Check Gateway logs for successful MDCB connection
docker-compose logs tyk-gateway

# Test Gateway health
curl http://localhost:8080/hello
```

**Verify in Control Plane Dashboard:**

**For Tyk Cloud:**

1. Navigate to Tyk Cloud Console
2. Go to **Deployments** > Click on your Control Plane
3. Your hybrid data plane should appear under **Hybrid data planes**

**For Self-Managed:**

1. Navigate to your Tyk Dashboard
2. Go to **System Management** > **Gateway Nodes**
3. Your data plane gateway should appear with the configured Group ID

---

### 6. Test with an API

APIs are managed from the control plane. Create an API in your Dashboard:

1. Login to your Dashboard (Tyk Cloud or Self-Managed)
2. Navigate to **APIs** > **Add New API**
3. Configure API details (e.g., httpbingo.org proxy)
4. **Important:** Ensure the API is assigned to the correct segment/group if using API segmentation
5. Save and publish

Test through your hybrid gateway:

```bash
# Replace with your API listen path
curl http://localhost:8080/your-api-path/get
```

---

## Access URLs

| Service | URL                     | Description                 |
| ------- | ----------------------- | --------------------------- |
| Gateway | `http://localhost:8080` | Hybrid API Gateway          |
| Redis   | `localhost:6379`        | Local cache/session storage |

**Control Plane (managed separately):**

- Dashboard UI and API management are on your Tyk Cloud or Self-Managed control plane

---

## Configuration Details

### Environment Files

| File             | Purpose                          |
| ---------------- | -------------------------------- |
| `.env`           | Component versions               |
| `confs/tyk.env`  | Gateway configuration (MDCB)     |
| `confs/pump.env` | Pump configuration (hybrid pump) |

> **Note for AWS Fargate and similar platforms:** These env files serve as a reference for required environment variables. For Fargate/ECS deployments, configure these variables directly in your Task Definitions and use AWS Secrets Manager for sensitive values.

### Required MDCB Configuration

**Gateway (`confs/tyk.env`):**

| Variable                               | Description                                      |
| -------------------------------------- | ------------------------------------------------ |
| `TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING` | MDCB endpoint (e.g., `xxx.cloud-ara.tyk.io:443`) |
| `TYK_GW_SLAVEOPTIONS_RPCKEY`           | Organization ID                                  |
| `TYK_GW_SLAVEOPTIONS_APIKEY`           | Dashboard User API Key                           |
| `TYK_GW_SLAVEOPTIONS_GROUPID`          | Data plane cluster identifier                    |

**Pump (`confs/pump.env`):**

| Variable                                     | Description                     |
| -------------------------------------------- | ------------------------------- |
| `TYK_PMP_PUMPS_HYBRID_META_CONNECTIONSTRING` | MDCB endpoint (same as gateway) |
| `TYK_PMP_PUMPS_HYBRID_META_RPCKEY`           | Organization ID                 |
| `TYK_PMP_PUMPS_HYBRID_META_APIKEY`           | Dashboard User API Key          |
| `TYK_PMP_PUMPS_HYBRID_META_GROUPID`          | Data plane cluster identifier   |

### Secrets Management

**Sensitive values in config files:**

- **TYK_GW_SECRET** - Gateway API secret (should match control plane)
- **TYK_GW_SLAVEOPTIONS_APIKEY** - Dashboard API key for MDCB auth
- **TYK_PMP_PUMPS_HYBRID_META_APIKEY** - Same API key for pump

---

## Troubleshooting

### Gateway Not Connecting to MDCB

**Symptom:** Gateway logs show connection errors or APIs don't load

```bash
# Check Gateway logs for connection errors
docker-compose logs tyk-gateway

# Common issues:
# 1. Incorrect MDCB connection string
# 2. Invalid API credentials (org ID, API key)
# 3. Network/firewall blocking outbound connection to MDCB
# 4. SSL certificate issues
```

### APIs Not Loading

**Symptom:** Gateway returns 404 for APIs that exist in Dashboard

1. Verify API is published in the control plane Dashboard
2. Check API segmentation - if using Group IDs, ensure API is assigned to this data plane's group
3. Check Gateway logs for sync errors:

```bash
docker-compose logs tyk-gateway
```

---

## Production Considerations

- Check the env files under `confs/` and apply the PROD recommendations noted in comments

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

---

## Component Versions

Update versions in `.env`:

```bash
GATEWAY_VERSION=v5.12.1
PUMP_VERSION=v1.14.1
```

---

## Resources

- [Hybrid Gateway Documentation](https://tyk.io/docs/tyk-cloud/environments-deployments/hybrid-gateways)
- [MDCB Configuration](https://tyk.io/docs/tyk-multi-data-centre/)
- [Tyk Cloud Console](https://account.cloud-ara.tyk.io/)
- [Release Notes](https://tyk.io/docs/developer-support/release-notes/overview)
- [Support](https://support.tyk.io/hc/en-gb)
