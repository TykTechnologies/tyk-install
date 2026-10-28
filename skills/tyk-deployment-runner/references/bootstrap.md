# Bootstrap

A freshly started licensed stack has no organisation, no user, and no APIs. Bootstrapping creates
them. OSS needs none of this — its APIs are files on disk.

## Which path

| Target | Bootstrap |
| --- | --- |
| `docker/oss/` | none. Drop a definition in `apps/`, restart the Gateway. |
| `docker/getting-started/` | built in — `start.sh` runs `bootstrap/bootstrap.hurl` |
| `docker/self-managed/`, MDCB control plane | `utils/bootstrap/` |
| `kubernetes/helm-*` | `utils/bootstrap/` against the Dashboard's service |

## docker/getting-started

```bash
cd docker/getting-started
./start.sh
```

Creates the organisation, an admin user, sample APIs including a Petstore OAS API, and prints the
credentials. This is the evaluation path — prefer it when someone just wants to see Tyk working.

It needs `hurl`, which is usually not installed: `brew install hurl`. The script runs it from a
container image, so check `start.sh` before assuming a local install is required.

## utils/bootstrap

```bash
cd utils/bootstrap
cp .env.example .env      # set the Dashboard URL and licence
docker compose up
cat bootstrap-output/bootstrap-credentials.txt
```

Creates the organisation, admin user, a test API, policies, and Portal configuration. Idempotent:
re-running detects the `.bootstrap_completed` marker and does not duplicate the organisation —
which is what makes it usable in the idempotency check.

`bootstrap-output/` and `bootstrap-credentials.txt` are gitignored. Never print their contents into
a report, a log, or a chat message, and never commit them.

## Doing it by hand

Against the Dashboard admin API, with `TYK_DB_ADMINSECRET` from `confs/tyk_analytics.env`:

```bash
# Create an organisation
curl -s -X POST http://localhost:3000/admin/organisations \
  -H "admin-auth: $ADMIN_SECRET" -H 'Content-Type: application/json' \
  -d '{"owner_name":"Example","cname_enabled":true}'

# Create a user in it
curl -s -X POST http://localhost:3000/admin/users \
  -H "admin-auth: $ADMIN_SECRET" -H 'Content-Type: application/json' \
  -d '{"org_id":"<org-id>","first_name":"Admin","email_address":"admin@example.local","active":true,"user_permissions":{"IsAdmin":"admin"}}'
```

The response carries the user's `access_key`, which is the Dashboard API key for everything after
this. Reference `$ADMIN_SECRET` from the environment; do not paste a literal secret into a command
you will show the user.

## Adding a first API

```bash
# Self-Managed, via the Dashboard API
curl -s -X POST http://localhost:3000/api/apis/oas \
  -H "authorization: $DASH_KEY" -H 'Content-Type: application/json' \
  -d @my-api.oas.json
```

```bash
# OSS, on disk
cp my-api.json docker/oss/apps/
docker compose restart tyk-gateway
docker compose logs tyk-gateway | grep 'API Loaded'
```

## Verifying the bootstrap worked

Creating an organisation is not evidence that traffic flows. After bootstrapping, prove a request
reaches an upstream:

```bash
./skills/tyk-deployment-runner/scripts/verify_deployment.sh \
  --edition self-managed --route /<your-listen-path>/
```

## Reference

- <https://tyk.io/docs/dashboard-admin-api.mdx>
- <https://tyk.io/docs/tyk-dashboard-api.mdx>
- <https://tyk.io/docs/getting-started>
