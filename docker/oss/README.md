# Tyk OSS (Open Source) — Docker

The open source Tyk Gateway with Redis. No licence, no Dashboard, no PostgreSQL.

This is a real production gateway, not a trial. The trade is that APIs are managed as files under
version control rather than through a UI — which many teams prefer.

## OSS vs Self-Managed

| | OSS | Self-Managed |
| --- | --- | --- |
| Gateway image | `tykio/tyk-gateway` | `tykio/tyk-gateway-ee` |
| Licence | none | Dashboard (+ Portal) |
| API definitions | files in `apps/` | Dashboard, stored in PostgreSQL |
| Policies | `policies/policies.json` | Dashboard |
| `TYK_GW_USEDBAPPCONFIGS` | `false` | `true` |
| Dependencies | Redis | Redis + PostgreSQL |
| Analytics | Redis, drained by Pump to a sink you choose | Dashboard UI |

You get: routing, every authentication method, rate limits, quotas, transforms, caching, circuit
breakers, JavaScript and gRPC plugins, Tyk Streams.

You do not get: Dashboard UI, Developer Portal, RBAC and multi-tenancy, MDCB, single sign-on.

Using `tyk-gateway-ee` here by mistake is a common error — that is the licensed Enterprise build.

## Prerequisites

- Docker with Docker Compose
- `curl` to verify

```bash
python3 ../../skills/tyk-deployment-planner/scripts/preflight.py --platform docker --target .
```

## Quick start

```bash
cp .env.example .env      # no licence needed; .env is gitignored
docker compose up -d
```

Redis becomes healthy first, then the Gateway starts. A local `go-httpbin` upstream is included so
the bundled example API works without egress.

## Verify

```bash
curl -s localhost:8080/hello | jq          # gateway health
curl -s localhost:8080/httpbin/get         # a request proxied to the upstream
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/nope/   # 404 - routing, not blanket forwarding
```

Or collect the whole evidence set at once:

```bash
../../skills/tyk-deployment-runner/scripts/verify_deployment.sh --edition oss --route /httpbin/get
```

A healthy gateway that proxies nothing is the failure worth catching, so check the proxied request
rather than `/hello` alone.

## Adding an API

Drop a Tyk API definition into `apps/` and restart the Gateway. The mount is read-only, so the
Gateway will never rewrite your files.

```bash
cp my-api.json apps/
docker compose restart tyk-gateway
docker compose logs tyk-gateway | grep 'API Loaded'
```

`apps/httpbin.json` is a working keyless example to copy. The fields that matter:

| Field | Meaning |
| --- | --- |
| `api_id` | unique, referenced by keys and policies |
| `proxy.listen_path` | the path Tyk serves, e.g. `/httpbin/` |
| `proxy.target_url` | the upstream. In Compose, the service name — not `localhost` |
| `proxy.strip_listen_path` | remove the listen path before forwarding |
| `use_keyless` | `true` for no authentication. Without it, requests get 401 |
| `active` | `false` means the definition loads but serves nothing |

Because these are files, keep them in git — that makes the gateway reproducible without a database
restore.

## Configuration

`confs/tyk.env` carries every Gateway setting, annotated with `# PROD:`,
`# PROD/PERFORMANCE:`, and `# SECURITY:` markers. To see what production would change:

```bash
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  audit confs/tyk.env --profile prod --profile security
```

Host ports come from `.env` (`GATEWAY_PORT`, `REDIS_PORT`) — change them there if something already
listens on 8080 or 6379.

## Analytics

Off by default: with no Dashboard, records accumulate in Redis and expire unless something drains
them. To enable, set `TYK_GW_ENABLEANALYTICS=true` in `confs/tyk.env`, point `confs/pump.env` at a
sink you actually read, then:

```bash
docker compose --profile analytics up -d
```

The bundled sink is stdout, so a first run shows something without external infrastructure.
Prometheus and Elasticsearch are commented out and ready. Note Pump supports Elasticsearch major
versions 3, 5, 6, and 7 only — version 8 restart-loops.

## Before production

```bash
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  audit confs/tyk.env --profile prod --profile performance --profile security
```

Regardless of what the markers say, these ship as development defaults and must change:

- `TYK_GW_SECRET` — this is the Gateway API credential. `openssl rand -hex 32`.
- Redis has no password and is a single instance. It holds keys, quotas, and rate-limit counters;
  losing it logs every consumer out.
- `TYK_GW_ALLOWINSECURECONFIGS=true`.
- The Gateway management API shares the traffic port. Set `TYK_GW_CONTROLAPIPORT`.

## Teardown

```bash
docker compose down       # stop, keep data
docker compose down -v    # stop and destroy volumes
```

## Reference

- https://tyk.io/docs/tyk-oss-gateway
- https://tyk.io/docs/tyk-open-source.mdx
- https://tyk.io/docs/planning-for-production
- Kubernetes equivalent: [`../../kubernetes/helm-oss/`](../../kubernetes/helm-oss/)
