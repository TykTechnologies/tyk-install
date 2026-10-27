# Tyk Observability (OpenTelemetry)

Optional traces, metrics and logs for Tyk Gateway, Dashboard, MDCB and Developer Portal. An
OpenTelemetry Collector receives them and sends them to Prometheus, Tempo and Loki. Grafana shows
them in ten ready-made dashboards, and 47 Prometheus alert rules watch them.

The files in this folder are shared by both platforms:

| Platform   | Guide                                                    |
| ---------- | -------------------------------------------------------- |
| Docker     | [docker/observability](../docker/observability/)         |
| Kubernetes | [kubernetes/observability](../kubernetes/observability/) |

## How It Works

```text
Gateway ───┐  OTLP gRPC :4317                ┌─> Prometheus (scrapes :8889) ─┐
Dashboard ─┤  traces and metrics             │     alert rules ─> Alertmanager├─> Grafana
Portal ────┼──────────────> OTel Collector ──┼─> Tempo (traces)              │
MDCB ──────┘                      ▲          └─> Loki (logs) ─────────────────┘
          container logs ─────────┘
```

- Every component pushes OTLP to the collector at `otel-collector:4317`.
- The collector exposes all metrics on `:8889` for Prometheus. Every resource attribute
  (`service.name`, `service.instance.id`, `control_plane_id`, `tyk.gw.id`, ...) becomes a label.
- Traces go to Tempo, and per-span request rate and latency go back into the metrics.
- The collector reads the Tyk containers' logs (JSON for the Gateway) and sends them to Loki, so
  logs carry the API id and trace id of each request.
- Prometheus evaluates the alert rules and sends firing alerts to Alertmanager.

## What Each Component Sends

| Component        | Traces | Metrics                                                                                                       | Needs |
| ---------------- | ------ | ------------------------------------------------------------------------------------------------------------- | ----- |
| Gateway          | Yes    | Requests, latency (total, gateway, upstream), response flags, 22 API metric definitions, runtime, loaded APIs | 5.13+ |
| Dashboard        | -      | Management API, gateway registry, licence, certificates, dependencies, object inventory, governance, runtime  | 5.16+ |
| MDCB             | -      | Data planes, RPC, config and key sync, analytics, dependencies, licence and certificate expiry, runtime       | 2.14+ |
| Developer Portal | -      | Provider sync, dependency health                                                                              | 1.20+ |
| Pump             | -      | None (Pump has no OpenTelemetry export)                                                                       | -     |

The collector also gathers every component's container logs. Older versions ignore the settings and
their dashboards stay empty. The control plane metrics need Dashboard 5.16, MDCB 2.14 and Portal 1.20,
which were pre-releases in October 2026; tyk-install pins Gateway 5.15.1, so the Gateway dashboards
work today.

## Dashboards

Grafana opens on the API Portfolio. The dashboards are in the **Tyk** folder and link to each other,
keeping the filters and time range.

| Dashboard                  | UID                        | For                    | Shows                                                                                                              |
| -------------------------- | -------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------ |
| API Portfolio Overview     | `tyk-api-portfolio`        | API platform, SRE      | Request rate, errors and p95 per API, leaderboards, tenants and consumers, availability SLO and error budget       |
| API Troubleshooting        | `tyk-api-troubleshooting`  | On-call engineers      | One API: gateway vs upstream latency, response flags, traces in Tempo, access and error logs by trace id           |
| API SLOs                   | `tyk-api-slos`             | API owners             | Error budget, availability, upstream p90/p95/p99, status codes, endpoints and methods per API                      |
| Gateway Fleet Health       | `tyk-gateway-fleet-health` | Platform operations    | Gateways, loaded APIs and policies, config drift, Go runtime, traffic per gateway, error logs                      |
| Native OTLP Metrics        | `tyk-gateway-otlp-metrics` | Engineers, architects  | Every API metric definition: metadata, session, header, response header and context dimensions                    |
| MCP Metrics                | `tyk-mcp-metrics`          | AI / MCP API owners    | MCP requests by method and primitive, primitive latency, trace-derived latency per span                            |
| Environments Overview      | `tyk-environments`         | Platform owners        | Every environment and control plane: dependency checks, gateways, version drift, licence and certificate expiry    |
| Tyk Dashboard              | `tyk-dashboard`            | Control plane owners   | Management API, connected gateways and heartbeats, change propagation, licence, pools, object inventory, governance |
| Tyk MDCB                   | `tyk-mdcb`                 | SREs running MDCB      | Data planes by group, connections, RPC, config and key sync, analytics ingestion, licence and certificates         |
| Tyk Developer Portal       | `tyk-portal`               | Portal owners          | Provider sync with the Dashboard, failures by cause, database and storage health                                   |

The Environments Overview uses Grafana's v2 dashboard format and needs Grafana 13.

## Alert Rules

Prometheus rules in [`rules/`](./rules/), with unit tests. Every alert has a `severity` label
(`critical`, `warning` or `info`), a `tyk_component` label and a `dashboard` annotation that names the
dashboard to start from.

| Alert                        | Severity | Fires when                                                                    |
| ---------------------------- | -------- | ----------------------------------------------------------------------------- |
| `TykGatewayHighErrorRate`    | warning  | More than 10% of an API's requests return 5xx for 5m (APIs above ~0.1 req/s) |
| `TykGatewayHighLatency`      | warning  | An API's p95 latency is above 1s for 5m (APIs above ~0.1 req/s)              |
| `TykGatewayAuthFailureSurge` | warning  | Missing or invalid credentials (`AMF`, `AKI`) above 0.1 req/s for 2m          |
| `TykGatewayQuotaExhausted`   | info     | Requests rejected for quota (`QEX`) for 1m                                    |
| `TykGatewayRateLimited`      | info     | Requests rejected by the rate limiter (`RLT`) for 1m                          |
| `TykGatewayUpstreamErrors`   | critical | More than 10% of an API's requests get a 5xx from the upstream (`URS`) for 3m |
| `TykGatewayGoroutineGrowth`  | warning  | A gateway runs more than 5000 goroutines for 10m                              |
| `TykGatewayApisLoadedDrop`   | critical | A gateway has 10% fewer APIs loaded than its peak in the last 15 minutes      |

[`tyk-control-plane.rules.yml`](./rules/tyk-control-plane.rules.yml) has 39 more:

| Group             | Rules | Covers                                                                                                                                     |
| ----------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| tyk-control-plane | 3     | A component that stopped reporting, restarted, or is near its memory limit                                                                 |
| tyk-dashboard     | 13    | Dependencies, Management API errors and latency, gateway heartbeats and drops, licence seats and expiry, certificates, notifications, pools |
| tyk-mdcb          | 18    | Dependencies, disconnected or shrinking data planes, reconnect storms, heartbeats, config drift, RPC errors and latency, sync, analytics    |
| tyk-portal        | 5     | Dependencies, provider sync stale, unreachable, failing or slow                                                                            |

Thresholds are defaults; tune them per estate. Run the tests with:

```bash
docker run --rm -v "$PWD/observability/rules:/rules" -w /rules/tests \
  --entrypoint promtool quay.io/prometheus/prometheus:v3.15.0 \
  test rules tyk-control-plane.rules.test.yml tyk-gateway.rules.test.yml
```

The gateway rules match `service_name="tyk-gateway"`, the Gateway's default resource name. If you
set `TYK_GW_OPENTELEMETRY_RESOURCENAME`, change them too.

## Files

| Path                           | Purpose                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------- |
| `env/gateway.env`              | Gateway traces, metrics (with the 22 API metric definitions) and JSON / access logs           |
| `env/dashboard.env`            | Dashboard metrics, `control_plane_id` and the metric families                                 |
| `env/portal.env`               | Developer Portal metrics                                                                      |
| `env/mdcb.env`                 | MDCB metrics, for your own MDCB (tyk-install has no MDCB deployment)                          |
| `collector/config.yaml`        | Collector pipelines: OTLP in, Prometheus exporter, Tempo, Loki, span metrics                  |
| `collector/logs-docker.yaml`   | Container logs on Docker                                                                      |
| `collector/logs-kubernetes.yaml` | Container logs on Kubernetes                                                                |
| `collector/exporters/`         | Optional extra backends (see below)                                                           |
| `dashboards/`                  | Grafana dashboards                                                                            |
| `rules/`                       | Prometheus alert rules and their tests                                                        |
| `scripts/smoke-test.sh`        | Checks a running stack receives metrics, traces and logs                                      |
| `scripts/check-panels.py`      | Runs every dashboard query against a running stack; fails on query errors (run in CI)         |
| `scripts/check-dashboards.sh`  | Static checks on the dashboards (run in CI)                                                   |

The env files serve both platforms. On Docker, the overlay loads them after the component's own
`confs/*.env`, so their values win. On Kubernetes, they become `tyk-otel-*` ConfigMaps; anything the
chart sets itself wins over them. Their comments sit on their own lines because
`kubectl create configmap --from-env-file` keeps anything after `=` as the value.

### Gateway API Metrics

`TYK_GW_OPENTELEMETRY_METRICS_APIMETRICS` in `env/gateway.env` defines 22 instruments, enough for
every Gateway dashboard panel. Each picks its labels from request metadata, the auth session, a
request or response header, or a context variable set by middleware. Some grow with your traffic:

- `Mcp-Session-Id` on `http.server.request.duration`: one histogram per MCP session
- `tyk.requests.by.apikey`, `tyk.requests.by.oauth`, `tyk.requests.by.portal`: per key, OAuth client
  or portal app
- `tyk.requests.by.tenant`, `tyk.latency.by.tenant`, `tyk.requests.by.customer`: per `X-Tenant-ID` /
  `X-Customer-ID` value

Remove the instruments or dimensions you do not need, or unset the variable to get the Gateway's four
built-in instruments (the identity, tenant and cache rows then stay empty). The Gateway caps each
instrument at `TYK_GW_OPENTELEMETRY_METRICS_CARDINALITYLIMIT` (2000 by default) label combinations.

## Sending to Another Backend

The local stack keeps receiving everything. To also send to another backend, select a file from
[`collector/exporters/`](./collector/exporters/) and set its variables (Docker:
`OTEL_COLLECTOR_EXPORTER` in `.env`; Kubernetes: the collector's `extraArgs` and `extraEnvs`):

| Backend                                                                      | File                      | Variables                                                         | Tyk dashboards and alerts      |
| ---------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------- | ------------------------------ |
| Prometheus remote write: Mimir, Grafana Cloud Metrics, Thanos, VictoriaMetrics, Cortex, Azure Managed Prometheus | `prometheus-remote-write` | `PROMETHEUS_REMOTE_WRITE_ENDPOINT`, `PROMETHEUS_REMOTE_WRITE_HEADERS` | Work unchanged                 |
| AWS: Managed Prometheus, X-Ray, CloudWatch Logs                              | `aws`                     | `AWS_REGION`, `AMP_REMOTE_WRITE_URL`, `CLOUDWATCH_LOG_GROUP`      | Work in Amazon Managed Grafana |
| Google Cloud: Managed Prometheus, Cloud Trace, Cloud Logging                 | `google-cloud`            | `GOOGLE_CLOUD_PROJECT`                                            | Work against Managed Prometheus |
| Any OTLP backend: Grafana Cloud, New Relic, Honeycomb, Elastic, Dynatrace, SigNoz, ... | `otlp`          | `OTLP_EXPORT_ENDPOINT`, `OTLP_EXPORT_HEADERS`                     | Need adapting                  |
| Datadog                                                                      | `datadog`                 | `DD_API_KEY`, `DD_SITE`                                           | Not applicable                 |
| Azure Monitor / Application Insights                                         | `azure-monitor`           | `APPLICATIONINSIGHTS_CONNECTION_STRING`                           | Not applicable                 |

Headers are a JSON map, for example `{"Authorization":"Basic <token>"}`.

If the backend rejects the data (wrong credentials, endpoint down), the collector logs the export
errors and the local stack keeps receiving everything:

```bash
docker logs tyk-otel-collector 2>&1 | grep export
```

If an exporter cannot start at all, for example `google-cloud` or `aws` without credentials, the
whole collector fails to start, and the local stack receives nothing until it is fixed.

`prometheus-remote-write` and `otlp` are tested end to end against local stand-ins (authenticated
delivery of metrics, traces and logs, and the Tyk dashboards and alert rules on the remote-write
copy). The vendor-specific files are checked to load, but not against a real account. OTLP backends store resource
attributes their own way, so the PromQL dashboards may need their label names adjusted; send metrics
with `prometheus-remote-write` to keep them as they are. Each file adds its own `*/export` pipelines,
so use one at a time, or merge two into a single file. Dynatrace only accepts delta metrics: add
`cumulativetodelta` to the `metrics/export` pipeline in `otlp.yaml`.

## Production Checklist

The defaults suit development. Before production:

- **Grafana access**: anyone who can reach Grafana is an Admin. Turn anonymous access off or make it
  Viewer, set an admin password, or use your SSO.
- **Trace sampling**: every request is traced. Use `TraceIDRatioBased` with a rate of 0.01-0.1
  (`env/gateway.env`).
- **Metric volume**: trim the Gateway's API metric definitions (see above); raise the export interval
  to 60s and the scrape interval to 30-60s.
- **Storage and retention**: Prometheus keeps 7 days, Tempo and Loki 3 days, on local disk. Use
  persistent volumes or object storage, or remote-write metrics to long-term storage.
- **Transport**: the collector's OTLP ports have no TLS or auth. Keep them on a private network, or
  set the components' `*_TLS_*` settings and a TLS receiver.
- **Collector**: it runs as root to read container log files. To run it as non-root, drop the logs
  file and ship logs with your platform's agent. Give it a memory limit; on large clusters run a
  Deployment for OTLP and keep the DaemonSet for logs.
- **Alerts**: route Alertmanager to your on-call tool and tune the thresholds.
- **Access logs**: one line per request; drop `TYK_GW_ACCESSLOGS_ENABLED` if log volume matters more
  than trace-to-log correlation.
- **Labels**: set `TYK_DB_CONTROLPLANEID` and the `*_DEPLOYMENTENVIRONMENT` settings per environment;
  the Environments Overview groups by them.
- **Memory limits**: set `GOMEMLIMIT` on the components to fill the memory limit panels and the
  `TykControlPlaneMemoryNearLimit` alert.

## Verify

Send some traffic through the Gateway, then:

```bash
observability/scripts/smoke-test.sh
```

It checks for Gateway metrics, loaded alert rules, the dashboards and datasources in Grafana, traces
in Tempo and logs in Loki. Set `PROMETHEUS_URL` and `GRAFANA_URL` when they are not on
`localhost:9090` and `localhost:3002`.

To run every dashboard query through Grafana (Python 3, no dependencies):

```bash
observability/scripts/check-panels.py --show-empty
```

It fails on any query error and lists the panels that returned nothing; those need traffic of that
kind (rate limits, cache, MCP, failures) or a component that is not running.

## Known Limitations

- The Dashboard shows each gateway's version and loaded APIs only for Gateway 5.16+; older gateways
  show as `unknown`.
- `tyk_gw_group_id` (gateway groups in Fleet Health and the MDCB dashboard) exists only on gateways
  connected to MDCB.
- On PostgreSQL, the Dashboard reports its pool size limit only when
  `TYK_DB_STORAGE_MAIN_POSTGRES_MAXOPENCONNECTIONS` is set, so the datastore pool saturation panel and
  alert stay empty otherwise.
- Rate limit, quota, cache and MCP panels stay empty until there is traffic of that kind.
- A restarted component gets a new instance id; the collector drops the old one's series after
  `metric_expiration` (2 minutes), and the trace-derived span metrics after up to about 4 minutes.
- Prometheus misses the first increment of a counter that starts mid-run.
- The Developer Portal exports provider sync and dependency health only.
- Loki stops accepting logs when its disk is more than 90% full.

## Origin

The dashboards and control plane rules started from tyk-demo's `opentelemetry-demo` deployment
([TykTechnologies/tyk-demo#418](https://github.com/TykTechnologies/tyk-demo/pull/418)). tyk-install
now maintains them. Changes from that version:

- The SLO dashboard reads the Gateway's OpenTelemetry metrics instead of Tyk Pump's Prometheus export.
- API Portfolio: "Top 10 APIs by P95 Latency" no longer multiplies the latency by the request count,
  and "Top 10 APIs by Request Rate" filters on the right method label.
- API Troubleshooting: the gateway logs link points at the Loki datasource; Fleet Health and API
  Troubleshooting take the service name from a variable, and their log panels match Tyk's `warning`
  level (they only matched `warn`, so warnings were missing).
- The Gateway alerts are Prometheus rules with unit tests. The error rate is per API (it compared a
  series with itself before), the latency alert reads the Gateway only, and the error, latency and
  upstream alerts ignore near-idle APIs. The upstream alert fires on a share of traffic rather than
  on a single error, and the lost-APIs alert keeps firing while the APIs are missing.
- Datasource UIDs, links and folder names no longer depend on the demo environment.
