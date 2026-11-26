# Tyk Self-Managed Getting Started — Docker

The full [Self-Managed stack](../self-managed/) plus sample APIs, policies and Developer Portal
content, bootstrapped for you. This directory is not a standalone stack: `start.sh` layers its
`docker-compose.yml` (one local `httpbin` upstream) over `../self-managed/docker-compose.yml`, then
runs `bootstrap/bootstrap.hurl` in a container. No local `hurl` install is needed.

## Quick start

The licences go in `../self-managed/.env`, not here: Compose reads the `.env` beside the first
compose file it is given.

```bash
cp ../self-managed/.env.example ../self-managed/.env   # set TYK_LICENSE_KEY and TYK_PORTAL_LICENSE
./start.sh
```

## Credentials

| Service | URL | Login |
| --- | --- | --- |
| Dashboard | `http://localhost:3000` | `developer@tyk.io` / `specialpassword` |
| Developer Portal | `http://localhost:3001` | `portaladmin@tyk.io` / `specialpassword` |

These are development defaults. Do not expose this stack beyond your machine.

## Verify

```bash
../../tools/verify_deployment.sh --edition self-managed
```

The sample APIs need an API key, so add `--route` with a key-free API of your own to prove a request
reaches an upstream.

## Teardown

```bash
docker compose -p tyk-getting-started \
  -f ../self-managed/docker-compose.yml -f docker-compose.yml down -v
```

More in [`../../docs/runtime.md`](../../docs/runtime.md) and
[`../../docs/bootstrap.md`](../../docs/bootstrap.md).
