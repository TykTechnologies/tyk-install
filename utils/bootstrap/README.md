# Tyk Bootstrap Utility

Containerized bootstrap script that automates the complete initial setup of a Tyk deployment using only Tyk APIs. Creates organization, admin user, test API, credentials, Developer Portal admin, and Dashboard provider connection.

## 🎯 Purpose

Automates the complete initial setup of a Tyk deployment:

**Dashboard Setup:**

- ✅ Creates organization ("Demo Organization")
- ✅ Creates admin user with Dashboard access
- ✅ Sets admin password and API credentials
- ✅ Generates Dashboard API key for management

**API Configuration:**

- ✅ Creates test API using OAS 3.0 format (httpbingo proxy)
- ✅ Creates API policy with rate limits and quotas
- ✅ Generates API key for testing (with alias "test-api-key-123")

**Developer Portal Setup:**

- ✅ Bootstraps Developer Portal with admin user
- ✅ Configures Dashboard provider connection
- ✅ Saves all credentials to file

## 🚀 Usage

### Prerequisites

- Valid `DASH_LICENSE` in `.env` file

### Docker Compose

**1. Set License Key**

Create or edit `.env` file:

```bash
DASH_LICENSE=your-license-key-here
```

Create or edit `.env` file:

```bash
TYK_LICENSE_KEY=your-license-key-here
```

**2. Run Bootstrap**

```bash
# Using the tools profile (recommended)
docker-compose --profile tools run --rm tyk-bootstrap

# Alternative: Direct docker compose run
docker compose run --rm tyk-bootstrap
```

**3. View Credentials**

```bash
cat bootstrap-output/bootstrap-credentials.txt
```
---

### Standalone Script

Run the script directly without Docker:

```bash
# Set environment variables
export DASH_LICENSE="your-license-key"
export DASHBOARD_URL="http://localhost:3000"
export GATEWAY_URL="http://localhost:8080"
export PORTAL_URL="http://localhost:3001"
export ADMIN_SECRET="admin-secret"

# Run script
bash bootstrap.sh
```

## 📋 Environment Variables
| Variable          | Default                     | Required | Description                     |
| ----------------- | --------------------------- | -------- | ------------------------------- |
| `DASH_LICENSE`    | -                           | ✅       | Tyk Dashboard license key       |
| `DASHBOARD_URL`   | `http://tyk-dashboard:3000` | ✅       | Dashboard URL                   |
| `GATEWAY_URL`     | `http://tyk-gateway:8080`   | ✅       | Gateway URL                     |
| `PORTAL_URL`      | `http://tyk-portal:3001`    | ⚠️       | Developer Portal URL (optional) |
| `ADMIN_SECRET`    | `admin-secret`              | ✅       | Dashboard admin API secret      |

**Note**: Portal bootstrapping is optional. If Portal is not running, the script will skip portal configuration and continue.

## 📂 Output

### Docker Compose

Creates `bootstrap-output/bootstrap-credentials.txt` with:

- Dashboard login credentials
- Portal admin credentials
- API testing credentials
- Dashboard API key and Org ID

## ✅ Idempotency

Bootstrap is **idempotent** - safe to run multiple times:

- ✅ Checks if organization exists → uses existing
- ✅ Checks if admin user exists → uses existing
- ✅ Checks if test API exists → uses existing
- ✅ Checks if policy exists → uses existing
- ✅ Checks if API key exists → uses existing
- ✅ Creates marker file (`.bootstrap_completed`) to track completion

**Re-run with existing setup:**

```bash
# Loads existing credentials from file
docker-compose --profile tools run --rm tyk-bootstrap
```

**Force fresh bootstrap** (only if you want to skip checks):

```bash
# Remove marker and credentials
rm -rf bootstrap-output/

# Run bootstrap again
docker-compose --profile tools run --rm tyk-bootstrap
```

## 🧪 What Gets Created

### Organization

- **Name**: "Demo Organization"
- **CNAME**: Enabled
- **Event Options**: Redis hashed key events enabled

### Dashboard Admin User

- **Email**: `admin@example.com`
- **Password**: `topsecret123`
- **Permissions**: Full admin (`IsAdmin: "admin"`)
- **Access Key**: Generated for Dashboard API access

### Test API

- **Name**: "Httpbin Test API (OAS)"
- **Format**: OpenAPI 3.0.3 specification
- **Listen Path**: `/httpbin/` (strip enabled)
- **Target URL**: `https://httpbingo.org/`
- **Authentication**: Auth token required (API key in `Authorization` header)
- **Endpoints**:
  - `GET /httpbin/get` - HTTP GET test
  - `POST /httpbin/post` - HTTP POST test
  - `GET /httpbin/anything/{path}` - Wildcard endpoint
- **Traffic Logs**: Enabled

### Policy

- **Name**: "Test API Policy"
- **Rate Limit**: 1000 requests per 60 seconds
- **Quota**: 1000 requests (allowance)
- **Applies To**: Httpbin Test API

### API Key

- **Alias**: `test-api-key-123`
- **Valid For**: Httpbin Test API
- **Rate Limit**: 1000 requests per 60 seconds
- **Quota**: Unlimited (-1)
- **Format**: Bearer token (use in `Authorization` header)

### Developer Portal (Optional)

- **Admin Email**: `portal-admin@example.com`
- **Admin Password**: `portalpass123`
- **API Token**: Generated for Portal API access
- **Provider**: Tyk Dashboard connection configured

## 🧹 Cleanup

**Remove bootstrap data:**

```bash
rm -rf bootstrap-output/
```

**Full reset (Docker Compose):**

```bash
# Stop all services and remove volumes
docker-compose down -v

# Remove bootstrap data
rm -rf bootstrap-output/

# Start services
docker-compose up -d

# Re-run bootstrap
docker-compose --profile tools run --rm tyk-bootstrap
```

## 🔧 Customization

Edit `bootstrap.sh` to customize:

**Lines 100-109**: Admin user credentials

```bash
"email_address": "admin@example.com"
"new_password": "topsecret123"
```

**Lines 253-310**: Test API configuration (OAS spec)

```bash
# Change target URL, endpoints, authentication
"url": "https://httpbingo.org/"
```

**Lines 358-380**: Policy settings

```bash
"rate": 1000,         # requests
"per": 60,            # seconds
"allowance": 1000     # quota
```

**Lines 470-475**: Portal admin credentials

```bash
"username": "portal-admin@example.com"
"password": "portalpass123"
```

## 🐛 Troubleshooting

**Bootstrap hangs waiting for Dashboard:**

```bash
# Check Dashboard is running
docker-compose ps tyk-dashboard

# Check Dashboard logs
docker-compose logs tyk-dashboard

# Test Dashboard health endpoint
curl http://localhost:3000/hello

# Increase wait time in bootstrap.sh (line 87)
local max_attempts=30  # Change to 60
```

**"DASH_LICENSE not set" error:**

```bash
# Check .env file exists
cat .env

# Verify license key is set
grep DASH_LICENSE .env

```

**"Organization already exists" but credentials missing:**

```bash
# List organizations
curl http://localhost:3000/admin/organisations/ \
  -H "admin-auth: admin-secret"

# Remove marker to re-extract credentials
rm bootstrap-output/.bootstrap_completed

# Re-run bootstrap
docker-compose --profile tools run --rm tyk-bootstrap
```

**Credentials file not created:**

```bash
# Check volume mount
docker-compose run --rm tyk-bootstrap ls -la /bootstrap-output

# Check local directory
ls -la bootstrap-output/

# Check permissions
chmod -R 755 bootstrap-output/
```

**Portal bootstrapping fails:**

```bash
# Check Portal is running
curl http://localhost:3001/hello

# Portal is optional - Dashboard and API work without it
# Skip portal errors if you don't need the Developer Portal
```

**Network "tyk" not found:**

```bash
# Create external network
docker network create tyk

# Or remove "external: true" from docker-compose.yml
```

## 🧪 Testing the Setup

After successful bootstrap:

### 1. Login to Dashboard

```text
URL: http://localhost:3000
Email: admin@example.com
Password: topsecret123
```

### 2. Test the API

```bash
# Get your API key from credentials file
API_KEY=$(grep "Test API Key:" bootstrap-output/bootstrap-credentials.txt | awk '{print $NF}')

curl http://localhost:8080/httpbin/get \
  -H "Authorization: $API_KEY"

```

### 3. Login to Developer Portal (if configured)

```text
URL: http://localhost:3001
Email: portal-admin@example.com
Password: portalpass123
```

### 4. Use Dashboard API

```bash
# Get credentials from file
DASH_KEY=$(grep "Dash Key:" bootstrap-output/bootstrap-credentials.txt | awk '{print $NF}')
ORG_ID=$(grep "Org ID:" bootstrap-output/bootstrap-credentials.txt | awk '{print $NF}')

# List APIs
curl http://localhost:3000/api/apis \
  -H "Authorization: $DASH_KEY"

# List keys
curl http://localhost:3000/api/keys \
  -H "Authorization: $DASH_KEY"
```

## 🔗 Resources

- [Tyk Dashboard API Documentation](https://tyk.io/docs/tyk-dashboard-api/)
- [Organization Management](https://tyk.io/docs/tyk-apis/tyk-dashboard-admin-api/organisations/)
- [OpenAPI Specification](https://tyk.io/docs/getting-started/using-oas-definitions/)
- [Developer Portal Setup](https://tyk.io/docs/tyk-developer-portal/)
- [API Key Management](https://tyk.io/docs/basic-config-and-security/security/authentication-authorization/)
