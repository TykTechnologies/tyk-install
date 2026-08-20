# Hardening

What `profiles.py` cannot tell you. The marker comments cover per-setting guidance; this covers the
concerns that are not expressible as a single setting.

Run the tool first — `profiles.py audit <files> --profile prod --profile security` — then work
through this list.

## Always flag, regardless of markers

These are committed development defaults. They are correct for a laptop and wrong for anything
else, and no marker will catch them because the value in the file *is* the intended dev value.

**On a Helm path, audit the sibling `.env.example` as well as `values.yaml`.** The credentials a
Helm deployment actually boots with live in `.env.example`, not in `values.yaml` — the values file
only references them via `useSecretName` / `connectionStringSecret`. Auditing only the file the user
named will miss every secret:

```bash
python3 scripts/profiles.py audit kubernetes/<target>/values.yaml kubernetes/<target>/.env.example \
  --profile prod --profile security
```

Pass both paths. `audit` masks credential values, so this is the safe way to enumerate them — do
**not** read the file by hand and quote lines from it, which would put plaintext passwords into
your transcript and breaks the rule in `AGENTS.md` §Secrets.

`profiles.py list` prints a count for every profile including zero. A `security=0` means the file
carries no `# SECURITY:` annotations — **not** that it has no security problems. Check the table
below regardless of what the counts say.

| What | Where | Why it matters |
| --- | --- | --- |
| `TYK_GW_SECRET` and `TYK_GW_NODESECRET` share one hardcoded value | `docker/*/confs/tyk.env` | This is the Gateway API credential. Anyone with it controls the Gateway. Generate separate 32+ character values: `openssl rand -hex 32`. |
| Postgres `tykuser` / `tykSecurePass123` | `docker/*/docker-compose.yml` | Committed in plain text in a public repository. |
| Redis with no password | all Compose stacks | Redis holds keys, quotas, and rate-limit counters. |
| `TYK_GW_ALLOWINSECURECONFIGS=true`, or `allowInsecureConfigs: true` on Helm | `docker/*/confs/tyk.env`, `kubernetes/*/values.yaml` | Permits insecure API configurations. Carries no marker in either place, so `audit` will not report it — check it by hand every time. |
| `TYK_DB_ADMINSECRET` | `confs/tyk_analytics.env` | Full Dashboard admin access. |

Name the variable and cite its `file:line`. Never print the value, even to show it is weak.

## Data stores

Single-instance Redis or PostgreSQL is a data-loss risk, not a tuning gap — treat it as more
serious than any `# PROD:` marker.

- **Redis** holds keys, quotas, rate-limit counters, and OAuth tokens. Losing it logs every
  consumer out. Use Redis Cluster or a managed equivalent, enable `enableCluster`, and turn on TLS.
- **Separate analytics Redis.** Analytics traffic competes with the hot path for the same
  connection pool. `TYK_GW_ENABLESEPERATEANALYTICSSTORE=true` with its own cluster is the single
  highest-value change for a busy gateway.
- **PostgreSQL** holds API definitions, policies, and users. Needs backups with a tested restore,
  not just replication. Replication protects against host loss, not against a bad migration.
- Do not co-locate Redis with the Gateway to save a hop. A Gateway restart should not take the
  session store with it.

## Network

- **Isolate the control API.** By default the Gateway's management API shares the traffic port,
  so anything that reaches your APIs can reach `/tyk/`. Set `TYK_GW_CONTROLAPIPORT` and
  `TYK_GW_CONTROLAPIHOSTNAME`, and do not expose that port publicly. See
  https://tyk.io/docs/planning-for-production#change-your-control-port
- **TLS on the edge**, and to Redis and PostgreSQL if they cross a network boundary.
- **Never disable certificate validation in production.** Every `SSLINSECURESKIPVERIFY` must stay
  `false`; the markers say so, and it is worth restating because the dev configs rely on it.
- **Dashboard and Portal should not be internet-facing** unless deliberately intended. The Portal
  usually is; the Dashboard usually is not.

## Availability

- At least two Gateways behind a load balancer. Gateways are stateless — state is in Redis — so
  this is straightforward.
- Set CPU and memory requests and limits. Without requests the scheduler cannot place pods
  sensibly, and without limits one Gateway can starve its neighbours.
- Pod anti-affinity so replicas do not share a node.
- A PodDisruptionBudget, so a drain cannot take every Gateway at once.
- Gateways are the only component that must scale with traffic. The Dashboard serves operators,
  not requests.

## Analytics volume

Analytics is the usual cause of "Tyk got slow" and "Redis filled up".

- `ENABLEDETAILEDRECORDING=true` stores full request and response bodies. It is invaluable for
  debugging and ruinous at volume — and it can capture sensitive payloads, so it is a data
  protection question as well as a capacity one.
- Pump must keep up with the Gateway. If it does not, records expire in Redis and analytics
  silently under-report — which looks like a traffic drop rather than a pipeline failure.
- Elasticsearch sinks support major versions 3, 5, 6, and 7 only. Version 8 fails at startup and
  restart-loops.

## Logging

- `TYK_GW_LOGLEVEL=error` in production. `info` is verbose enough to cost real money in a log
  pipeline.
- Access logs are off by default. Turning them on duplicates much of what analytics captures.

## Upgrades and backups

- Control plane before data planes; never split Gateway and Dashboard minor versions.
- Back up PostgreSQL and test a restore. An untested backup is not a backup.
- Keep API definitions in version control — Tyk Sync, or files in OSS — so the gateway is
  reproducible without a database restore. This is the difference between an outage and a disaster.

## What not to do

Do not invent thresholds. If the repository's markers give no number and nothing here does either,
say the number needs sizing work and point at
https://tyk.io/docs/planning-for-production rather than guessing a value the user might deploy.

Do not report a configuration as "production ready". Report which guidance it satisfies and which
it does not; the judgement belongs to whoever owns the service.

## Reference

- https://tyk.io/docs/planning-for-production
- https://tyk.io/docs/api-management/dashboard-configuration
- https://tyk.io/docs/tyk-pump
