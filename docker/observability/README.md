# Tyk Observability on Docker

Optional add-on for the [Self-Managed](../self-managed/) and [Hybrid](../hybrid/) deployments: an
OpenTelemetry Collector, Prometheus, Alertmanager, Tempo, Loki and Grafana, with the Tyk dashboards
and alert rules. What it collects, the dashboards and the alerts are described in
[observability/README.md](../../observability/README.md).

## Prerequisites

- A configured Self-Managed or Hybrid deployment (`.env` and `confs/` ready)
- Docker Compose v2.20+ (the overlay uses `include`)
- About 2 GB more RAM
- Docker Engine on Linux, Docker Desktop or OrbStack: the collector reads Docker's container log
  files from `/var/lib/docker/containers`

## Quick Start

### Self-Managed

```bash
cd docker/self-managed
docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d
```

The Gateway sends traces, metrics and logs. The Dashboard and Developer Portal send metrics from
Dashboard 5.16 and Portal 1.20; older versions ignore the settings.

### Hybrid

```bash
cd docker/hybrid
docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d
```

The Gateway sends traces, metrics and logs. The control plane (Tyk Cloud or your MDCB) is monitored
where it runs.

If the deployment is already running, the same command recreates the Tyk containers with the new
settings. Send a few requests through the Gateway, then open Grafana.

## Access URLs

| Service      | URL                     | Description                                   |
| ------------ | ----------------------- | --------------------------------------------- |
| Grafana      | `http://localhost:3002` | Dashboards (folder **Tyk**), Explore, alerts  |
| Prometheus   | `http://localhost:9090` | Metrics and alert rules                       |
| Alertmanager | `http://localhost:9093` | Firing alerts                                 |
| OTLP         | `localhost:4317` (gRPC), `localhost:4318` (HTTP) | For components outside this compose project |

Grafana needs no login. Tempo and Loki are reached through Grafana.

## Verify

```bash
# From the repository root
observability/scripts/smoke-test.sh
```

## What the Overlay Changes

`docker-compose.otel.yml` includes [`docker-compose.yml`](./docker-compose.yml) from this folder and:

- adds `observability/env/gateway.env` (and `dashboard.env`, `portal.env` for Self-Managed) after the
  component's own `confs/*.env`, so its values win
- labels the Tyk services' logs with their compose service name, which the collector uses to keep
  only Tyk's logs
- attaches the Tyk services to the observability services' network, so they reach
  `otel-collector:4317`; the deployment's own network is unchanged

The base `docker-compose.yml` is unchanged; without the overlay nothing is collected.

## Configuration

| File                                          | Purpose                                                  |
| --------------------------------------------- | -------------------------------------------------------- |
| `docker-compose.yml`                          | The observability services                               |
| `confs/prometheus.yml`                        | Scrapes the collector, loads the alert rules             |
| `confs/alertmanager.yml`                      | Alert routing (no receiver by default)                   |
| `confs/tempo.yaml`                            | Trace storage and retention                              |
| `confs/loki.yaml`                             | Log storage and retention                                |
| `confs/grafana/provisioning/`                 | Datasources and the dashboards folder                    |
| [`../../observability/`](../../observability/) | Dashboards, alert rules, collector config, env files   |

Optional settings in the deployment's `.env`:

```bash
# Grafana admin password (anonymous users are already Admin)
GRAFANA_ADMIN_PASSWORD=admin

# Also send everything to another backend (see observability/collector/exporters)
# OTEL_COLLECTOR_EXPORTER=prometheus-remote-write
# PROMETHEUS_REMOTE_WRITE_ENDPOINT=https://mimir.example.com/api/v1/push
# PROMETHEUS_REMOTE_WRITE_HEADERS={"Authorization":"Bearer <token>"}

# Image versions
# OTEL_COLLECTOR_VERSION=0.162.0
# PROMETHEUS_VERSION=v3.15.0
# ALERTMANAGER_VERSION=v0.34.1
# TEMPO_VERSION=3.1.0
# LOKI_VERSION=3.7.8
# GRAFANA_VERSION=13.2.4
```

## Production Considerations

See the [production checklist](../../observability/README.md#production-checklist). On Docker in
particular:

- Grafana's port is published on every interface and anonymous users are Admin: set
  `GF_AUTH_ANONYMOUS_ENABLED=false`, `GF_AUTH_DISABLE_LOGIN_FORM=false` and an admin password.
- The collector runs as root to read the log files. To avoid it, remove `logs-docker.yaml` from its
  command and the `/var/lib/docker/containers` mount.
- With rootless Docker or Podman, the container log files are elsewhere: change the mount.

## Troubleshooting

### No Gateway logs in Grafana

```bash
docker logs tyk-otel-collector 2>&1 | grep -i error
```

Check the containers were recreated with the overlay (`docker inspect tyk-gateway --format
'{{.HostConfig.LogConfig}}'` shows `labels:com.docker.compose.service`), and that Docker stores
its data under `/var/lib/docker`.

### Loki answers 503 or "Ingester is shutting down"

Loki throttles writes when its disk is more than 90% full. Free some Docker disk space
(`docker system df`).

### "all predefined address pools have been fully subnetted"

Docker has run out of network ranges. Remove unused networks with `docker network prune`.

### Tempo logs "error calling scheduler ... no jobs found"

Harmless: Tempo 3's background worker polls for compaction work and logs this at error level while
there is none.

### The control plane dashboards are empty

They need Dashboard 5.16+, Developer Portal 1.20+ and MDCB 2.14+. Check the versions in `.env`.

## Cleanup

```bash
# Stop everything
docker compose -f docker-compose.yml -f docker-compose.otel.yml down

# Also delete the stored metrics, traces, logs and Grafana data (and the Tyk volumes)
docker compose -f docker-compose.yml -f docker-compose.otel.yml down -v
```
