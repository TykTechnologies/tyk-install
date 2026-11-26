# Tyk Self-Managed Kubernetes Install - Quick Guide

## Prerequisites

- Kubernetes cluster (EKS/GKE/AKS) running. The bundled Tyk Operator 1.6.0 lists Kubernetes 1.34
  and 1.35 as compatible
- kubectl configured and connected
- Helm 3.12+ or Helm 4 installed
- Tyk license key

> **Red Hat OpenShift?** Follow the steps below, with the changes described in
> [Deploying on Red Hat OpenShift](#deploying-on-red-hat-openshift). It requires tyk-charts 5.4.0 or later.

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

The `bitnamilegacy` Redis and PostgreSQL images receive no further updates and are for evaluation
only; in production use a maintained Redis and PostgreSQL (a managed service or a maintained chart).

```bash
# Install PostgreSQL (creates required databases)
helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set image.repository=bitnamilegacy/postgresql \
  --namespace tyk \
  --set auth.username=$POSTGRES_USER \
  --set auth.password=$POSTGRES_PASSWORD \
  --set auth.database=$POSTGRES_DB \
  --set primary.initdb.scripts."init\.sql"="CREATE DATABASE portal;" \
  --set primary.persistence.size=20Gi \
  --version 12.12.10
  # Required for installing on RedHat OpenShift - add " \" to the --version line
  # above and append these flags (this chart version pins UID/fsGroup 1001,
  # which restricted-v2 rejects):
  # --set primary.podSecurityContext.runAsUser=null \
  # --set primary.podSecurityContext.fsGroup=null \
  # --set primary.containerSecurityContext.runAsUser=null \
  # --set volumePermissions.enabled=false

# Install Redis
# On RedHat OpenShift no extra flags are needed: this chart version detects
# OpenShift and drops its fixed UID/fsGroup so the SCC can assign them.
helm install tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=bitnamilegacy/redis \
  --namespace tyk \
  --set auth.enabled=false \
  --version 19.0.2

# Wait for databases to be ready (~2 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n tyk
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n tyk

# Install cert-manager (required for Tyk Operator)
# Cluster admin privileges required for installing on RedHat OpenShift
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.3 \
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
helm install tyk tyk-helm/tyk-stack --version 5.5.0 \
  --namespace tyk \
  --values values.yaml

# On RedHat OpenShift, layer the OpenShift overlay instead (tyk-charts 5.4.0+):
# helm install tyk tyk-helm/tyk-stack --version 5.5.0 \
#   --namespace tyk \
#   --values values.yaml \
#   --values values-openshift.yaml

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

There are four ways to access your Tyk services, ordered from quickest to most production-ready:

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

> **On OpenShift** skip to *Forward services and test*: `values-openshift.yaml` already sets every
> service to `ClusterIP`, and upgrading with `values.yaml` alone would drop the overlay.

**Update service types in values.yaml:**

```yaml
# Set all services to ClusterIP
service:
  type: ClusterIP
```

**Apply changes:**

```bash
helm upgrade tyk tyk-helm/tyk-stack --version 5.5.0 \
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
   helm upgrade tyk tyk-helm/tyk-stack --version 5.5.0 \
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

#### Option 4: OpenShift Routes (RedHat OpenShift)

OpenShift uses Routes rather than Ingress or LoadBalancer for external access. Routes are created using the `oc` CLI and are automatically assigned a hostname under your cluster's `*.apps` domain.

> **For local testing on OpenShift Local (CRC), port-forwarding (Option 2) is recommended** as it avoids DNS configuration.

**Expose services via Routes:**

```bash
# Expose Dashboard, Gateway, and Portal
oc expose svc dashboard-svc-tyk-tyk-dashboard -n tyk --port=3000
oc expose svc gateway-svc-tyk-tyk-gateway -n tyk --port=8080
oc expose svc dev-portal-svc-tyk-tyk-dev-portal -n tyk --port=3001

# Get the assigned Route URLs
oc get routes -n tyk
```

Routes will be available at URLs such as:

```text
http://dashboard-svc-tyk-tyk-dashboard-tyk.apps.<cluster-domain>
http://gateway-svc-tyk-tyk-gateway-tyk.apps.<cluster-domain>
http://dev-portal-svc-tyk-tyk-dev-portal-tyk.apps.<cluster-domain>
```

**Or, instead of `oc expose`, HTTPS routes with edge termination** (these use the router's `*.apps`
certificate, and plain HTTP redirects to HTTPS):

```bash
oc create route edge dashboard --service=dashboard-svc-tyk-tyk-dashboard --port=3000 --insecure-policy=Redirect -n tyk
oc create route edge gateway --service=gateway-svc-tyk-tyk-gateway --port=8080 --insecure-policy=Redirect -n tyk
oc create route edge portal --service=dev-portal-svc-tyk-tyk-dev-portal --port=3001 --insecure-policy=Redirect -n tyk
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
# Or read the admin user's API key stored by the bootstrap job:
kubectl get secret tyk-operator-conf -n tyk -o jsonpath='{.data.TYK_AUTH}' | base64 -d && echo

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
            "description": "Test API using httpbin.org for Install demonstration",
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

## Deploying on Red Hat OpenShift

tyk-charts 5.4.0 and later install on OpenShift without Kustomize patches. Every security context
block in the Tyk component charts accepts `enabled: false`, which omits the block from the manifest
so OpenShift's Security Context Constraint (SCC), normally `restricted-v2`, assigns the UID and GID
from the namespace's allocated range. [`values-openshift.yaml`](values-openshift.yaml) sets all of
them and switches every service to `ClusterIP`. The same security context settings are
also commented beside each component in `values.yaml` under
`Required for deploying on RedHat OpenShift`.

Run the Quick Start steps with these changes:

| Step | Change on OpenShift |
| --- | --- |
| 1 | `oc login` instead of the cloud CLI. |
| 4 | PostgreSQL needs the commented OpenShift flags. Redis needs none. cert-manager is only for the operator and needs cluster-admin; without cluster-admin, skip it. |
| 5 | Install with the pinned `--version 5.5.0` (OpenShift needs 5.4.0 or later) and layer `--values values-openshift.yaml` (see [Install](#install)). The operator installs cluster-scoped CRDs, so it needs cluster-admin; without it, `helm install` fails with `cannot patch resource "customresourcedefinitions"`. Add `--set global.components.operator=false`, and a cluster admin can add the operator for your namespace later; see [Operator without cluster-admin](#operator-without-cluster-admin). |
| 6 | Use Option 4 (Routes), or Option 2 without its `helm upgrade` (the overlay already sets `ClusterIP`). |
| Every later `helm upgrade` | Pass `--values values-openshift.yaml` again. An upgrade with `values.yaml` alone restores the chart's pinned UID and `fsGroup` defaults, which `restricted-v2` rejects, and the gateway goes down. |

### Install

```bash
helm install tyk tyk-helm/tyk-stack --version 5.5.0 \
  --namespace tyk \
  --values values.yaml \
  --values values-openshift.yaml
```

Do not add `--wait`. The operator needs the `tyk-operator-conf` secret, which the bootstrap job
creates after the install; with `--wait`, Helm never runs that job and the install times out. Until
the job has run (about a minute), the operator pod reports `secret "tyk-operator-conf" not found`.

Verify that every pod was admitted under `restricted-v2` with a UID from the namespace range:

```bash
oc get pods -n tyk -o custom-columns='NAME:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc,UID:.spec.containers[0].securityContext.runAsUser,STATUS:.status.phase'
```

### Things to know

- **Use `enabled: false`, not `{}`.** Helm deep-merges the chart defaults back into an empty
  block, so `securityContext: {}` changes nothing.
- **Disable all three gateway blocks**, including
  `gateway.initContainers.setupDirectories.securityContext`. Left enabled, the init container falls
  back to UID 65532, which `restricted-v2` rejects.

### Operator without cluster-admin

The operator chart creates cluster-scoped CRDs and ClusterRoles, so only a cluster admin can
install it. The team that owns the namespace needs no cluster-admin to use it afterwards.
[`values-operator-namespaced.yaml`](values-operator-namespaced.yaml) makes the operator reconcile
only its own namespace (`WATCH_NAMESPACE`), turns off its admission webhooks so cert-manager is
not needed, and reads the operator licence from `tyk-conf`.

1. The namespace owner installs the stack as in [Install](#install), adding
   `--set global.components.operator=false`. The bootstrap job still writes `tyk-operator-conf`
   with the Dashboard URL, organisation and API key.
2. A cluster admin installs the operator into the same namespace:

   ```bash
   helm install tyk-operator tyk-helm/tyk-operator --version 1.6.0 \
     --namespace tyk \
     --values values-operator-namespaced.yaml
   ```

3. A cluster admin lets namespace admins and editors manage Tyk resources (once per cluster). The
   default `admin` and `edit` roles do not cover custom resources, so without this the namespace
   owner gets `forbidden` when creating a `TykOasApiDefinition`.

   ```bash
   oc apply -f - <<'EOF'
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: tyk-operator-resources-edit
     labels:
       rbac.authorization.k8s.io/aggregate-to-admin: "true"
       rbac.authorization.k8s.io/aggregate-to-edit: "true"
   rules:
     - apiGroups: ["tyk.tyk.io"]
       resources: ["*"]
       verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   EOF
   ```

`WATCH_NAMESPACE` limits which namespace the operator acts on, not its permissions: the chart binds
the operator's ClusterRole cluster-wide. It also limits the
[Kubernetes Gateway API](#kubernetes-gateway-api-optional): the OperatorContexts, `Gateway` and
`HTTPRoute` resources must all be in the watched namespace.

---

## Kubernetes Gateway API (Optional)

From Tyk Operator 1.6.0 (tyk-charts 5.5.0), the operator can take routes from the
[Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). A platform team owns a `GatewayClass`
and a `Gateway`; application teams publish `HTTPRoute` resources, and the operator creates Tyk OAS
APIs in the Dashboard for each route, one per hostname and path group, served by this stack's
Gateways. It is off by default. It needs the Dashboard, so it does not apply to
[helm-oss](../helm-oss/), and every CRD step below needs cluster-admin.

1. If the stack was first installed with tyk-charts earlier than 5.5.0, bring the operator's CRDs
   up to 1.6.0. Helm installs a chart's CRDs on the first install only and never upgrades them, so
   an upgraded release keeps the old ones, and step 4 fails with `unknown field "spec.dataPlane"`.

   ```bash
   helm show crds tyk-helm/tyk-operator --version 1.6.0 | kubectl apply --server-side --force-conflicts -f -
   ```

2. Install the Gateway API CRDs from the **experimental** channel of Gateway API v1.6.2, as the
   Tyk Operator documentation specifies. `--server-side` is required: the CRDs are too large for a
   client-side apply.

   ```bash
   kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/experimental-install.yaml
   ```

   If the cluster already has Gateway API CRDs, check their channel and version before replacing
   them: `kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations}'`.
   On OpenShift 4.19 and later the Ingress Operator owns these CRDs at the version OpenShift
   supports, and CRDs it does not manage block cluster updates
   ([OKD docs](https://docs.okd.io/4.19/networking/ingress_load_balancing/configuring_ingress_cluster_traffic/ingress-gateway-api.html)),
   so do not apply the experimental channel there.

3. Turn the feature on with [`values-gateway-api.yaml`](values-gateway-api.yaml). Install the
   Gateway API CRDs first: with the flag on and the CRDs missing, the operator exits at startup.

   ```bash
   helm upgrade tyk tyk-helm/tyk-stack --version 5.5.0 \
     --namespace tyk \
     --values values.yaml \
     --values values-gateway-api.yaml
   ```

   Add any other files you installed with, such as `--values values-otel.yaml` and its
   `--post-renderer`. From now on pass `values-gateway-api.yaml` on every `helm upgrade`,
   including those in [Access Services](#6-access-services): an upgrade without it turns the flag
   off.

4. Create the class and the Gateway. [`gateway-api/class-and-gateway.yaml`](gateway-api/class-and-gateway.yaml)
   connects them to this stack through two OperatorContexts: one for the Dashboard, using the
   `tyk-operator-conf` secret the bootstrap job writes, and one for the Gateways, using the
   `gateway-svc-tyk-tyk-gateway` Service.

   ```bash
   kubectl apply -f gateway-api/class-and-gateway.yaml
   kubectl wait --for=condition=Accepted gatewayclass/tyk --timeout=60s
   kubectl wait --for=condition=Accepted gateway/tyk -n tyk --timeout=60s
   kubectl get gateway tyk -n tyk   # PROGRAMMED: True once the gateway Service has an address
   ```

   `PROGRAMMED` stays `False` with reason `AddressNotAssigned` while the gateway Service is a
   `LoadBalancer` still waiting for an external address, as on a local cluster. Routes work
   regardless; it turns `True` when the load balancer gets an address, or straight away with
   `ClusterIP` ([Option 2](#option-2-port-forward-best-for-local-testing)).

5. Publish a route. [`gateway-api/example-route.yaml`](gateway-api/example-route.yaml) deploys
   httpbin in the `gateway-api-demo` namespace and routes `api.example.com/orders/*` to it.

   ```bash
   kubectl apply -f gateway-api/example-route.yaml
   kubectl wait --for=condition=available deploy/httpbin -n gateway-api-demo --timeout=180s
   kubectl wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
     httproute/orders -n gateway-api-demo --timeout=120s

   # Skip the port-forward if Option 2 already forwards 8080
   kubectl port-forward -n tyk svc/gateway-svc-tyk-tyk-gateway 8080:8080 &
   sleep 2
   curl -sf --retry 10 --retry-delay 2 --retry-all-errors \
     -H "Host: api.example.com" http://localhost:8080/orders/get
   ```

6. Secure it. [`gateway-api/example-auth.yaml`](gateway-api/example-auth.yaml) attaches a Tyk OAS
   definition that requires an auth token, grants access with a `SecurityPolicy` that names the
   route, and issues one token with a `TykSession`.

   ```bash
   kubectl apply -f gateway-api/example-auth.yaml
   kubectl wait --for=condition=Accepted tykoasapidefinition/orders-security -n gateway-api-demo --timeout=120s
   kubectl wait --for=jsonpath='{.status.latestTransaction.status}'=Successful \
     tyksession/orders-client -n gateway-api-demo --timeout=120s
   TOKEN=$(kubectl get secret orders-client-tyk-key -n gateway-api-demo -o jsonpath='{.data.token}' | base64 -d)
   sleep 5   # the Gateways reload the changed API

   curl -s -o /dev/null -w '%{http_code}\n' -H "Host: api.example.com" http://localhost:8080/orders/get   # 401
   curl -s -o /dev/null -w '%{http_code}\n' -H "Host: api.example.com" -H "Authorization: $TOKEN" \
     http://localhost:8080/orders/get   # 200
   ```

### Things to know

- **Routes carry routing only.** Authentication, rate limits and middleware come from a Tyk OAS
  definition attached to the route or to its `Gateway`. The route owns the routing settings
  (listen path, custom domain, upstream, Gateway tags and a few more), and the operator rejects
  an attached definition that sets them; see
  [Secure and extend routes](https://tyk.io/docs/product-stack/tyk-operator/gateway-api/secure-and-extend-routes).
- **The Gateways need `enableCustomDomains` and `enableStrictRoutes`**, so a route matches on its
  hostname and `/orders` does not also match `/orders-archive`. `values.yaml` sets both.
- **Sharding needs a second Gateway.** This stack runs one Gateway Deployment. Setting
  `tyk-gateway.gateway.sharding.enabled` and `tags` on it makes it load only APIs with those tags,
  which takes every other Dashboard API off the only Gateway, and the chart asks for at least one
  unsharded Gateway. To keep routes on their own Gateways, run a separate, sharded Gateway release
  behind its own Service, and point `dataPlane.serviceRef` and `dataPlane.tags` at it.
- **With the [operator without cluster-admin](#operator-without-cluster-admin)**, the stack's
  operator is off, so `values-gateway-api.yaml` does nothing: set `enableGatewayAPI: true` on the
  `tyk-operator` release instead. The OperatorContexts, `Gateway` and `HTTPRoute` resources must
  be in the watched namespace, so change the examples' `gateway-api-demo` namespace (and the
  route's `parentRefs`) to `tyk`. For namespace owners to publish routes, add
  `gateway.networking.k8s.io` `gateways` and `httproutes` to the aggregated ClusterRole.
- **Turning it off.** While the flag is still on, delete the `SecurityPolicy` resources with
  `HTTPRoute` entries and the attached `TykOasApiDefinition` resources, then the `HTTPRoute`,
  `Gateway` and `GatewayClass` resources, so the operator removes the Tyk APIs and finalizers it
  added. Then upgrade without `values-gateway-api.yaml`. With the flag off, nothing removes them.
  For the examples:
  `kubectl delete -f gateway-api/example-auth.yaml -f gateway-api/example-route.yaml -f gateway-api/class-and-gateway.yaml`.
- Tyk docs: [Get started](https://tyk.io/docs/product-stack/tyk-operator/gateway-api/get-started),
  [reference](https://tyk.io/docs/product-stack/tyk-operator/gateway-api/reference).

---

## Observability (Optional)

OpenTelemetry traces, metrics and logs from every Tyk component, with Prometheus, Alertmanager,
Grafana, Tempo and Loki. After installing the observability stack, add the overlay and the
post-renderer to the install:

```bash
helm upgrade --install tyk tyk-helm/tyk-stack --version 5.5.0 \
  --namespace tyk \
  --values values.yaml \
  --values values-otel.yaml \
  --post-renderer ../observability/post-render.sh
```

With Helm 4, run `helm plugin install ../observability` once and use `--post-renderer tyk-otel`.
See [kubernetes/observability](../observability/) for the full steps.

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

### Portal Login Returns "Bad Request"

Set `PORTAL_DISABLECSRFCHECK=true` in values.yaml under `tyk-dev-portal.extraEnvs`. This is needed when accessing the Portal via HTTP/LoadBalancer IP. Set to `false` when using a proper domain with TLS and Ingress.

### Database Connection Issues

```bash
# Check PostgreSQL is running
kubectl get pods -n tyk -l app.kubernetes.io/name=postgresql

# Check which secret key feeds the Dashboard's connection strings. The Dashboard
# image has no shell, so read the Deployment rather than exec into the pod
kubectl get deploy dashboard-tyk-tyk-dashboard -n tyk -o jsonpath='{.spec.template.spec.containers[0].env}' \
  | jq '.[] | select(.name | test("CONNECTIONSTRING"))'

# Verify connection string format in secret
kubectl get secret tyk-conf -n tyk -o jsonpath='{.data.DashDatabaseConnectionString}' | base64 -d && echo
# Should be: host=<host> port=5432 dbname=<db> user=<user> password=<password> sslmode=<mode>

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

- [Installation Documentation](https://tyk.io/docs/tyk-self-managed/install/kubernetes)
- [Tyk Dashboard API](https://tyk.io/docs/tyk-dashboard-api)
- [Tyk Operator](https://tyk.io/docs/api-management/automations/operator)
- [How-TO Articles](https://support.tyk.io/hc/en-gb)
