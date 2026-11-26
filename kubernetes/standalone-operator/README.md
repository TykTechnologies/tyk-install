# Tyk Operator for Kubernetes

Deploy and manage Tyk APIs using Tyk Kubernetes CRDs.

## 🎯 What is Tyk Operator?

Tyk Operator is a native Kubernetes operator, allowing you to define and manage APIs as code. This means you can deploy, update, and secure APIs using the same declarative configuration approach Kubernetes uses for other application components.

The Tyk Operator extends Kubernetes with these custom resources (Operator 1.6.0, all in the
`tyk.tyk.io/v1alpha1` API group):

APIs:

- **TykOasApiDefinition** – A Tyk OAS API. The OpenAPI document lives in a ConfigMap that the resource references.
- **ApiDefinition** – A Tyk API definition in the older, non-OAS format. New APIs use TykOasApiDefinition.
- **TykStreamsApiDefinition** – A Tyk Streams API.
- **TykMcpProxyDefinition** – An MCP proxy that publishes an upstream MCP server through the Gateway.
- **SubGraph** – A GraphQL federation subgraph.
- **SuperGraph** – A GraphQL federation supergraph.

Access and credentials:

- **SecurityPolicy** – A security policy: access rights, rate limits and quotas across APIs.
- **TykSession** – A key (token or basic auth) with its access rights and limits. You can bring the credential in a Kubernetes Secret, and the operator writes the result to one.
- **TykOAuthClient** – An OAuth 2.0 client bound to an OAuth-enabled API and a policy.
- **TykCertificate** – A certificate and key from a `kubernetes.io/tls` Secret, uploaded to the Tyk certificate store.

Dashboard objects:

- **TykWebhook** – A reusable Dashboard webhook that API event handlers fire.
- **TykRuleset** – An API governance ruleset (Spectral) for Tyk OAS or MCP APIs, with a none, warn or block action.
- **TykUserGroup** – A Dashboard user group and its RBAC permissions.
- **TykIdentityProfile** – A Tyk Identity Broker profile for single sign-on.
- **PortalConfig** – Settings of the Dashboard's classic developer portal.
- **PortalAPICatalogue** – The classic developer portal's API catalogue.
- **APIDescription** – One API entry in that catalogue.

Operator:

- **OperatorContext** – Which Dashboard (and, for the Kubernetes Gateway API, which data plane) a resource is reconciled against, including API ownership.

The schema of each resource is in the
[Tyk Operator documentation](https://tyk.io/docs/api-management/automations/operator), and
`kubectl explain tykoasapidefinition.spec` prints it from the installed CRDs.

**Benefits**:

- GitOps-friendly API management
- Declarative API configuration (manage APIs like K8s resources)
- Kubernetes-native workflows
- CI/CD integration with ArgoCD/Flux
- Single Source of Truth for API Configurations
- Tyk Operator Reconciles any divergence between Kubernetes desired state and the actual state in Tyk Gateway or Tyk Dashboard.

**Important**: Tyk Operator requires an existing Tyk control plane and data plane to work.

## 📋 Prerequisites

- A running Tyk Dashboard (Tyk Cloud or Self-Managed) that the cluster can reach, and its URL
- A dedicated Dashboard user for the Operator (see below), with its API key and Org ID
- A Tyk Operator licence key
- Kubernetes 1.34 or 1.35, the versions Operator 1.6.0 lists as compatible
- Helm 3 or Helm 4
- kubectl configured for the cluster

## 🚀 Installation

### Create a Dedicated User for Operator

**IMPORTANT:** Create a user account with appropriate permissions to manage APIs on the Dashboard through the Operator:

1. Log into your Tyk Dashboard (Cloud or Self-Managed)
2. Navigate to **User Management** > **Users**
3. Click **Add User** to create a new user
4. Set user permissions (recommended: Admin for a Quick setup)
5. For Tyk Cloud, logout of your Tyk Dashboard and login again using your new Operator user credentials
6. Copy the Operator user's API key and set it as `TYK_OPERATOR_API_KEY` in your `.env` file

**Note:** The operator needs its own credentials to create/manage APIs on the Dashboard.

### Install the Operator

```bash
# Add Helm repo
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/

kubectl create namespace tyk-operator

# Install cert-manager (required for Tyk Operator webhooks)
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.3 \
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
# values.yaml hardens the controller's container, which chart 1.6.0 leaves unset
helm install tyk-operator tyk-helm/tyk-operator --version 1.6.0 \
  --namespace tyk-operator \
  --values values.yaml

# Verify operator is running (~30 sec)
kubectl get pods -n tyk-operator -l control-plane=tyk-operator-controller-manager
```

**Expected pod:**

- `tyk-operator-controller-manager-xxx` - Running

## 📝 Creating APIs with CRDs

Both examples go into the `tyk-operator` namespace. The operator creates the API and the policy on
your control plane Dashboard, which then syncs them to your data plane Gateways.

### Example 1: Tyk OAS API

A `TykOasApiDefinition` does not carry the OpenAPI document itself. The document, with its
`x-tyk-api-gateway` extension, goes into a ConfigMap, and `spec.tykOAS.configmapRef` names the
ConfigMap and the key that holds it:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: petstore-oas
  namespace: tyk-operator
data:
  petstore.json: |
    {
      "openapi": "3.0.3",
      "info": {"title": "Petstore API", "version": "1.0.0"},
      "servers": [{"url": "https://petstore.swagger.io/v2"}],
      "paths": {
        "/pet/{petId}": {
          "get": {
            "operationId": "getPetById",
            "parameters": [
              {"name": "petId", "in": "path", "required": true, "schema": {"type": "integer"}}
            ],
            "responses": {"200": {"description": "Successful response"}}
          }
        }
      },
      "x-tyk-api-gateway": {
        "info": {"name": "petstore", "state": {"active": true}},
        "upstream": {"url": "https://petstore.swagger.io/v2"},
        "server": {"listenPath": {"value": "/petstore/", "strip": true}}
      }
    }
---
apiVersion: tyk.tyk.io/v1alpha1
kind: TykOasApiDefinition
metadata:
  name: petstore
  namespace: tyk-operator
spec:
  tykOAS:
    configmapRef:
      name: petstore-oas
      namespace: tyk-operator
      keyName: petstore.json
EOF
```

The API has no `authentication` block, so it is keyless; add one under
`x-tyk-api-gateway.server` before exposing anything real.

### Example 2: Security Policy

The policy grants access to the `petstore` API from Example 1. `kind` must name the resource type,
because it defaults to `ApiDefinition`:

```bash
kubectl apply -f - <<'EOF'
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
    - name: petstore
      namespace: tyk-operator
      kind: TykOasApiDefinition
      versions:
        - Default
  rate: 100
  per: 60
  quota_max: 1000
  quota_renewal_rate: 3600
EOF
```

### Check the resources

```bash
# List the API and the policy
kubectl get tykoasapidefinitions,securitypolicies -n tyk-operator

# Describe the API: events show reconcile errors
kubectl describe tykoasapidefinition petstore -n tyk-operator

# Status, including the Tyk API ID once it is created
kubectl get tykoasapidefinition petstore -n tyk-operator -o jsonpath='{.status}'
```

---

## Kubernetes Gateway API

From Operator 1.6.0 the operator can also take routes from the Kubernetes Gateway API
(`GatewayClass`, `Gateway`, `HTTPRoute`) and create Tyk OAS APIs in the Dashboard for each route.
It is off by default. It needs Tyk Gateways running in this cluster behind a Kubernetes Service,
because a `Gateway` points at that Service, and those Gateways need
`TYK_GW_ENABLECUSTOMDOMAINS=true` and `TYK_GW_HTTPSERVEROPTIONS_ENABLESTRICTROUTES=true`, so a
route matches on its hostname and `/orders` does not also match `/orders-archive`. Every CRD step
needs cluster-admin. The full walkthrough, with checks, is in the
[self-managed README](../helm-self-managed/README.md#kubernetes-gateway-api-optional).

1. If the operator was first installed with a chart earlier than 1.6.0, update its CRDs. Helm
   installs CRDs on the first install only, so `helm upgrade` leaves the old ones in place:

   ```bash
   helm show crds tyk-helm/tyk-operator --version 1.6.0 | kubectl apply --server-side --force-conflicts -f -
   ```

2. Install the Gateway API CRDs from the experimental channel of v1.6.2, as the Tyk Operator
   documentation specifies:

   ```bash
   kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/experimental-install.yaml
   ```

3. Turn the feature on, and keep the `--set` on every later upgrade. With the flag on and the
   Gateway API CRDs missing, the operator exits at startup.

   ```bash
   helm upgrade tyk-operator tyk-helm/tyk-operator --version 1.6.0 \
     --namespace tyk-operator \
     --values values.yaml \
     --set enableGatewayAPI=true
   ```

4. Create the OperatorContexts, `GatewayClass` and `Gateway` from a copy of
   [`../helm-self-managed/gateway-api/class-and-gateway.yaml`](../helm-self-managed/gateway-api/class-and-gateway.yaml),
   which assumes the self-managed stack in namespace `tyk`. Change:
   - the `tyk-dashboard` OperatorContext's namespace and `secretRef` to `tyk-operator` and
     `tyk-operator-conf`, and the GatewayClass `parametersRef.namespace` to match;
   - the `tyk-data-plane` OperatorContext and the `Gateway` into the namespace of the Service in
     front of your Gateways, with `serviceRef.name` set to that Service. The Gateway looks for its
     `infrastructure.parametersRef` in its own namespace;
   - the listener `port` to a port of that Service;
   - in `example-route.yaml`, the route's `parentRefs[].namespace` to the Gateway's namespace.

---

## Configuration Details

### Secrets Management

**Operator Secret (`tyk-operator-conf`):**

This secret stores configuration for the Tyk Operator:

- **TYK_MODE** - Operator mode (pro)
- **TYK_URL** - Dashboard URL
- **TYK_AUTH** - Operator API key
- **TYK_ORG** - Organization ID
- **TYK_OPERATOR_LICENSEKEY** - Operator license

## 🐛 Troubleshooting

**CRD not recognized:**

```bash
# Check CRDs are installed
kubectl get crd | grep tyk

# Install or update them. Helm installs CRDs on the first install only, so a
# helm upgrade never adds or changes them
helm show crds tyk-helm/tyk-operator --version 1.6.0 | kubectl apply --server-side --force-conflicts -f -
```

**API not appearing in Dashboard:**

```bash
# Check operator logs
kubectl logs -n tyk-operator -l control-plane=tyk-operator-controller-manager -f

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
