# Tyk on bare metal / VMs

Tyk installed from rpm/deb packages with systemd. No container runtime.

## When to use this

Choose bare metal when a container runtime is genuinely unavailable — a locked-down or regulated
host, an existing VM fleet with established configuration management, or a policy that forbids
containers. Otherwise [`../docker/`](../docker/) or [`../kubernetes/`](../kubernetes/) will be less
work to run and upgrade.

| | Bare metal | Docker | Kubernetes |
| --- | --- | --- | --- |
| Redis / PostgreSQL | you provide | included | you provide |
| Upgrades | package manager, per host | change a tag | `helm upgrade` |
| Scaling out | provision another host | `--scale` | `replicaCount` |
| Config reload | `systemctl restart` | `compose restart` | rolling update |

## Configuration format

Tyk's native config files are JSON — `/opt/tyk-gateway/tyk.conf`,
`/opt/tyk-dashboard/tyk_analytics.conf`, `/opt/tyk-pump/pump.conf` — and JSON cannot carry
comments.

This path therefore configures Tyk through the environment instead. Every Tyk setting has a
`TYK_*` variable equivalent, so `confs/gateway.env` holds the same settings as
[`../docker/self-managed/confs/tyk.env`](../docker/self-managed/confs/tyk.env), with the same
`# PROD:`, `# PROD/PERFORMANCE:`, and `# SECURITY:` marker comments — so `profiles.py` works here
exactly as it does everywhere else:

```bash
python3 ../skills/tyk-production-readiness/scripts/profiles.py \
  audit confs/gateway.env --profile prod --profile security
```

Environment variables take precedence over the JSON file, so the packaged `tyk.conf` can be left
alone. The packaged units already read `/etc/default/tyk-<component>`, so that is where
`install.sh` writes — no systemd drop-in is needed for configuration.

**One catch, and it is the reason `install.sh` transforms the file rather than copying it.**
systemd's `EnvironmentFile` does *not* strip trailing comments: it takes everything after `=`
literally. So a line that works fine in Docker Compose —

```bash
TYK_GW_HTTPSERVEROPTIONS_USESSL=false # PROD: Set to true to enable SSL/TLS
```

reaches Tyk as the string `false # PROD: Set to true to enable SSL/TLS`, and the gateway exits with
`strconv.ParseBool: invalid syntax`. Docker Compose's `env_file` parser strips the comment; systemd
does not.

`install.sh` therefore installs a **sanitised copy** with comments removed, leaving the annotated
file in `confs/` as the human- and `profiles.py`-readable source. `verify.sh` fails if an installed
file still contains inline comments. Never copy `confs/*.env` to `/etc/default/` by hand.

## Prerequisites

| | |
| --- | --- |
| OS | RHEL / Rocky / Alma 8+, or Ubuntu / Debian. systemd required. |
| Redis | required by the Gateway. Not installed by these scripts. |
| PostgreSQL | required by the Dashboard and Pump. Not installed by these scripts. |
| Licences | `TYK_LICENSE_KEY` for the Dashboard. The Gateway alone needs none. |

Packages come from Tyk's own repositories on [packagecloud.io](https://packagecloud.io/tyk), one
per component: `tyk/tyk-gateway`, `tyk/tyk-dashboard`, `tyk/tyk-pump`.

## Install

Review the plan first. `--dry-run` changes nothing and works on any host, including macOS:

```bash
./install.sh --dry-run --components gateway,dashboard,pump
```

Then, on the Linux host:

```bash
sudo ./install.sh --components gateway,dashboard,pump
```

To pin a version rather than taking the repository's latest:

```bash
sudo ./install.sh --components gateway --version 5.14.0
```

If your distribution is newer than Tyk's published builds, pin the upstream repository codename.
packagecloud 404s on an unknown codename and apt then reports "does not have a Release file":

```bash
# e.g. on Ubuntu 26.04 (resolute), for which no build is published
sudo ./install.sh --components gateway --os ubuntu --dist noble
```

Known-good: `ubuntu noble`/`jammy`, `debian bookworm`, `el 8`/`9`.

**A gateway installed without the dashboard** is switched automatically to file-based APIs
(`TYK_GW_USEDBAPPCONFIGS=false`, definitions from `/opt/tyk-gateway/apps`). Without that it would
point at a Dashboard that does not exist, and `/hello` would report `warn` with dashboard `fail`
while no APIs ever load.

Supply licences without putting them on a command line or in a tracked file:

```bash
sudo ./install.sh --components gateway,dashboard --env-file /root/tyk-licences.env
```

`install.sh` is idempotent: an already-installed package is skipped, and the config and drop-ins
are rewritten to the same content. It never prints a licence value.

What it does, in order: adds the packagecloud repository per component, installs the packages,
writes a comment-stripped copy of `confs/<component>.env` to `/etc/default/tyk-<component>`
(mode 0640), writes a hardening drop-in per unit, then enables and restarts each service.

## Configure

Edit the annotated source and re-run the installer, so the sanitising step is never skipped:

```bash
vi confs/gateway.env                 # the annotated source
sudo ./install.sh --components gateway   # re-renders /etc/default/tyk-gateway
```

Or edit the installed file directly — but with no inline comments:

```bash
sudo vi /etc/default/tyk-gateway
sudo systemctl restart tyk-gateway
```

Point the Gateway at your Redis and the Dashboard at your PostgreSQL — the defaults assume both on
`127.0.0.1`:

```bash
TYK_GW_STORAGE_ADDRS=127.0.0.1:6379
TYK_DB_STORAGE_MAIN_CONNECTIONSTRING=host=127.0.0.1 port=5432 user=tykuser password=... dbname=tyk_analytics
```

`systemd/` holds reference copies of the hardening drop-ins.
Review those against your environment before enabling them: `ProtectHome` and a read-only
filesystem will break custom plugin paths or certificates stored outside `/opt/tyk-gateway`.

## Bootstrap

A fresh Dashboard has no organisation or user. See
[`../skills/tyk-deployment-runner/references/bootstrap.md`](../skills/tyk-deployment-runner/references/bootstrap.md);
the admin API calls there apply unchanged, with `TYK_DB_ADMINSECRET` from
`/etc/default/tyk-dashboard`.

## Verify

```bash
./verify.sh --components gateway,dashboard,pump
./verify.sh --components gateway --route /your-listen-path/
```

Checks unit state, whether each unit is enabled at boot, that config exists at
`/etc/default/tyk-<component>` and contains no inline comments, that `/hello` reports
`status=pass` rather than merely returning 200, and Redis and PostgreSQL reachability. Exits
non-zero on failure.

Pass `--route` to prove a request actually reaches an upstream. Units being active is not evidence
that traffic flows.

## Upgrade

Control plane before data planes, and never split Gateway and Dashboard minor versions.

```bash
sudo apt-get update && sudo apt-get install --only-upgrade tyk-gateway
# or
sudo yum update tyk-gateway

sudo systemctl restart tyk-gateway
./verify.sh --components gateway --route /your-listen-path/
```

Check the release notes first: <https://tyk.io/docs/developer-support/release-notes/overview>

## Uninstall

```bash
sudo systemctl disable --now tyk-gateway tyk-dashboard tyk-pump
sudo apt-get remove tyk-gateway tyk-dashboard tyk-pump    # or: yum remove
sudo rm -f /etc/default/tyk-gateway /etc/default/tyk-dashboard /etc/default/tyk-pump
sudo rm -rf /etc/systemd/system/tyk-*.service.d
sudo systemctl daemon-reload
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| unit `active` but `/hello` fails | `journalctl -u tyk-gateway -n 50`. Usually Redis. |
| unit fails immediately with `strconv.ParseBool` or similar | An inline comment reached the value. `grep ' # ' /etc/default/tyk-gateway` — re-run `install.sh` rather than hand-copying `confs/*.env`. |
| unit fails immediately | A malformed line in `/etc/default/tyk-*` — a stray quote is enough. |
| `/hello` returns 200 but `status=warn` | A component is failing. Usually a gateway pointed at a Dashboard that is not installed; see the note under Install. |
| `license is invalid` | `TYK_LICENSE_KEY` in `/etc/default/tyk-dashboard`. Trials expire. |
| apt: `does not have a Release file` | No published build for your codename. Pin with `--os`/`--dist`. |
| permission denied on start | SELinux. Check `ausearch -m avc -ts recent`. |

More in
[`../skills/tyk-deployment-runner/references/debugging.md`](../skills/tyk-deployment-runner/references/debugging.md).

## Before production

```bash
python3 ../skills/tyk-production-readiness/scripts/profiles.py \
  audit confs/*.env --profile prod --profile performance --profile security
```

Beyond the markers: `TYK_GW_SECRET` and `TYK_GW_NODESECRET` are inherited from the Docker configs
as the same hardcoded development value and must be replaced (`openssl rand -hex 32`), the
PostgreSQL connection string carries a committed development password, and a single Redis or
PostgreSQL host is a data-loss risk rather than a tuning gap.

## Verified

Verified in an Ubuntu 26.04 VM (systemd 259, arm64) with Tyk Gateway 5.14.0 from packagecloud
pinned to `ubuntu noble`: unit active and enabled, config installed with comments stripped,
`/hello` reporting `status=pass`, Redis reachable, and a file-defined API proxying a request.
Dashboard and Pump on bare metal are not yet verified.

## Reference

- <https://tyk.io/docs/tyk-self-managed/install/linux>
- <https://packagecloud.io/tyk>
- <https://tyk.io/docs/tyk-configuration-reference>
- <https://tyk.io/docs/planning-for-production>
