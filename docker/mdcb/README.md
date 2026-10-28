# Tyk MDCB — Docker

A self-managed control plane plus one or more remote data planes, bridged by MDCB
(Multi-Data-Centre Bridge).

Both sub-stacks here can run on one host for a demo, with deliberately non-colliding ports. In
reality they live in different clusters, regions, or data centres.

## When you need this

MDCB is the right answer when:

- APIs are served from more than one region or data centre, and
- data planes must keep serving traffic through a control-plane outage, or
- regulation requires traffic and analytics to stay in a jurisdiction.

MDCB is **not** the answer to plain high availability. Several gateways against a single
Self-Managed control plane already gives you that, with far fewer moving parts. If someone wants
"HA Tyk", send them to [`../self-managed/`](../self-managed/) instead.

## Architecture

```text
   CONTROL PLANE                          DATA PLANE (xN)
   Dashboard  ──┐                         Gateway (RPC mode)
   MDCB :9091 ──┼── Redis                 Pump
   Gateway      │   PostgreSQL            its own local Redis
   Pump       ──┘                              │
        ▲                                      │
        └──────────── RPC :9091 ───────────────┘
```

The data plane's Redis is its own and must not be shared with the control plane — keeping local
state is exactly what lets it survive a control-plane outage.

## Licences

Two are required, and they are separate:

| Variable | For |
| --- | --- |
| `TYK_LICENSE_KEY` | the control-plane Dashboard |
| `TYK_MDCB_LICENSE` | MDCB itself |

Data planes need no licence of their own; entitlement arrives over RPC. Trials:
<https://tyk.io/self-managed-trial/>

## 1. Start the control plane

Order matters. A data plane cannot complete its handshake until MDCB is serving.

```bash
cd control-plane
cp .env.example .env       # add TYK_LICENSE_KEY and TYK_MDCB_LICENSE
docker compose up -d
docker compose ps
```

Verify before going further:

```bash
curl -s localhost:3000/hello        # dashboard
curl -s localhost:8080/hello | jq   # control-plane gateway
docker logs tyk-mdcb-cp | tail -20  # must NOT be looping on a licence error
../../../skills/tyk-deployment-runner/scripts/verify_deployment.sh --edition mdcb-control-plane
```

If MDCB logs `This license has expired, please renew.` in a loop, `TYK_MDCB_LICENSE` is missing,
wrong, or expired. That message looks identical whether the value is absent or invalid.

## 2. Collect the three identifiers

The data plane needs three values from the control-plane Dashboard at `http://localhost:3000`:

| Value | Where | Goes into |
| --- | --- | --- |
| Organisation ID | Dashboard → your organisation | `TYK_GW_SLAVEOPTIONS_RPCKEY` |
| Dashboard user API key | Dashboard → Users → your user | `TYK_GW_SLAVEOPTIONS_APIKEY` |
| Group ID | you choose it — a name for this data-plane cluster | `TYK_GW_SLAVEOPTIONS_GROUPID` |

All three must be right. One wrong value fails the handshake with `access denied`, which is
indistinguishable in the logs from a licence problem.

**The organisation must be hybrid-enabled.** MDCB refuses the RPC login for an
organisation that is not, and the data plane reports it as `RPC Login incorrect` — the same
message as wrong credentials. Create the organisation with `hybrid_enabled`:

```bash
curl -s -X POST http://localhost:3000/admin/organisations \
  -H "admin-auth: $ADMIN_SECRET" -H 'Content-Type: application/json' \
  -d '{"owner_name":"Example","cname_enabled":true,"hybrid_enabled":true}'
```

Bootstrap the control plane first if it has no organisation yet — see
[`../../utils/bootstrap/`](../../utils/bootstrap/).

## 3. Start a data plane

```bash
cd ../data-plane
cp .env.example .env
# edit confs/tyk.env: set RPCKEY, APIKEY, GROUPID, and CONNECTIONSTRING
docker compose up -d
```

`CONNECTIONSTRING` defaults to `host.docker.internal:9091`, which reaches a control plane on the
same machine. For a real remote control plane, set its hostname and remove the `extra_hosts`
entry from `docker-compose.yml`.

The data-plane gateway is on **8081** and its Redis on **6380**, so it does not collide with a
control plane on the same host.

## 4. Verify the bridge

Verified on Docker Desktop / OrbStack in August 2026 with MDCB v2.12.0 and Tyk 5.14.0 (the pins
have since moved to the current release): control plane healthy,
data plane logged in over RPC, an API created on the control plane propagated to the data plane,
and a request served through the data-plane gateway.

```bash
docker logs tyk-gateway-dp | grep -i rpc
../../../skills/tyk-deployment-runner/scripts/verify_deployment.sh \
  --edition mdcb-data-plane --gateway http://localhost:8081
```

Then prove it end to end: create an API on the control-plane Dashboard, tag it for this data
plane's group, and call it through port 8081. An RPC connection with no APIs flowing is a group or
tagging problem, not a connectivity one.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `rpc: connection refused` | Control plane not serving, or wrong host/port. MDCB is on 9091. Start the control plane first. |
| `RPC Login incorrect` on the data plane | Three different causes, and the gateway-side message is identical for all of them. Check MDCB's own log to tell them apart: (a) one of the three identifiers is wrong; (b) the organisation is not `hybrid_enabled`; (c) MDCB cannot read `tyk_organisations`, which means its connection string points at the wrong database — see the row below. |
| MDCB logs `relation "tyk_organisations" does not exist` | `TYK_MDCB_ANALYTICSCONFIG_CONNECTIONSTRING` points at the analytics database (`tyk_analytics`) instead of the Dashboard's **main** database (`tyk_dashboard`). Organisations live in the main one. Must match `TYK_DB_STORAGE_MAIN_CONNECTIONSTRING` in the control plane's `confs/tyk_analytics.env`. |
| MDCB logs `no driver specified for mongo` | `TYK_MDCB_ANALYTICSCONFIG_TYPE` is unset, so it defaulted to `mongo` and ignored every PostgreSQL setting. |
| `certificate signed by unknown authority` | TLS to MDCB. For development set `TYK_GW_SLAVEOPTIONS_SSLINSECURESKIPVERIFY=true`; in production install the CA instead. |
| Connects, but no APIs appear | Group ID mismatch, or APIs not tagged for this data plane. |
| Keys work on one plane, not the other | `TYK_MDCB_HASHKEYS` and the gateways' `TYK_GW_HASHKEYS` disagree. They must match. |
| Port 5432 already allocated | A local PostgreSQL. Change `POSTGRES_PORT` in `.env`. |

More in
[`../../skills/tyk-deployment-runner/references/debugging.md`](../../skills/tyk-deployment-runner/references/debugging.md).

## Before production

```bash
python3 ../../skills/tyk-production-readiness/scripts/profiles.py \
  audit control-plane/confs/*.env data-plane/confs/*.env --profile prod --profile security
```

Specific to MDCB, beyond the usual:

- **Enable the synchroniser.** `TYK_MDCB_SYNCWORKER_ENABLED=true` on the control plane and
  `TYK_GW_SLAVEOPTIONS_SYNCHRONISERENABLED=true` on each data plane. Without it, data planes do
  not keep a keyspace copy — and surviving a control-plane outage is the reason you chose MDCB.
- **TLS on the RPC link.** It crosses a network boundary between sites. Set `TYK_MDCB_USESSL=true`,
  and set `SSLINSECURESKIPVERIFY=false` on the data planes.
- **Run at least two MDCB instances.** Every data plane depends on MDCB to pick up configuration
  changes.
- The committed Postgres password and Gateway secrets are development defaults.

## Teardown

```bash
cd data-plane   && docker compose down -v
cd ../control-plane && docker compose down -v
```

## Reference

- <https://tyk.io/docs/tyk-multi-data-centre>
- <https://tyk.io/docs/tyk-mdcb-api.mdx>
- Kubernetes equivalent: [`../../kubernetes/helm-mdcb/`](../../kubernetes/helm-mdcb/)
- Tyk Cloud control plane instead of self-hosted: [`../hybrid/`](../hybrid/)
