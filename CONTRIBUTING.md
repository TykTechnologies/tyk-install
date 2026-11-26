# Contributing

Thanks for helping improve the Tyk deployment configurations. Report security problems through
[SECURITY.md](SECURITY.md), never as an issue or pull request.

## Pull requests

1. Fork the repository, or create a branch if you have write access. `main` is protected: every
   change lands through a pull request.
2. Keep a pull request to one topic. Update the README of every deployment directory you change,
   and [`docs/topology-matrix.md`](docs/topology-matrix.md) if you add, rename or remove one.
3. Run the checks below locally, then open the pull request against `main`. A maintainer reviews
   and merges it once the checks pass.

## Checks

The [lint workflow](.github/workflows/lint.yml) runs on every pull request. Run the same checks
before pushing:

| Check | Command |
| --- | --- |
| YAML | `yamllint -d "{extends: relaxed, rules: {line-length: disable, truthy: disable}}" <files>`, over the paths listed in the workflow |
| Topology matrix paths | `python3 tools/check_topology_matrix.py` |
| Shell scripts | `shellcheck -S error <script>.sh` |
| Markdown style | `npx -y markdownlint-cli2@0.24.2 --config .github/.markdownlint.json "**/*.md"` |
| Markdown links | run by the workflow on every pull request |

For a Compose change, also run `docker compose -f <file> config -q` with a copy of the directory's
`.env.example` as `.env`, and delete that copy afterwards.

## Pinning

- Pin every image to an exact tag that exists in its registry. Do not use `latest` where the
  registry publishes version tags, and never make a release candidate the default.
- Tyk component versions live in each `.env.example` and in the Helm `values*.yaml` image tags. A
  workflow in the Tyk docs repository raises a pull request to move them on each release, so do
  not bump them by hand in an unrelated pull request.
- Third-party images (Redis, PostgreSQL, the observability stack, `go-httpbin`, `alpine`, `hurl`)
  and the versions in README examples are updated by hand. Move every copy of a pin together.

## Marker comments

Production, performance, security and OpenShift guidance lives as a comment beside the setting it
applies to, and [`tools/profiles.py`](tools/profiles.py) reads it:

```text
TYK_GW_LOGLEVEL=info # PROD: Set to "error" to reduce log volume
# TYK_GW_MAXIDLECONNSPERHOST=10000 # PROD/PERFORMANCE: Set high value (>=10000)
TYK_GW_SECRET=... # SECURITY: Change to a strong 32+ character string
# Required for deploying on RedHat OpenShift
```

Keep the marker words (`PROD:`, `PROD/PERFORMANCE:`, `SECURITY:`) in capitals with the colon, put
the advice on the same line as the setting, and check the result with
`python3 tools/profiles.py audit <file> --profile prod --profile performance --profile security`.

## Secrets

Never commit a licence, API key, password or real endpoint. Real values go in a gitignored `.env`;
committed files carry empty values or placeholders such as `your-mdcb.cloud-ara.tyk.io:443`.
