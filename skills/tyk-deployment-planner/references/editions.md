# Editions

What each edition includes, what it needs, and when it is the right answer.

## OSS (open source)

The Gateway alone, Apache 2.0 licensed, no licence key.

| | |
| --- | --- |
| Image | `tykio/tyk-gateway` — **not** `tyk-gateway-ee`, which is the licensed build |
| Needs | Redis |
| Config source | files on disk (`TYK_GW_USEDBAPPCONFIGS=false`) |
| Directories | `docker/oss/`, `kubernetes/helm-oss/` (chart `tyk-oss`) |

Gets you: routing, all authentication methods, rate limits, quotas, transforms, caching, circuit
breakers, JavaScript and gRPC plugins, Tyk Streams.

Does not get you: Dashboard UI, Developer Portal, RBAC and multi-tenancy, MDCB, analytics
storage beyond Redis, single sign-on.

OSS is a real production gateway, not a trial. The trade is that APIs are managed as files under
version control rather than through a UI — which many teams prefer. Choose it when nobody needs
the Dashboard.

## Self-Managed

Gateway, Dashboard, Pump, and optionally Developer Portal, all self-hosted.

| | |
| --- | --- |
| Images | `tykio/tyk-gateway-ee`, `tykio/tyk-dashboard`, `tykio/tyk-pump-docker-pub`, `tykio/portal` |
| Needs | Redis, PostgreSQL |
| Licences | Dashboard; Portal separately if the Portal is deployed |
| Config source | Dashboard (`TYK_GW_USEDBAPPCONFIGS=true`) |
| Directories | `docker/getting-started/`, `docker/self-managed/`, `kubernetes/helm-self-managed/` (chart `tyk-stack`) |

`docker/getting-started/` is the evaluation path: it bootstraps an organisation, a Dashboard user,
and sample APIs. Send someone there to try Tyk. `docker/self-managed/` is the full stack including
Portal.

## Hybrid (Tyk Cloud control plane)

Tyk runs the control plane; the customer runs gateways in their own network, so traffic and
credentials never leave their infrastructure.

| | |
| --- | --- |
| Runs locally | Gateway, Pump, Redis |
| Needs | a Tyk Cloud account, plus org ID, API key, and group ID from it |
| Config source | Tyk Cloud MDCB over RPC (`TYK_GW_SLAVEOPTIONS_USERPC=true`) |
| Directories | `docker/hybrid/`, `kubernetes/helm-hybrid/` (chart `tyk-data-plane`) |

Provisioning the Cloud control plane happens in the Tyk Cloud UI, not from this repository.

## MDCB (self-managed multi-data-centre)

The same split as hybrid, but the customer runs the control plane too.

| | |
| --- | --- |
| Control plane | Dashboard, MDCB, Redis, PostgreSQL, optionally a Gateway |
| Data plane | Gateway in RPC mode, Pump, its own local Redis |
| Licences | Dashboard **and** MDCB |
| RPC port | 9091 |
| Directories | `docker/mdcb/`, `kubernetes/helm-mdcb/` (charts `tyk-control-plane`, `tyk-data-plane`) |

Choose MDCB when there is more than one region or data centre, when data planes must keep serving
traffic through a control-plane outage, or when regulation requires traffic to stay in a
jurisdiction. It is materially more moving parts than Self-Managed — do not reach for it to solve
plain high availability, which multiple gateways against one control plane already handles.

## AI Studio

AI Studio, Microgateway, and analytics pulse, for governing LLM and AI API traffic.

| | |
| --- | --- |
| Needs | PostgreSQL. Redis is optional; each edge keeps its own SQLite |
| Licence | none for the Community Edition (AGPL-3.0, on GitHub); AI Studio licence for the Enterprise Edition |
| Directory | `docker/ai-studio/`, `kubernetes/helm-ai-studio/` |

Deployed independently of the API-management editions above.

## Choosing by licence

| Licences held | Edition |
| --- | --- |
| none | OSS |
| Tyk Cloud account | hybrid data plane |
| Dashboard | Self-Managed |
| Dashboard + Portal | Self-Managed with Portal |
| Dashboard + MDCB | MDCB |
| AI Studio | AI Studio |

Free trial licences: <https://tyk.io/self-managed-trial/>

## Reference

- <https://tyk.io/docs/tyk-open-source.mdx>
- <https://tyk.io/docs/tyk-self-managed>
- <https://tyk.io/docs/tyk-multi-data-centre>
- <https://tyk.io/docs/tyk-cloud>
