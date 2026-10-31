# Tyk OSS (Open Source) — Docker

The open source Tyk Gateway with Redis. No licence, no Dashboard, no PostgreSQL.

This is a real production gateway, not a trial. The trade is that APIs are managed as files under
version control rather than through a UI — which many teams prefer.

## OSS vs Self-Managed

| | OSS | Self-Managed |
| --- | --- | --- |
| Gateway image | `tykio/tyk-gateway` | `tykio/tyk-gateway-ee` |
| Licence | none | Dashboard (+ Portal) |
| API definitions | Tyk OAS files in `apps/` | Dashboard, stored in PostgreSQL |
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
the bundled example APIs work without egress.

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

## Five-minute proof of concept: one keyed API, 10 requests per minute

The stack ships two Tyk OAS example APIs. `httpbin` is keyless and `httpbin-keyed` needs an API
key. Each is a pair of files in `apps/`: the OpenAPI document (`httpbin-keyed-oas.json`) and the
wrapper the Gateway generated from it (`httpbin-keyed.json`), see [Adding an API](#adding-an-api).
The policy `httpbin-10rpm` in `policies/policies.json` caps a key at 10 requests per minute. With
the stack up, run the whole proof in one go:

```bash
scripts/keyed-poc.sh
```

Or step by step:

```bash
SECRET=$(grep ^TYK_GW_SECRET= confs/tyk.env | cut -d= -f2 | cut -d' ' -f1)

# the keyed API refuses a request without a key
curl -s localhost:8080/httpbin-keyed/get                      # 401 {"error": "Authorization field missing"}

# a key that references the policy; key, policy and API share org_id "default"
KEY=$(curl -s -X POST localhost:8080/tyk/keys -H "x-tyk-authorization: $SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"org_id":"default","apply_policies":["httpbin-10rpm"]}' | jq -r .key)

# ten 200s, then the limit
for i in $(seq 1 12); do
  curl -s -o /dev/null -w '%{http_code} ' -H "Authorization: $KEY" localhost:8080/httpbin-keyed/get
done; echo                                                   # 200 x10 then 429 x2
curl -s -H "Authorization: $KEY" localhost:8080/httpbin-keyed/get   # {"error": "Rate Limit Exceeded"}
```

What the pieces are:

- The limit lives on the key, not in the API definition. `rate` requests per `per` seconds,
  `quota_max` requests per `quota_renewal_rate` seconds (`-1` means no quota). They can be set
  inline when the key is created (`{"rate":10,"per":60,"quota_max":-1,"access_rights":{...}}`)
  or, as here, on a policy the key references with `apply_policies`.
- The key, the policy and the API must share the same `org_id` (`default` in this stack). A
  file policy without `org_id`, or a key request without one, fails with "Failed to create key"
  and the Gateway logs `policy not found`.
- Counters live in Redis, so the limit holds across every Gateway replica and the key survives a
  Gateway restart. A rate-limited call returns HTTP 429 `{"error": "Rate Limit Exceeded"}`; an
  exhausted quota returns HTTP 403 `{"error": "Quota exceeded"}`.
- A cap on one endpoint for every caller belongs in the Tyk OAS document instead, under
  `x-tyk-api-gateway.middleware.operations.<operationId>.rateLimit`, with `per` as a duration
  string: `{"enabled": true, "rate": 5, "per": "1m"}`. That limit answers HTTP 429
  `{"error": "API Rate Limit Exceeded"}`.

Everything above runs on the open source Gateway; no licence is involved.

## Adding an API

The Gateway reads API definitions from `apps/` at start. The mount is read-only, so the Gateway
never rewrites your files; keep them in git, which makes the gateway reproducible without a
database restore.

A file-based Tyk OAS API is a pair of files: `<id>-oas.json`, your OpenAPI document with the
`x-tyk-api-gateway` extension, and `<id>.json`, the wrapper the Gateway generates from it
(`"is_oas": true`) and reads the routing from. A bare OpenAPI document dropped into `apps/` is
not loaded, and a hand-written stub wrapper fails with `Listen path is empty`. Let the Gateway API
produce the pair:

```bash
scripts/add-oas-api.sh my-api.oas.json     # writes apps/<id>.json and apps/<id>-oas.json
docker compose restart tyk-gateway
docker compose logs tyk-gateway | grep 'API Loaded'
```

The script starts a throwaway Gateway with `apps/` mounted writable, posts the document to
`POST /tyk/apis/oas`, waits for the pair and stops it; the running Gateway keeps its read-only
mount. Both example pairs were produced this way: copy `apps/httpbin-oas.json` for a keyless API
and `apps/httpbin-keyed-oas.json` for one behind an API key. The fields that matter in the
document:

| Field | Meaning |
| --- | --- |
| `x-tyk-api-gateway.info.id` | unique, referenced by keys and policies, and the file name of the pair |
| `x-tyk-api-gateway.info.orgId` | `default` here; keys and policies must use the same value |
| `x-tyk-api-gateway.server.listenPath.value` | the path Tyk serves, e.g. `/orders/`; `strip: true` removes it before forwarding |
| `x-tyk-api-gateway.upstream.url` | the upstream. In Compose, the service name — not `localhost` |
| `x-tyk-api-gateway.server.authentication` | `enabled: true` plus the security scheme to enforce; omit it for a keyless API |
| `x-tyk-api-gateway.info.state.active` | `false` means the definition loads but serves nothing |

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

- <https://tyk.io/docs/tyk-oss-gateway>
- <https://tyk.io/docs/tyk-open-source.mdx>
- <https://tyk.io/docs/planning-for-production>
- Kubernetes equivalent: [`../../kubernetes/helm-oss/`](../../kubernetes/helm-oss/)
