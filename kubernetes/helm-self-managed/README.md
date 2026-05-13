# Tyk Self-Managed Kubernetes PoC - Quick Guide

## Prerequisites

- Kubernetes cluster (EKS/GKE/AKS) running
- kubectl configured and connected
- Helm 3.12+ installed
- Tyk license key

---

## Quick Start

### 1. Prepare Cluster Access

Kubernetes cluster should already be set up and running

**AWS EKS:**

```bash
aws eks update-kubeconfig --region your-rg --name your-cluster-name
```

**GCP GKE:**

```bash
gcloud container clusters get-credentials your-cluster-name --zone us-central1-a
```

**Azure AKS:**

```bash
az aks get-credentials --resource-group your-rg --name your-cluster-name
```

**Verify connection:**

```bash
kubectl get nodes
```

---

### 2. Configure Environment

Copy the `.env.example` file and update with your values:

```bash
cp .env.example .env

# Edit .env file with your license key
# Required: TYK_LICENSE_KEY
```

**IMPORTANT: Load environment variables:**

```bash
source .env
```

---

### 3. Create Namespace and Secrets

```bash
# Create namespace
kubectl create namespace tyk

# Create secret
kubectl create secret generic tyk-conf \
  --namespace tyk \
  --from-literal=APISecret=$TYK_API_SECRET \
  --from-literal=AdminSecret=$TYK_ADMIN_SECRET \
  --from-literal=DashLicense=$TYK_LICENSE_KEY \
  --from-literal=OperatorLicense=$TYK_OPERATOR_LICENSE \
  --from-literal=DevPortalLicense=$TYK_PORTAL_LICENSE \
  --from-literal=adminUserFirstName=$ADMIN_FIRST_NAME \
  --from-literal=adminUserLastName=$ADMIN_LAST_NAME \
  --from-literal=adminUserEmail=$ADMIN_EMAIL \
  --from-literal=adminUserPassword=$ADMIN_PASSWORD \
  --from-literal=DashDatabaseConnectionString="$DashDatabaseConnectionString" \
  --from-literal=DevPortalDatabaseConnectionString="$DevPortalDatabaseConnectionString"

# Create dev portal secret
kubectl create secret generic secrets-tyk-tyk-dev-portal \
  -n tyk \
  --from-literal=adminUserPassword=$ADMIN_PASSWORD \
  --from-literal=adminUserEmail=$ADMIN_EMAIL

# Verify secret created with all keys filled
kubectl get secret tyk-conf -n tyk -oyaml
```

---

### 4. Install Dependencies (PostgreSQL & Redis)

```bash
# Add Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install PostgreSQL (creates required databases)
helm install tyk-postgres bitnami/postgresql \
  --set image.repository=bitnamilegacy/postgresql \
  --namespace tyk \
  --set auth.username=$POSTGRES_USER \
  --set auth.password=$POSTGRES_PASSWORD \
  --set auth.database=$POSTGRES_DB \
  --set primary.initdb.scripts."init\.sql"="CREATE DATABASE portal;" \
  --set primary.persistence.size=20Gi \
  --version 12.12.10

# Install Redis
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis \
  --namespace tyk \
  --set auth.enabled=false \
  --version 19.0.2

# Wait for databases to be ready (~2 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n tyk
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n tyk

# Install cert-manager (required for Tyk Operator)
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.17.4 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

---

### 5. Install Tyk Stack

```bash
# Add Tyk Helm repository
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/
helm repo update

# Install Tyk (~60 sec)
helm install tyk tyk-helm/tyk-stack \
  --namespace tyk \
  --values values.yaml

# Monitor installation and wait (~60 sec)
kubectl get pods -n tyk -w
# Press Ctrl+C when all pods show "Running" or "Completed"
```

**Expected pods:**

- `gateway-xxx` - Running
- `dashboard-xxx` - Running
- `tyk-pump-xxx` - Running
- `tyk-portal-xxx` - Running
- `tyk-postgres-xxx` - Running
- `tyk-redis-xxx` - Running
- `tyk-tyk-operator-xxx` - Running

---

### 6. Access Services

There are three ways to access your Tyk services, ordered from quickest to most production-ready:

#### Option 1: LoadBalancer Service (Quickest for Cloud Deployments)

Expose services via cloud LoadBalancer. This works out-of-the-box on EKS, GKE, and AKS.

**LoadBalancer is already enabled in values.yaml:**

```yaml
# Gateway
service:
  type: LoadBalancer
  externalTrafficPolicy: Local

# Dashboard
service:
  type: LoadBalancer

# Portal
service:
  type: LoadBalancer
```

**Get service endpoints:**

```bash
# Get all LoadBalancer addresses
kubectl get svc -n tyk

# Wait for EXTERNAL-IP to be assigned
# AWS: Shows hostname (e.g., a1b2c3-123456.us-east-1.elb.amazonaws.com)
# GCP/Azure: Shows IP address

# Test services (replace <LOADBALANCER-ADDRESS> with actual address)
curl <GATEWAY-LB-ADDRESS>/hello
curl <DASHBOARD-LB-ADDRESS>/hello
curl <PORTAL-LB-ADDRESS>/ready
```

**Login to Dashboard:**

```text
URL: http://<DASHBOARD-LB-ADDRESS>
Credentials: See step 7 below
```

---

#### Option 2: Port-Forward (Best for Local Testing)

Quick access for local testing without external exposure.

**Update service types in values.yaml:**

```yaml
# Set all services to ClusterIP
service:
  type: ClusterIP
```

**Apply changes:**

```bash
helm upgrade tyk tyk-helm/tyk-stack \
  --namespace tyk \
  --values values.yaml
```

**Forward services and test:**

```bash
# Forward all services (run each in separate terminal)
kubectl port-forward -n tyk svc/dashboard-svc-tyk-tyk-dashboard 3000:3000
kubectl port-forward -n tyk svc/gateway-svc-tyk-tyk-gateway 8080:8080
kubectl port-forward -n tyk svc/dev-portal-svc-tyk-tyk-dev-portal 3001:3001

# Access URLs:
# Dashboard: http://localhost:3000
# Gateway:   http://localhost:8080
# Portal:    http://localhost:3001
```

---

#### Option 3: Ingress (Production Setup with Custom Domain)

Configure Ingress for production deployments with custom domains, TLS, and shared load balancing.

##### Prerequisites by Cloud Provider

| Cloud       | Ingress Controller           | Setup                                             |
| ----------- | ---------------------------- | ------------------------------------------------- |
| **AWS EKS** | AWS Load Balancer Controller | See [AWS Setup](#aws-eks-alb-ingress)             |
| **GKE**     | GCE                          | See [GKE Setup](#gke-gce-ingress)                 |
| **AKS**     | AGIC or NGINX                | See [AKS Setup](#aks-application-gateway-ingress) |
| **Any**     | NGINX Ingress                | See [NGINX Setup](#nginx-ingress)                 |

##### General Steps

1. Change service types to `ClusterIP` in values.yaml:

   ```yaml
   service:
     type: ClusterIP
   ```

2. Enable and configure ingress for your cloud provider (see sections below)

3. Apply changes:

   ```bash
   helm upgrade tyk tyk-helm/tyk-stack \
     --namespace tyk \
     --values values.yaml

   # Verify ingress created
   kubectl get ingress -n tyk
   ```

4. Test services at your custom domains

---

##### AWS EKS: ALB Ingress

**Prerequisites:**

1. AWS Load Balancer Controller installed
2. ACM certificate created for your domain

**values.yaml configuration:**

For each service (Gateway, Dashboard, Portal), update the ingress section:

```yaml
# Example for Gateway
tyk-gateway:
  gateway:
    ingress:
      enabled: true
      className: alb
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
        alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxx
        alb.ingress.kubernetes.io/healthcheck-path: /hello
      hosts:
        - host: gateway.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - hosts:
            - gateway.yourdomain.com

# Dashboard
tyk-dashboard:
  dashboard:
    ingress:
      enabled: true
      className: alb
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing # Use "internal" for production
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
        alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxx
      hosts:
        - host: dashboard.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - hosts:
            - dashboard.yourdomain.com

# Portal (similar configuration)
```

**Security Note:** For production, set Dashboard and Portal to `scheme: internal` and use VPN or IP allowlisting.

---

##### GKE: GCE Ingress

GKE includes the GCE ingress controller by default.

```bash
# Verify HttpLoadBalancing is enabled
gcloud container clusters describe <cluster-name> --zone <zone>
```

**values.yaml configuration:**

```yaml
# Gateway
tyk-gateway:
  gateway:
    ingress:
      enabled: true
      className: gce
      hosts:
        - host: gateway.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      # Optional: TLS with Google-managed certificate
      # annotations:
      #   networking.gke.io/managed-certificates: tyk-gateway-cert
      # tls: []

# Dashboard
tyk-dashboard:
  dashboard:
    ingress:
      enabled: true
      className: gce
      hosts:
        - host: dashboard.yourdomain.com
          paths:
            - path: /
              pathType: Prefix

# Portal (similar configuration)
```

---

##### AKS: Application Gateway Ingress

**Prerequisites:**

1. Enable AGIC addon or install via Helm for existing Application Gateway

**values.yaml configuration:**

```yaml
# Gateway
tyk-gateway:
  gateway:
    ingress:
      enabled: true
      className: azure-application-gateway
      annotations:
        appgw.ingress.kubernetes.io/health-probe-path: /hello
        appgw.ingress.kubernetes.io/backend-protocol: "http"
      hosts:
        - host: gateway.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      # Optional: TLS configuration
      # annotations:
      #   appgw.ingress.kubernetes.io/ssl-redirect: "true"
      # tls:
      #   - secretName: tyk-gateway-tls
      #     hosts:
      #       - gateway.yourdomain.com

# Dashboard and Portal (similar configuration)
```

---

##### NGINX Ingress

Works on any Kubernetes cluster including on-premises.

**Prerequisites:**

1. Install NGINX Ingress Controller
2. (Optional) Install cert-manager for automatic TLS

**values.yaml configuration:**

```yaml
# Gateway
tyk-gateway:
  gateway:
    ingress:
      enabled: true
      className: nginx
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      hosts:
        - host: gateway.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: tyk-gateway-tls
          hosts:
            - gateway.yourdomain.com

# Dashboard
tyk-dashboard:
  dashboard:
    ingress:
      enabled: true
      className: nginx
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
        # For production, add IP allowlisting:
        # nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12"
      hosts:
        - host: dashboard.yourdomain.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: tyk-dashboard-tls
          hosts:
            - dashboard.yourdomain.com

# Portal (similar configuration)
```

---

### 7. Get Admin Credentials

```bash
# Get admin email
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.adminUserEmail}' | base64 -d && echo

# Get admin password
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.adminUserPassword}' | base64 -d && echo
```

**Login to Dashboard** using the credentials above at the appropriate URL from step 6.

---

### 8. Quick Test - Create Your First API

```bash
# Login to Dashboard first to get your API key
# Dashboard > Users > Your User > API Access Credentials
# Or get the bootstrap-generated API key from bootstrap job logs:
kubectl logs -n tyk -l app=bootstrap-tyk-tyk-bootstrap

# Set your Dashboard API key
DASH_API_KEY="your-dashboard-api-key-here"

# Get your Gateway URL (LoadBalancer, port-forward, or ingress)
GATEWAY_URL="http://localhost:8080"  # Adjust based on your setup

# Create a test API
curl -X POST http://localhost:3000/api/apis/oas \
  -H "Authorization: $DASH_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
          "info": {
            "description": "Test API using httpbin.org for PoC demonstration",
            "title": "Httpbin Test API",
            "version": "1.0.0"
          },
          "openapi": "3.0.3",
          "servers": [{"url": "https://httpbingo.org/"}],
          "security": [],
          "paths": {
            "/anything/{path}": {
              "get": {
                "operationId": "anythingRequest",
                "parameters": [{"in": "path", "name": "path", "required": true, "schema": {"type": "string"}}],
                "responses": {"200": {"description": "Successful response"}},
                "summary": "Returns anything passed in request"
              }
            },
            "/get": {
              "get": {
                "operationId": "getRequest",
                "responses": {"200": {"description": "Successful response"}},
                "summary": "HTTP GET test endpoint"
              }
            },
            "/post": {
              "post": {
                "operationId": "postRequest",
                "responses": {"200": {"description": "Successful response"}},
                "summary": "HTTP POST test endpoint"
              }
            }
          },
          "components": {
            "securitySchemes": {}
          },
          "x-tyk-api-gateway": {
            "info": {
              "name": "Httpbin Test API (OAS)",
              "state": {"active": true, "internal": false}
            },
            "upstream": {
              "proxy": {"enabled": false, "url": ""},
              "url": "https://httpbingo.org/"
            },
            "server": {
              "listenPath": {"value": "/httpbin/", "strip": true}
            },
            "middleware": {
              "global": {"trafficLogs": {"enabled": true}}
            }
          }
        }'

# Test the API through the Gateway
curl $GATEWAY_URL/httpbin/get
# Should return JSON from httpbingo.org

# Check Dashboard > Monitoring > Activity to see the request
```

---

## Configuration Details

### Secrets Management

**Main Secret (`tyk-conf`):**

Stores all sensitive configuration for the Tyk stack:

- **APISecret** - Shared secret between Gateway & Dashboard for API definition sync
- **AdminSecret** - Dashboard admin API authentication
- **DashLicense** - Dashboard license key
- **OperatorLicense** - Tyk Operator license key
- **DevPortalLicense** - Developer Portal license key
- **adminUserEmail/Password** - Bootstrap admin user credentials
- **DashDatabaseConnectionString** - PostgreSQL connection for Dashboard
- **DevPortalDatabaseConnectionString** - PostgreSQL connection for Portal

**Developer Portal Secret (`secrets-tyk-tyk-dev-portal`):**

Stores Portal-specific credentials:

- **adminUserEmail** - Portal admin email
- **adminUserPassword** - Portal admin password

**View secrets:**

```bash
# View all secret keys
kubectl get secret tyk-conf -n tyk -o yaml

# Decode specific value
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.APISecret}' | base64 -d && echo
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.DashLicense}' | base64 -d && echo
```

**Update secret:**

```bash
# Update license key (must include ALL secret keys)
kubectl create secret generic tyk-conf \
  --namespace tyk \
  --from-literal=APISecret=$TYK_API_SECRET \
  --from-literal=AdminSecret=$TYK_ADMIN_SECRET \
  --from-literal=DashLicense=new-license-key \
  --from-literal=OperatorLicense=$TYK_OPERATOR_LICENSE \
  --from-literal=DevPortalLicense=$TYK_PORTAL_LICENSE \
  --from-literal=adminUserFirstName=$ADMIN_FIRST_NAME \
  --from-literal=adminUserLastName=$ADMIN_LAST_NAME \
  --from-literal=adminUserEmail=$ADMIN_EMAIL \
  --from-literal=adminUserPassword=$ADMIN_PASSWORD \
  --from-literal=DashDatabaseConnectionString="$DashDatabaseConnectionString" \
  --from-literal=DevPortalDatabaseConnectionString="$DevPortalDatabaseConnectionString" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart affected pods to pick up new secret
kubectl rollout restart deployment -n tyk
```

---

## Useful Commands

### View Logs

```bash
# Gateway logs
kubectl logs -n tyk -l app=gateway-tyk-tyk-gateway --tail=50 -f

# Dashboard logs
kubectl logs -n tyk -l app=dashboard-tyk-tyk-dashboard --tail=50 -f

# Pump logs
kubectl logs -n tyk -l app=pump-tyk-tyk-pump --tail=50 -f

# Portal logs
kubectl logs -n tyk -l app=dev-portal-tyk-tyk-dev-portal --tail=50 -f

# Operator logs
kubectl logs -n tyk -l control-plane=tyk-operator-controller-manager --tail=50 -f
```

### Check Status

```bash
# All pods
kubectl get pods -n tyk

# All services
kubectl get svc -n tyk

# Ingress resources
kubectl get ingress -n tyk

# Recent events
kubectl get events -n tyk --sort-by='.lastTimestamp' | tail -20
```

### Restart Components

```bash
kubectl rollout restart deployment -n tyk gateway-tyk-tyk-gateway
kubectl rollout restart deployment -n tyk dashboard-tyk-tyk-dashboard
kubectl rollout restart deployment -n tyk pump-tyk-tyk-pump
kubectl rollout restart deployment -n tyk dev-portal-tyk-tyk-dev-portal
```

### Scale Gateway

```bash
# Manual scaling
kubectl scale deployment gateway-tyk-tyk-gateway -n tyk --replicas=3

# Check scaling
kubectl get pods -n tyk -l app=gateway-tyk-tyk-gateway
```

**Auto-scaling configuration in values.yaml:**

```yaml
tyk-gateway:
  gateway:
    replicaCount: 3
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 8
      averageCpuUtilization: 60
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod details
kubectl describe pod -n tyk <pod-name>

# Check recent events
kubectl get events -n tyk --sort-by='.lastTimestamp' | tail -20

# Check pod logs
kubectl logs -n tyk <pod-name>
```

### Secret Issues

```bash
# Verify secret exists and has all required keys
kubectl get secret tyk-conf -n tyk -oyaml

# Decode and verify specific values
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.APISecret}' | base64 -d && echo
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.DashLicense}' | base64 -d && echo

# If secret is missing or incorrect, recreate it
kubectl delete secret tyk-conf -n tyk
# Re-export environment variables and run step 3 again
source .env
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
kubectl get pods -n tyk -l app.kubernetes.io/name=postgresql

# Test database connectivity from a pod
kubectl exec -it -n tyk deployment/dashboard-tyk-tyk-dashboard -- /bin/sh
# Inside the pod:
# Check if database connection string is available (should show the value)
env | grep DATABASE

# Verify connection string format in secret
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.DashDatabaseConnectionString}' | base64 -d && echo
# Should be: postgresql://user:password@host:5432/database

# Check PostgreSQL logs
kubectl logs -n tyk -l app.kubernetes.io/name=postgresql
```

### License Key Issues

```bash
# Verify license key is set
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.DashLicense}' | base64 -d && echo

# Check Dashboard logs for license errors
kubectl logs -n tyk -l app=dashboard-tyk-tyk-dashboard --tail=100 | grep -i license

# Check license expiration
# Login to Dashboard > Settings > License
```

### Gateway Not Loading APIs

```bash
# Check Gateway is connected to Dashboard
kubectl logs -n tyk -l app=gateway-tyk-tyk-gateway --tail=100

# Force reload Gateway (using APISecret for auth)
API_SECRET=$(kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.APISecret}' | base64 -d)
curl -X GET http://localhost:8080/tyk/reload \
  -H "X-Tyk-Authorization: $API_SECRET"

# Check if APIs are published in Dashboard
# Dashboard > APIs > Check "Published" status
```

### Dashboard Not Accessible

```bash
# Check Dashboard pod status
kubectl get pods -n tyk -l app=dashboard-tyk-tyk-dashboard

# Check Dashboard service
kubectl get svc -n tyk | grep dashboard

# Check Dashboard logs
kubectl logs -n tyk -l app=dashboard-tyk-tyk-dashboard --tail=100

# If using LoadBalancer, verify external IP is assigned
kubectl get svc -n tyk dashboard-svc-tyk-tyk-dashboard

# If using Ingress, verify ingress is created
kubectl get ingress -n tyk
kubectl describe ingress -n tyk <dashboard-ingress-name>
```

### Operator Issues

```bash
# Check operator pod is running
kubectl get pods -n tyk -l control-plane=tyk-operator-controller-manager

# Check operator logs
kubectl logs -n tyk -l control-plane=tyk-operator-controller-manager --tail=100

# Verify operator secret exists
kubectl get secret tyk-operator-conf -n tyk

# Check CRDs are installed
kubectl get crds | grep tyk
```

### Ingress Not Working

```bash
# Verify ingress controller is installed
kubectl get pods -n kube-system | grep ingress  # For NGINX
kubectl get pods -n kube-system | grep aws-load-balancer  # For AWS LB Controller

# Check ingress resource
kubectl get ingress -n tyk
kubectl describe ingress -n tyk <ingress-name>

# For AWS ALB, check AWS console for ALB creation
# For GKE, check Google Cloud Console for Load Balancer

# Verify DNS is pointing to ingress address
nslookup gateway.yourdomain.com
```

---

## Cleanup

```bash
# Remove Tyk Stack
helm uninstall tyk -n tyk

# Remove databases (DELETES ALL DATA)
helm uninstall tyk-postgres -n tyk
helm uninstall tyk-redis -n tyk

# Remove secrets
kubectl delete secrets -n tyk --all

# Remove PVCs (if you want to delete stored data)
kubectl delete pvc -n tyk --all

# Delete namespace
kubectl delete namespace tyk

# Remove cert-manager (ONLY if installed specifically for Tyk)
kubectl delete namespace cert-manager
```

---

## Resources

- [Installation Documentation](https://tyk.io/docs/tyk-self-managed/install#install-on-kubernetes)
- [Tyk Dashboard API](https://tyk.io/docs/tyk-dashboard-api/)
- [Tyk Operator](https://tyk.io/docs/api-management/automations/operator)
- [How-TO Articles](https://support.tyk.io/hc/en-gb)
