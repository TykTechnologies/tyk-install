# Tyk Hybrid Data Plane Kubernetes Install - Quick Guide

## Prerequisites

- Kubernetes cluster (EKS/GKE/AKS) running
- kubectl configured and connected
- Helm 3.12+ installed
- Tyk Control Plane (Tyk Cloud or Self-Managed MDCB) set up and running
- MDCB connection credentials (Connection String, Organization ID, API Key, Group ID)

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

# Edit .env file with your MDCB credentials
# Required for Data Plane:
# For Tyk Cloud Hybrid create a Hybrid Data Plane in the Tyk Cloud Console: https://tyk.io/docs/tyk-cloud/environments-deployments/hybrid-gateways
# Once you have Saved the Hybrid Data Plane Config, continue here
#   - TYK_ORG_ID
#   - TYK_API_KEY (Dashboard API key for data plane)
#   - TYK_GROUP_ID
#
# Required for Operator (if using) see step 8. :
#   - TYK_DASHBOARD_URL (e.g., https://your-org.cloud.tyk.io)
#   - TYK_OPERATOR_API_KEY (separate user with appropriate permissions) see step 8.
#   - TYK_OPERATOR_LICENSE
```

**IMPORTANT: Load environment variables:**

```bash
source .env
```

**Note:** The `connectionString` will be configured directly in `values.yaml` (see step 3b).

---

### 3. Create Namespace and Secrets

```bash
# Create namespace
kubectl create namespace tyk-dp

# Create secret for data plane configuration
# NOTE: connectionString is NOT included here - it must be set in values.yaml
kubectl create secret generic tyk-data-plane-conf \
  --namespace tyk-dp \
  --from-literal=APISecret=$TYK_API_SECRET \
  --from-literal=orgId=$TYK_ORG_ID \
  --from-literal=userApiKey=$TYK_API_KEY \
  --from-literal=groupID=$TYK_GROUP_ID

# Verify secret created with all keys filled
kubectl get secret tyk-data-plane-conf -n tyk-dp -oyaml
```

---

### 3b. Configure Connection String in values.yaml

**IMPORTANT:** The `connectionString` cannot be stored in the Kubernetes secret. It must be configured directly in `values.yaml`.

Edit your `values.yaml` file and add the `connectionString` under `global.remoteControlPlane`:

```yaml
global:
  remoteControlPlane:
    useSecretName: "tyk-data-plane-conf"
    enabled: true
    useSSL: true
    sslInsecureSkipVerify: true

    # Add your MDCB connection string here
    connectionString: "__.cloud-ara.tyk.io:443" # Replace with your MDCB endpoint
```

**For Tyk Cloud:** Use `__.cloud-ara.tyk.io:443`
**For Self-Managed:** Use your MDCB endpoint

---

### 4. Install Dependencies (Redis)

```bash
# Add Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Redis
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis \
  --namespace tyk-dp \
  --set auth.enabled=false \
  --version 19.0.2

# Wait for Redis to be ready (~1 minute)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n tyk-dp
```

---

### 5. Install Tyk Data Plane

```bash
# Add Tyk Helm repository
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/
helm repo update

# Install Tyk Data Plane (~30 sec)
helm install tyk-dp tyk-helm/tyk-data-plane \
  --namespace tyk-dp \
  --values values.yaml

# Monitor installation and wait (~30 sec)
kubectl get pods -n tyk-dp -w
# Press Ctrl+C when all pods show "Running" or "Completed"
```

**Expected pods:**

- `gateway-tyk-dp-xxx` - Running
- `pump-tyk-dp-xxx` - Running
- `tyk-redis-xxx` - Running

---

### 6. Access Services

There are three ways to access your Tyk Gateway, ordered from quickest to most production-ready:

#### Option 1: LoadBalancer Service (Quickest for Cloud Deployments)

Expose the gateway via a cloud LoadBalancer. This works out-of-the-box on EKS, GKE, and AKS.

> **Note:** Each LoadBalancer service creates a separate cloud load balancer. For multiple gateways, use Ingress to share a single load balancer.

**LoadBalancer is already enabled in values.yaml:**

```yaml
service:
  type: LoadBalancer
  externalTrafficPolicy: Local
```

**Test Gateway:**

```bash
# Get the LoadBalancer external IP/hostname
kubectl get svc -n tyk-dp

# Wait for EXTERNAL-IP to be assigned
# AWS: Shows hostname (e.g., a1b2c3-123456.us-east-1.elb.amazonaws.com)
# GCP/Azure: Shows IP address

# Replace  with the actual LoadBalancer address
curl <LOADBALANCER-ADDRESS>/hello
```

---

#### Option 2: Port-Forward (Best for Local Testing)

Quick access for local testing without external exposure.

**Update Gateway service in values.yaml:**

```yaml
service:
  type: ClusterIP
```

**Apply changes:**

```bash
helm upgrade tyk-dp tyk-helm/tyk-data-plane \
  --namespace tyk-dp \
  --values values.yaml
```

**Forward and test:**

```bash
# Forward Gateway service to localhost
kubectl port-forward -n tyk-dp svc/<gateway-service> 8080:8080

# Test Gateway
curl http://localhost:8080/hello
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

1. Change service type to `ClusterIP` in values.yaml:

   ```yaml
   service:
     type: ClusterIP
   ```

2. Enable and configure ingress for your cloud provider (see sections below)

3. Apply changes:

   ```bash
   helm upgrade tyk-dp tyk-helm/tyk-data-plane \
     --namespace tyk-dp \
     --values values.yaml

   # Verify ingress created
   kubectl get ingress -n tyk-dp
   ```

4. Test Gateway at `https://gateway.yourdomain.com/hello`

---

##### AWS EKS: ALB Ingress

**Prerequisites:**

1. AWS Load Balancer Controller

**values.yaml configuration:**

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /hello
  hosts:
    - host: gateway.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  # Optional: TLS with ACM certificate
  # annotations:
  #   alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
  #   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxx
  # tls:
  #   - hosts:
  #       - gateway.yourdomain.com
```

---

##### GKE: GCE Ingress

GKE includes the GCE ingress controller by default.

```bash
# Verify HttpLoadBalancing is enabled within the addonsConfig section.
gcloud container clusters describe <cluster-name> --zone <zone>
```

**values.yaml configuration:**

```yaml
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
  #
  # Optional: TLS with self-managed certificate
  # tls:
  #   - secretName: tyk-gateway-tls
  #     hosts:
  #       - gateway.yourdomain.com
```

---

##### AKS: Application Gateway Ingress

**Prerequisites:**

1. Enable AGIC addon or install via Helm for existing Application Gateway.

**values.yaml configuration:**

```yaml
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
```

---

##### NGINX: Ingress

Works on any Kubernetes cluster including on-premises.

**Prerequisites:**

1. Install NGINX Ingress Controller

**values.yaml configuration:**

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: gateway.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  # Optional: TLS with cert-manager
  # annotations:
  #   cert-manager.io/cluster-issuer: letsencrypt-prod
  # tls:
  #   - secretName: tyk-gateway-tls
  #     hosts:
  #       - gateway.yourdomain.com
```

**Test Gateway** at `gateway.yourdomain.com/hello`

---

### 7. Verify Data Plane Connection

```bash
# Check Gateway logs for successful MDCB connection
kubectl logs -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway --tail=50
```

**Verify in Control Plane Dashboard for Self-Managed:**

- Navigate to your Tyk Dashboard for Self-Managed
- Go to System Management > Gateway Nodes
- Your data plane gateway should appear in the list with the Group ID you configured

**Verify in Control Plane Dashboard for Tyk Cloud:**

- Navigate to Tyk Cloud Dashboard
- Go to Deployments --> Click on the relevant Control Plane
- Your Hybrid data plane gateway should appear in the list with the Group ID you configured under Hybrid data planes

---

### 8 (Optional) Install Tyk Operator

Tyk Operator enables declarative API management using Kubernetes CRDs. This is useful for GitOps workflows where you want to manage APIs via Kubernetes manifests.

**Prerequisites:**

- Tyk Operator license key
- Control Plane Dashboard URL (Tyk Cloud or Self-Managed MDCB Dashboard)
- **Separate Dashboard User for Operator** (different from data plane API key)

#### Create a Dedicated User for Operator

**IMPORTANT:** Create a user account with appropriate permissions to manage APIs on the Dashboard through the Operator:

1. Log into your Tyk Dashboard (Cloud or Self-Managed)
2. Navigate to **User Management** > **Users**
3. Click **Add User** to create a new user
4. Set user permissions (recommended: Admin for a Quick setup)
5. For Tyk Cloud, logout of your Tyk Dashboard and login again using your new Operator user credentials
6. Copy the Operator user's API key and set it as `TYK_OPERATOR_API_KEY` in your `.env` file

**Note:** This is a separate API key from `TYK_API_KEY` (used by the data plane). The operator needs its own credentials to create/manage APIs on the Dashboard.

```bash
# Install cert-manager (required for Tyk Operator webhooks)
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.17.4 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Wait for cert-manager to be ready (~30 sec)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=120s

# Create operator configuration secret
# IMPORTANT: Use TYK_OPERATOR_API_KEY (separate user), not TYK_API_KEY
# TYK_URL should point to your Control Plane Dashboard:
#   - Tyk Cloud: https://_____.cloud-ara.tyk.io/
#   - Self-Managed MDCB: https://<dashboard-url>
kubectl create secret generic tyk-operator-conf \
  --namespace tyk-dp \
  --from-literal=TYK_MODE=pro \
  --from-literal=TYK_URL=$TYK_DASHBOARD_URL \
  --from-literal=TYK_AUTH=$TYK_OPERATOR_API_KEY \
  --from-literal=TYK_ORG=$TYK_ORG_ID \
  --from-literal=TYK_OPERATOR_LICENSEKEY=$TYK_OPERATOR_LICENSE

# Verify secret created
kubectl get secret tyk-operator-conf -n tyk-dp

# Install Tyk Operator
helm install tyk-operator tyk-helm/tyk-operator \
  --namespace tyk-dp

# Verify operator is running (~30 sec)
kubectl get pods -n tyk-dp -l control-plane=tyk-operator-controller-manager
```

**Expected additional pod:**

- `tyk-operator-controller-manager-xxx` - Running

**Test Operator (Optional):**
Create a sample API using Tyk Operator CRD to verify it's working. The operator will create the API on your control plane Dashboard, which will then sync to your data plane gateways. Refer to [Tyk Operator documentation](https://tyk.io/docs/api-management/automations/operator) for examples.

---

## Configuration Details

### Secrets Management

**Data Plane Secret (`tyk-data-plane-conf`):**

This secret stores sensitive data for the gateway:

- **APISecret** - Gateway node secret
- **orgId** - Organization ID
- **userApiKey** - Dashboard API key (for data plane)
- **groupID** - Data plane identifier

**IMPORTANT:** The `connectionString` is NOT stored in the secret. It must be configured in `values.yaml` under `global.remoteControlPlane.connectionString`.

**Operator Secret (`tyk-operator-conf`, if using operator):**

This secret stores configuration for the Tyk Operator:

- **TYK_MODE** - Operator mode (pro)
- **TYK_URL** - Dashboard URL
- **TYK_AUTH** - Operator API key (separate user API key)
- **TYK_ORG** - Organization ID
- **TYK_OPERATOR_LICENSEKEY** - Operator license

**View secret:**

```bash
# Data plane secret
kubectl get secret tyk-data-plane-conf -n tyk-dp -o yaml

# Operator secret (if using)
kubectl get secret tyk-operator-conf -n tyk-dp -o yaml

# Note: secrets are base64 encoded
```

**Update secret:**

```bash
# Update data plane API key
kubectl create secret generic tyk-data-plane-conf \
  --namespace tyk-dp \
  --from-literal=APISecret=$TYK_API_SECRET \
  --from-literal=orgId=$TYK_ORG_ID \
  --from-literal=userApiKey=new-api-key \
  --from-literal=groupID=$TYK_GROUP_ID \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Gateway pods to apply changes
kubectl rollout restart deployment -n tyk-dp gateway-tyk-dp-tyk-gateway
```

### MDCB Connection

The data plane connects to the control plane via MDCB (Multi Data Center Bridge) using:

- **Connection String:** The MDCB endpoint URL configured in `values.yaml` at `global.remoteControlPlane.connectionString`
  - Tyk Cloud: `your-mdcb.cloud-ara.tyk.io:443`
  - Self-Managed: Your MDCB endpoint
- **Credentials:** Organization ID, API Key, and Group ID stored in `tyk-data-plane-conf` secret
- **SSL:** Enabled by default for secure communication (`useSSL: true`)
- **RPC Connection:** Gateway pulls API definitions and configuration via RPC from control plane
- **Analytics:** Can be sent directly to control plane via RPC or through Tyk Pump

## Useful Commands

### View Logs

```bash
# Gateway logs
kubectl logs -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway --tail=50 -f

# Pump logs (if enabled)
kubectl logs -n tyk-dp -l app=pump-tyk-dp-tyk-pump --tail=50 -f
```

### Check Status

```bash
# All pods
kubectl get pods -n tyk-dp

# All services
kubectl get svc -n tyk-dp

# Recent events
kubectl get events -n tyk-dp | tail -20
```

### Restart Components

```bash
kubectl rollout restart deployment -n tyk-dp gateway-tyk-dp-tyk-gateway
kubectl rollout restart deployment -n tyk-dp pump-tyk-dp-tyk-pump
```

### Scale Gateway

```bash
# Manual scaling
kubectl scale deployment gateway-tyk-dp-tyk-gateway -n tyk-dp --replicas=3

# Check scaling
kubectl get pods -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway
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
kubectl describe pod -n tyk-dp <pod-name>

# Check recent events
kubectl get events -n tyk-dp | tail -20
```

### Secret Issues

```bash
# Verify secret exists
kubectl get secret tyk-data-plane-conf -n tyk-dp -oyaml
# to check values
kubectl get secret tyk-data-plane-conf -n tyk-dp -o jsonpath='{.data.APISecret}' | base64 -d && echo
# Make sure all values are correct.

# Recreate secret if needed
kubectl delete secret tyk-data-plane-conf -n tyk-dp
# you may need to re-export the env in your terminal session (step 2).
# Then run step 3 again
```

### Gateway Not Connecting to MDCB

```bash
# Check Gateway logs for connection errors
kubectl logs -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway --tail=100

# Common issues:
# 1. Incorrect or empty MDCB connection string
# 2. Invalid API credentials
# 3. Network/firewall blocking connection
# 4. SSL certificate issues
```

### APIs Not Loading in Gateway

APIs are managed from the control plane. If APIs aren't loading:

1. Verify the API is published in the Dashboard
2. Check that the API has the correct Group ID tag matching your data plane

---

## Cleanup

```bash
# Remove Tyk Data Plane
helm uninstall tyk-dp -n tyk-dp
# Remove Tyk Operator
helm uninstall tyk-operator -n tyk-dp

# Remove Redis (DELETES ALL DATA)
helm uninstall tyk-redis -n tyk-dp

# Remove secrets
kubectl delete secrets -n tyk-dp --all

# Remove PVCs (if you want to delete stored data)
kubectl delete pvc -n tyk-dp --all

# Delete namespace
kubectl delete namespace tyk-dp
```

---

## Resources

- [Installation Documentation](https://tyk.io/docs/tyk-cloud/environments-deployments/hybrid-gateways)
- [How-TO Articles](https://support.tyk.io/hc/en-gb)
