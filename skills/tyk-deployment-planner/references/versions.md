# Versions

## Where the pins live

This file carries no version numbers on purpose. Read the pin from the target directory:

- Docker and bare metal: `GATEWAY_VERSION`, `DASHBOARD_VERSION`, `PUMP_VERSION`, `PORTAL_VERSION`
  and `MDCB_VERSION` in that directory's `.env.example`.
- Helm: the `image.tag` values inside the directory's `values*.yaml`. The Helm `.env.example`
  files carry chart versions only.

A workflow in the Tyk docs repository (`sync-versions-to-tyk-install.yml`) opens a pull request
here whenever a component is released, so the pins track the latest stable Docker Hub tag. Never
quote a version from memory: a remembered number is the one most likely to be stale. When the user
needs the latest release rather than the repository pin, resolve it live from Docker Hub
(`https://hub.docker.com/v2/repositories/tykio/<image>/tags`) or the GitHub releases API, and say
which source you used.

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
- **The chart's default image tag trails this repository.** tyk-charts 5.4.0 ships Gateway and
  Dashboard `v5.13.2`, Pump `v1.17.0` and MDCB `v2.13.0`, behind the pins here. Every Helm values
  file therefore pins its image tags explicitly — `helm-self-managed` 4, `helm-hybrid` 2,
  `helm-oss` 1, `helm-mdcb` control-plane 4 and data-plane 2. Do not add more; check what actually
  rendered:
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
GATEWAY_VERSION=vX.Y.Z      # the same tag for both: Gateway and Dashboard never split minors
DASHBOARD_VERSION=vX.Y.Z
```

For Helm, pass `--version` to `helm upgrade --install` and set the image tag in an overlay.

Before moving anyone to a newer version, check the release notes for breaking changes and for the
minimum Redis and PostgreSQL versions: <https://tyk.io/docs/developer-support/release-notes/overview>

## Recording what was deployed

Any deployment summary must state the versions actually running, read back from the deployment
rather than from this file:

```bash
curl -s http://localhost:8080/hello | jq -r '.version'
docker compose images
kubectl get pods -n tyk -o jsonpath='{.items[*].spec.containers[*].image}'
```
