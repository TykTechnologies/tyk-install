# Multi-site

Read this before planning MDCB. The topology matrix routes "more than one data centre" here, and
that routing is right, but MDCB does not by itself deliver what most people mean by "either site
can fail" — and the difference decides the design.

## What MDCB actually gives you

An **asymmetric** topology. One site owns the control plane; the others are data planes.

| If this fails | Then |
| --- | --- |
| A data-plane site | Its traffic stops. Other data planes are unaffected. The control plane is unaffected. |
| The **control-plane** site | Every data plane keeps proxying existing traffic — **only if the synchroniser is on**. But the Dashboard is gone, no configuration or key changes propagate, new keys cannot be created, and analytics stop being collected centrally. |

So a control-plane-site outage is not an outage, but it is a **frozen, read-only** period across
every remaining site. Whether that is acceptable is a business decision, and it is the first thing
to establish with the user.

**The synchroniser is what makes this true, and it is off by default.** Without it a data plane
holds no local keyspace copy and will not survive losing the control plane, which removes the main
reason to run MDCB at all:

- Control plane: `TYK_MDCB_SYNCWORKER_ENABLED=true`, or `global.mdcbSynchronizer.enabled: true`.
- Each data plane: `TYK_GW_SLAVEOPTIONS_SYNCHRONISERENABLED=true`.

Both halves are required. Setting one is a silent half-configuration.

## What this repository does not cover

Be direct with the user about where the guidance stops. None of the following has a tested pattern
here, and inventing one is worse than saying so:

- **An active/active control plane.** Two control planes, either able to serve writes, is not a
  configuration this repository describes or tests. If the user needs it, involve Tyk directly
  rather than assembling something from these files.
- **Cross-site PostgreSQL.** The control plane's Postgres holds API definitions, policies, and
  users. Replicating it across sites, and deciding what happens on failover, is a database design
  problem this repository does not address.
- **Cross-site Redis.** Do not try. Each data plane must have its **own local** Redis — that is
  precisely what lets it keep serving through a control-plane outage. Stretching one Redis across
  sites reintroduces the dependency you are trying to remove, and adds cross-site latency to every
  rate-limit check.
- **Traffic steering between sites.** DNS, GSLB, anycast, or a global load balancer is where the
  user's "either site serves traffic" requirement is actually met. Tyk does not do it, and nothing
  here configures it.
- **Backup and restore of the control plane**, which is what actually bounds a control-plane-site
  disaster. See `../../tyk-production-readiness/references/hardening.md`.

## Questions to settle before planning

Record the answers in the deployment plan. Several change the topology, not just the values.

1. **Why two sites?** Latency, data residency, or resilience? Residency usually forces MDCB.
   Resilience alone often does not — see the next question.
2. **Would two gateways behind a load balancer in one site do?** For most "we need HA" requests it
   would, and Self-Managed is far fewer moving parts. Do not sell MDCB to someone who needs
   replicas.
3. **Which site owns the control plane?** There has to be an answer, and the user should choose it
   deliberately rather than discovering it later.
4. **Is a read-only period acceptable in the surviving sites** while the control-plane site is
   down — no config changes, no new keys? If not, MDCB alone does not meet the requirement.
5. **What is the RTO for the control plane?** This drives the backup and restore design, which
   matters more than any Tyk setting here.
6. **How does client traffic reach the right site?** Confirm something owns this. It is routinely
   assumed and routinely missing.

## Planning notes

- **Start with one site.** Stand up the control plane and one data plane, verify the RPC bridge and
  a proxied request, then add the second site. Two sites at once means two untested things failing
  together.
- **TLS on the RPC link.** It crosses a network boundary between sites, so `TYK_MDCB_USESSL=true`
  and `sslInsecureSkipVerify: false` on the data planes. The development defaults do the opposite.
- **MDCB must be reachable from every data-plane network** on 9091, and it speaks gRPC — a plain
  HTTP ingress or OpenShift Route will not carry it. Plan a LoadBalancer or a gRPC-aware ingress.
- **Two or more MDCB replicas.** Every data plane depends on MDCB to pick up changes.
- **Version order:** upgrade the control plane before any data plane. A newer data plane against an
  older control plane is unsupported.
- `TYK_MDCB_HASHKEYS` and each gateway's `TYK_GW_HASHKEYS` must match, or keys will not resolve
  across the bridge.

## Reference

- <https://tyk.io/docs/tyk-multi-data-centre>
- <https://tyk.io/docs/planning-for-production>
- Artifacts and the RPC troubleshooting table: [`../../../docker/mdcb/README.md`](../../../docker/mdcb/README.md)
- Kubernetes equivalents: [`../../../kubernetes/helm-mdcb/README.md`](../../../kubernetes/helm-mdcb/README.md)
