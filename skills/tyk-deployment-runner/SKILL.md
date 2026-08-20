---
name: tyk-deployment-runner
description: Start a Tyk deployment, bootstrap it, and prove it works. Use when running or restarting a Tyk stack with Docker Compose, Helm, or bare-metal packages, when bootstrapping an organisation, Dashboard user, or first API, and when a Tyk deployment is up but not behaving — gateway not starting, Dashboard licence errors, Redis or Postgres connection failures, MDCB RPC handshake problems, or a request not reaching its upstream. Collects executable evidence rather than reporting success from container status alone.
---

# Tyk Deployment Runner

Apply a deployment and prove it works. Prefer an existing plan from `tyk-deployment-planner`; if
there is none, resolve the target against the topology matrix that skill owns
(`tyk-deployment-planner/references/topology-matrix.md`) before starting anything.

## Workflow

1. Read the plan if one exists. Otherwise resolve exactly one matrix row and confirm it with the
   user.
2. Echo the target before touching it: Docker context, or Kubernetes context and namespace, plus
   what will be created. For a cluster, confirm the namespace is one the user intends to use.
3. Prepare secrets: `cp .env.example .env` in the target directory, then have the user supply
   licence values. Never print them, and never commit `.env`.
4. Start the stack. Read `references/runtime.md` for per-platform commands, ordering, and the
   dependency waits that matter.
5. Bootstrap. Read `references/bootstrap.md` — `utils/bootstrap/` creates the organisation, admin
   user, a test API, and Portal configuration.
6. Verify with `scripts/verify_deployment.sh`. Include its real output.
7. Prove idempotency: re-run configuration and show the second run changes nothing.
8. Prove persistence: restart the stack and re-run verification.
9. Report versions deployed, URLs, evidence, and anything left unverified.

## Running

```bash
# Docker  (see references/runtime.md -- docker/getting-started/ is an exception
#          and must be started with its own ./start.sh, not `compose up`)
cd docker/<target> && cp .env.example .env   # then fill in licence values
docker compose up -d
docker compose ps

# Helm
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ && helm repo update
helm upgrade --install tyk tyk-helm/<chart> -n <namespace> --create-namespace \
  -f kubernetes/<target>/values.yaml -f <overlay>.yaml
```

Order matters. Redis and Postgres must be ready before the Dashboard, the Dashboard before the
Gateway, and an MDCB control plane before any data plane. The Compose files encode this with
healthchecks and `depends_on`; on Kubernetes use `kubectl wait --for=condition=ready`.

## Evidence

Container status is not evidence. A gateway can be `running` and still route nothing.

Required before reporting success:

- Gateway `/hello` returns healthy, with its Redis and Dashboard components healthy where they apply.
- Dashboard `/hello` returns healthy and the licence is valid, on licensed editions.
- **A real request reaches an upstream through the gateway** and returns the upstream's response.
- Idempotency: configuration re-run leaves the deployment unchanged.
- Persistence: after `docker compose restart` or a pod restart, the above still holds.

```bash
# Docker
./skills/tyk-deployment-runner/scripts/verify_deployment.sh \
  --edition self-managed --stack self-managed --route /httpbin/get

# Kubernetes or OpenShift: --namespace switches component checks to kubectl
kubectl port-forward -n tyk svc/gateway-svc-tyk-tyk-gateway 8080:8080 &
./skills/tyk-deployment-runner/scripts/verify_deployment.sh \
  --edition self-managed --namespace tyk --route /httpbin/get
```

Always pass `--stack` (Docker) or `--namespace` (Kubernetes). Without them the script picks the
first matching container on the host, which on a machine running more than one Tyk stack can
report another deployment's Redis as evidence for yours.

Report what the commands actually returned. If a check could not run — no licence, no cluster, no
egress — name the check and the reason. An unverified deployment is reported as unverified.

## References

- Read `references/runtime.md` for per-platform start, stop, upgrade, and teardown commands.
- Read `references/bootstrap.md` for organisation, user, API, and Portal bootstrapping, and for
  recovering credentials without touching the database.
- Read `references/debugging.md` whenever a verification step fails. Read it before changing
  configuration, not after.

## Safety

- Never delete, upgrade, or reconfigure resources the user did not ask you to touch. Ask before
  reusing a namespace, project, or Compose stack that already exists.
- Do not use direct database access for normal bootstrap or credential recovery. Use the APIs.
- Never print or commit a licence, token, generated credential, or certificate. `.env` is
  gitignored and must stay that way.
- Prefer an overlay over editing a tracked config file. If a tracked file must change, say so
  explicitly and show the diff.
- `docker compose down -v` destroys data. Confirm before running it, and never run it against a
  stack you did not create in this session.
- The Postgres and Redis passwords and the Gateway secrets committed here are development
  defaults. Refuse to treat a deployment using them as production-ready, and say why.

## Completion Contract

Finish when every required evidence item above has real command output behind it, idempotency and
persistence are demonstrated, and the report lists deployed versions, URLs, the exact rerun
commands, and every check that could not be performed with its reason.
