# Versions

## Pinned set

Every **Docker and bare-metal** `.env.example` pins these. Use them unless the user asks
otherwise. The Helm `.env.example` files do **not** carry version variables — on those paths the
version lives in the image tags inside `values.yaml`, so read it there.

| Component | Version | Variable |
| --- | --- | --- |
| Gateway | `v5.14.0` | `GATEWAY_VERSION` |
| Dashboard | `v5.14.0` | `DASHBOARD_VERSION` |
| Pump | `v1.16.0` | `PUMP_VERSION` |
| Developer Portal | `v1.18.0` | `PORTAL_VERSION` |

Read the actual value from the target directory's `.env.example` rather than trusting this table —
these are refreshed periodically, and the `.env.example` is the source of truth.

## Compatibility rules

- **Never mix Gateway and Dashboard minor versions.** The Dashboard writes API definitions the
  Gateway must understand; a mismatch fails in ways that look like configuration bugs. Keep both
  on the same `5.x`.
- **Upgrade the control plane before the data planes.** On MDCB or hybrid, a newer data plane
  against an older control plane is unsupported. The reverse is tolerated during a rolling
  upgrade.
- **Pump is versioned independently** and is generally tolerant of Gateway versions, but its
  sinks are not: Elasticsearch support covers major versions 3, 5, 6, and 7 only. Pointing it at
  Elasticsearch 8 fails at startup and restart-loops.
- **Helm chart versions are not component versions.** The `tyk-stack` chart version and the
  Gateway image tag move independently; pin both. Note the Helm READMEs currently pin only the
  Bitnami dependencies and cert-manager — the Tyk chart itself is installed unpinned, so
  `helm repo update` can change it. Pass `--version` yourself.
- **The chart's default image tag trails this repository.** `tyk-helm/tyk-oss` shipped Gateway
  `v5.9.1`, and `tyk-stack`/`tyk-control-plane` shipped `v5.13.1`, while this repo pins `v5.14.0`.
  Every Helm values file here therefore pins its image tags explicitly — `helm-self-managed` 4,
  `helm-hybrid` 2, `helm-mdcb` control-plane 4 and data-plane 2. Do not add more; check what
  actually rendered:
  `helm template ... | grep -oE 'image: .*tyk.*'`

## Editions and image names

| Edition | Gateway image |
| --- | --- |
| OSS | `tykio/tyk-gateway` |
| Self-Managed, hybrid, MDCB | `tykio/tyk-gateway-ee` |

Using `tyk-gateway-ee` for an OSS deployment, or `tyk-gateway` where a licensed feature is needed,
is a common and confusing mistake. The `-ee` build is the licensed Enterprise Edition.

## Changing versions

Override in `.env` rather than editing `.env.example`:

```bash
GATEWAY_VERSION=v5.13.1
DASHBOARD_VERSION=v5.13.1
```

For Helm, pass `--version` to `helm upgrade --install` and set the image tag in an overlay.

Before moving anyone to a newer version, check the release notes for breaking changes and for the
minimum Redis and PostgreSQL versions: https://tyk.io/docs/developer-support/release-notes/overview

## Recording what was deployed

Any deployment summary must state the versions actually running, read back from the deployment
rather than from this file:

```bash
curl -s http://localhost:8080/hello | jq -r '.version'
docker compose images
kubectl get pods -n tyk -o jsonpath='{.items[*].spec.containers[*].image}'
```
