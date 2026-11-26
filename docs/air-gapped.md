# Air-gapped deployments

How to run any path in this repository on hosts with no access to public registries or package
repositories. Tyk's own guide is
[How to install Tyk in air-gapped deployments](https://tyk.io/docs/api-management/air-gapped-deployment);
this page applies it to the files here.

The pattern is the same everywhere: on a connected machine, collect exactly what the chosen path
uses, move it across, and point the deployment at the internal copy. Pick the topology first
([topology matrix](./topology-matrix.md)), because the image and package lists follow from it.

Depending on the licence, the Dashboard can send usage telemetry to Tyk by default. In an
environment with no outbound access, set `TYK_DB_DISABLETELEMETRY=true`
([Dashboard configuration](https://tyk.io/docs/tyk-dashboard/configuration)).

## Docker Compose

Compose lists the images a stack uses, with your `.env` and any overlays applied:

```bash
# On the connected machine, from the target directory, with the same -f files and
# --profile flags you will start the stack with
cd docker/self-managed
docker compose config --images > images.txt
xargs -n 1 docker pull < images.txt
docker save -o tyk-images.tar $(cat images.txt)
```

Move `tyk-images.tar` and the tyk-install checkout to the target, then:

```bash
docker load -i tyk-images.tar
docker compose up -d --pull never
```

`--pull never` makes a missing image an immediate error instead of a hanging pull. The Compose
files keep the public image names, so nothing in them changes. To use an internal registry
instead of `docker save`, re-tag and push each image there and configure the registry as a mirror
in the Docker daemon.

## Kubernetes (Helm)

Pull the chart, then list the images it renders with your values and overlays:

```bash
# On the connected machine
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ && helm repo update
helm pull tyk-helm/tyk-oss --version 5.5.0          # writes tyk-oss-5.5.0.tgz
helm template tyk-oss tyk-oss-5.5.0.tgz -f kubernetes/helm-oss/values.yaml \
  | sed -n 's/^ *image: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' | sort -u
```

Push each image to the internal registry under its full original name, then install from the
`.tgz` with the registry set:

```bash
helm upgrade --install tyk-oss ./tyk-oss-5.5.0.tgz -n tyk -f kubernetes/helm-oss/values.yaml \
  --set global.imageRegistry=registry.example.internal/ \
  --set 'tyk-gateway.gateway.imagePullSecrets[0].name=tyk-registry'
```

- `global.imageRegistry` is prefixed to the whole image name, trailing slash included. An image
  set as `docker.tyk.io/tyk-gateway/tyk-gateway:v5.16.0` is pulled as
  `registry.example.internal/docker.tyk.io/tyk-gateway/tyk-gateway:v5.16.0`, so push it there.
- Pull secrets are set per component, for example `tyk-gateway.gateway.imagePullSecrets` and
  `tyk-pump.pump.imagePullSecrets`. Create the secret with
  `kubectl create secret docker-registry tyk-registry ...`.
- The chart's `helm test` pod uses `zalbiraw/alpine-curl-jq`, which `global.imageRegistry` does
  not rewrite in tyk-charts 5.5.0. Mirror it under that exact name with a node-level registry
  mirror, or skip `helm test` and verify with `tools/verify_deployment.sh`.
- Redis and PostgreSQL come from their own charts (each `kubernetes/*/README.md`); mirror those
  charts and images too, and set each chart's own registry value.
- Tyk Operator has its own chart and image, and needs cert-manager
  ([`kubernetes/standalone-operator/`](../kubernetes/standalone-operator/)): mirror all three.

## Bare metal

`baremetal/install.sh --mirror` installs from an internal copy of Tyk's package repositories,
and still checks signatures. [`baremetal/README.md`](../baremetal/README.md), "Air-gapped hosts",
has the mirror layout and how to build it.
