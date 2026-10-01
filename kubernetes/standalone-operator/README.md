# Tyk Operator for Kubernetes

Deploy and manage Tyk APIs using Tyk Kubernetes CRDs.

## 🎯 What is Tyk Operator?

Tyk Operator is a native Kubernetes operator, allowing you to define and manage APIs as code. This means you can deploy, update, and secure APIs using the same declarative configuration approach Kubernetes uses for other application components.

The Tyk Operator extends Kubernetes with custom resources for managing Tyk APIs:

- **TykOasApiDefinition** – Defines configuration of OpenAPI based API definition managed by Tyk.
- **ApiDefinition** – Defines configuration of Classic (non-OAS) Tyk API definition.
- **TykStreamsApiDefinition** – Defines configuration of Tyk Streams APIs.
- **SecurityPolicy** – Defines configuration of security policies and access control for APIs.
- **SubGraph** – Defines GraphQL federation subgraph .
- **SuperGraph** – Defines GraphQL federation supergraph.
- **OperatorContext** – Controls the operational context and behavior of the Tyk Operator (inc API ownership).

**Benefits**:

- GitOps-friendly API management
- Declarative API configuration (manage APIs like K8s resources)
- Kubernetes-native workflows
- CI/CD integration with ArgoCD/Flux
- Single Source of Truth for API Configurations
- Tyk Operator Reconciles any divergence between Kubernetes desired state and the actual state in Tyk Gateway or Tyk Dashboard.

**Important**: Tyk Operator requires an existing Tyk control plane and data plane to work.

## 📋 Prerequisites

- **Existing Tyk Dashboard** (running and accessible)
- Dashboard API credentials (User API Key + Org ID)
- Kubernetes 1.19+
- Helm 3.x
- kubectl configured

## 🚀 Installation

**Prerequisites**:

Tyk Operator enables declarative API management using Kubernetes CRDs. This is useful for GitOps workflows where you want to manage APIs via Kubernetes manifests.

**Prerequisites:**

- You must have a running Tyk Dashboard. The Operator connects to an existing Dashboard to manage APIs via CRDs.
- Tyk Operator license key
- Control Plane Dashboard URL
- **Separate Dashboard User for Operator**

### Create a Dedicated User for Operator

**IMPORTANT:** Create a user account with appropriate permissions to manage APIs on the Dashboard through the Operator:

1. Log into your Tyk Dashboard (Cloud or Self-Managed)
2. Navigate to **User Management** > **Users**
3. Click **Add User** to create a new user
4. Set user permissions (recommended: Admin for a Quick setup)
5. For Tyk Cloud, logout of your Tyk Dashboard and login again using your new Operator user credentials
6. Copy the Operator user's API key and set it as `TYK_OPERATOR_API_KEY` in your `.env` file

**Note:** The operator needs its own credentials to create/manage APIs on the Dashboard.

```bash
# Add Helm repo
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/

kubectl create namespace tyk-operator

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
# TYK_URL should point to your Control Plane Dashboard: e.g https://<dashboard-url>
kubectl create secret generic tyk-operator-conf \
  --namespace tyk-operator \
  --from-literal=TYK_MODE=pro \
  --from-literal=TYK_URL=$TYK_DASHBOARD_URL \
  --from-literal=TYK_AUTH=$TYK_OPERATOR_API_KEY \
  --from-literal=TYK_ORG=$TYK_ORG_ID \
  --from-literal=TYK_OPERATOR_LICENSEKEY=$TYK_OPERATOR_LICENSE

# Verify secret created
kubectl get secret tyk-operator-conf -n tyk-operator

# Install Tyk Operator
helm install tyk-operator tyk-helm/tyk-operator \
  --namespace tyk-operator

# Verify operator is running (~30 sec)
kubectl get pods -n tyk-operator -l control-plane=tyk-operator-controller-manager
```

**Expected pod:**

- `tyk-operator-controller-manager-xxx` - Running

**Test Operator (Optional):**
Create a sample API using Tyk Operator CRD to verify it's working. The operator will create the API on your control plane Dashboard, which will then sync to your data plane gateways. Refer to [Tyk Operator documentation](https://tyk.io/docs/api-management/automations/operator) for examples.

---

## 📝 Creating APIs with CRDs

### Example 1: OAS API

```yaml
apiVersion: tyk.tyk.io/v1alpha1
kind: TykOasApiDefinition
metadata:
  name: petstore
  namespace: tyk-operator
spec:
  tykOAS:
    info:
      title: Petstore API
      version: 1.0.0
    servers:
      - url: https://petstore.swagger.io/v2
    paths:
      /pet:
        get:
          operationId: getPet
          responses:
            "200":
              description: Successful response
    x-tyk-api-gateway:
      info:
        name: petstore
        state:
          active: true
      upstream:
        url: https://petstore.swagger.io/v2
      server:
        listenPath:
          value: /petstore/
          strip: true
```

**Apply:**

```bash
kubectl apply -f examples/tyk-oas-api-crd.yaml
```

### Example 2: Security Policy

```yaml
apiVersion: tyk.tyk.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: standard-policy
  namespace: tyk-operator
spec:
  name: Standard Policy
  active: true
  state: active
  access_rights_array:
    - name: httpbin
      namespace: tyk
      versions:
        - Default
  rate: 100
  per: 60
  quota_max: 1000
  quota_renewal_rate: 3600
```

**Apply:**

```bash
kubectl apply -f examples/security-policy-crd.yaml
```

## Configuration Details

### Secrets Management

**Operator Secret (`tyk-operator-conf`):**

This secret stores configuration for the Tyk Operator:

- **TYK_MODE** - Operator mode (pro)
- **TYK_URL** - Dashboard URL
- **TYK_AUTH** - Operator API key
- **TYK_ORG** - Organization ID
- **TYK_OPERATOR_LICENSEKEY** - Operator license

## 🧪 Testing

```bash
# Check API is created
kubectl get tykoasapidefinition -n tyk-operator

# Describe API
kubectl describe tykoasapidefinition httpbin -n tyk-operator

# Check status
kubectl get tykoasapidefinition httpbin -n tyk -o jsonpath='{.status}'
```

## 🐛 Troubleshooting

**CRD not recognized:**

```bash
# Check CRDs are installed
kubectl get crd | grep tyk

# Reinstall if missing
helm upgrade tyk-operator tyk-helm/tyk-operator -n tyk-operator
```

**API not appearing in Dashboard:**

```bash
# Check operator logs
kubectl logs -n tyk -l app.kubernetes.io/name=tyk-operator -f

# Check API status
kubectl describe tykoasapidefinition <name> -n tyk-operator
```

**Operator pod crash:**

```bash
# Check secret exists
kubectl get secret tyk-operator-conf -n tyk-operator

# Verify secret contents
kubectl get secret tyk-operator-conf -n tyk-operator -o jsonpath='{.data.TYK_AUTH}' | base64 -d && echo

```

## 🔗 Resources

- [Operator Documentation](https://tyk.io/docs/api-management/automations/operator)
