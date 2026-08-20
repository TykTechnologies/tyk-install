# Topology Matrix

Every supported deployment maps to a real directory in this repository. If a request does not map
to a row here, say so rather than improvising a path.

`status` means:

| status | meaning |
| --- | --- |
| `bundled-tested` | Artifacts exist and are verified end to end, including a request proxied through the gateway. |
| `bundled` | Artifacts exist and render/parse, but a full runtime verification needs a licence, a cluster, or hardware not available at authoring time. |
| `guidance-only` | Documentation only. No tested artifact. Never present as though one exists. |

## Docker

| Edition | Directory | Components | Licence | Status |
| --- | --- | --- | --- | --- |
| OSS | `docker/oss/` | Gateway (`tykio/tyk-gateway`), Redis | none | `bundled-tested` |
| Self-Managed quickstart | `docker/getting-started/` | Gateway, Dashboard, Redis, Postgres, bootstrap. **Starts with `./start.sh`, not `docker compose up` — see the note below** | Dashboard, in `docker/self-managed/.env` | `bundled-tested` |
| Self-Managed full | `docker/self-managed/` | Gateway, Dashboard, Pump, Portal, Redis, Postgres | Dashboard, Portal | `bundled-tested` |
| Hybrid data plane | `docker/hybrid/` | Gateway, Pump, Redis → Tyk Cloud MDCB | Tyk Cloud account | `bundled` |
| MDCB control plane | `docker/mdcb/control-plane/` | Dashboard, MDCB, Gateway, Pump, Redis, Postgres | Dashboard, MDCB | `bundled-tested` |
| MDCB data plane | `docker/mdcb/data-plane/` | Gateway (RPC), Pump, Redis → self-hosted MDCB | inherited via MDCB | `bundled-tested` |
| AI Studio | `docker/ai-studio/` | AI Studio, Microgateway, analytics pulse, Postgres | AI Studio | `bundled` |

`docker/getting-started/` is not a standalone stack: its `docker-compose.yml` defines only an
`httpbin` service and is layered over `docker/self-managed/docker-compose.yml` by `start.sh`.
`docker compose up -d` there fails with `refers to undefined network tyk`, and the directory has no
`.env.example`. Because `start.sh` passes the self-managed compose file first, Compose takes its
project directory from there — so the licence goes in **`docker/self-managed/.env`**, not in
`getting-started/`. A `.env` in `getting-started/` is silently ignored.

## Kubernetes (Helm)

| Edition | Directory | Chart | Licence | Status |
| --- | --- | --- | --- | --- |
| OSS | `kubernetes/helm-oss/` | `tyk-helm/tyk-oss` | none | `bundled-tested` |
| Self-Managed | `kubernetes/helm-self-managed/` | `tyk-helm/tyk-stack` | Dashboard, Portal, **and Operator as shipped** — see note | `bundled` |
| Hybrid data plane | `kubernetes/helm-hybrid/` | `tyk-helm/tyk-data-plane` | Tyk Cloud account | `bundled` |
| MDCB control plane | `kubernetes/helm-mdcb/values-control-plane.yaml` | `tyk-helm/tyk-control-plane` | Dashboard, MDCB | `bundled` |
| MDCB data plane | `kubernetes/helm-mdcb/values-data-plane.yaml` | `tyk-helm/tyk-data-plane` | inherited via MDCB | `bundled` |
| Operator only | `kubernetes/standalone-operator/` | `tyk-helm/tyk-operator` | Operator | `bundled` |

**`kubernetes/helm-self-managed/values.yaml` enables the Tyk Operator** (`operator: true`). As
shipped, that row therefore needs a **third licence** the Licence column above would not otherwise
imply, and it pulls in cert-manager plus cluster-admin rights to install CRDs. The rendered
bootstrap Job reads `TYK_K8SBOOTSTRAP_OPERATORLICENSEKEY` from the `OperatorLicense` secret key.

If the user holds only Dashboard and Portal licences, set `global.components.operator: false` in an
overlay before installing, and say you have done so. Do not guess what an empty
`TYK_OPERATOR_LICENSE` with `operator: true` does — it is not documented here, so make it an
explicit decision for the user.

## Bare metal / VM

| Edition | Directory | Method | Status |
| --- | --- | --- | --- |
| Gateway on rpm/deb | `baremetal/` | packages + systemd, Redis and Postgres supplied by the operator | `bundled-tested` (gateway; dashboard and pump `bundled`) |

**Bare metal covers Gateway, Dashboard and Pump only.** There is no bare-metal MDCB, control
plane, data plane, Portal, or Operator — `baremetal/install.sh` accepts exactly
`gateway`, `dashboard`, `pump`. So "MDCB on bare metal" and "hybrid on bare metal" are combinations
with no row. Say so rather than assembling one.

Bare metal needs a Linux host with systemd. The gateway path is verified end to end in an
Ubuntu 26.04 VM; dashboard and pump on bare metal are not. `--dry-run` works from any host,
including macOS, for reviewing the plan.

Note the packages are not published for every distribution release. Pin the upstream codename with
`--os`/`--dist` when yours is newer than Tyk's builds.

## Platform overlays

OpenShift is not a separate directory. It is an overlay carried inside the Helm values as
`# Required for deploying on RedHat OpenShift` blocks, activated with:

```bash
python3 skills/tyk-production-readiness/scripts/profiles.py \
  apply kubernetes/helm-self-managed/values.yaml --profile openshift -o openshift-values.yaml
```

Then install with both files, base first. OpenShift also needs `Route` rather than `Ingress` — the
`oc expose svc` recipes are in each Helm README under "OpenShift Routes".

Overlay coverage: `kubernetes/helm-self-managed/values.yaml` has 5 blocks,
`kubernetes/helm-hybrid/values.yaml` has 2. `helm-oss` and `helm-mdcb` carry them too. There is no
OpenShift overlay for the Docker paths, because Docker does not have SCCs.

## Not supported

| Request | Answer |
| --- | --- |
| Tyk Cloud control plane provisioning | Done in the Tyk Cloud UI, not from here. This repository covers the customer-hosted data plane that connects to it (`docker/hybrid/`, `kubernetes/helm-hybrid/`). |
| Cloud infrastructure provisioning (EKS/AKS/GKE, Terraform) | Out of scope. Bring your own cluster, Redis, and Postgres. |
| Windows hosts | Not supported. |

## Choosing

Step 1 is a **gate**, not a preference: a licence you do not hold rules a row out no matter how well
it fits otherwise. Work through these in order and stop at the first that decides the question.

1. **Which licences does the user actually hold?** This eliminates rows before anything else is
   considered.
   - none → **OSS only**. Every other edition needs a licence. OSS has no Dashboard, so "I just
     want to try the UI" is not satisfiable without one.
   - Tyk Cloud account → hybrid data plane.
   - Dashboard → Self-Managed. Add Portal if they hold that too.
   - Dashboard **and** MDCB → MDCB is available; still check step 3 before choosing it.
2. **Just evaluating, and they hold a Dashboard licence?** → `docker/getting-started/`, which
   bootstraps APIs and a Dashboard user for them. Do not send someone to the full stack to answer
   "can I try Tyk". Without a Dashboard licence this row is not available — go to `docker/oss/`.
3. **Platform?** Laptop or single VM → Docker. Cluster → Helm. No container runtime → bare metal.
4. **Do they need MDCB, or just high availability?** These are different, and the answer is usually
   the second. Note this interacts with step 3 rather than being independent of it: **MDCB exists
   only on Docker and Helm.** If step 3 landed on bare metal and this step says MDCB, the request
   has no row — stop and say so.

   - Two or more gateways behind a load balancer against **one** control plane gives high
     availability. That is Self-Managed, and it is what most "we need HA" requests mean.
   - MDCB is for when sites must be **independent**: separate regions or data centres, data planes
     that must keep serving through a control-plane outage, or traffic that must stay in a
     jurisdiction. Ask *why* there are two sites before deciding.
   - If MDCB is right, read `multi-site.md` before planning — MDCB does not by itself give two
     symmetric sites, and the difference matters.
5. **RedHat OpenShift?** Pick the Helm row, then add the `openshift` profile.

Record the chosen row, its status, the licences required, and the pinned versions in the plan.
