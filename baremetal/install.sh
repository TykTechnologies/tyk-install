#!/usr/bin/env bash
# Install Tyk from packages onto a Linux host, with systemd.
#
#   sudo ./install.sh --components gateway,dashboard,pump
#   sudo ./install.sh --components mdcb,portal,sync
#   ./install.sh --dry-run --components gateway        # prints the plan, changes nothing
#
# Idempotent: re-running installs nothing new and rewrites the same drop-ins.
# Never echoes a licence value. Licences are read from the environment or from a
# file you pass with --env-file, and written only to root-owned drop-ins.
#
# Package repositories, package names, service names, and config paths are taken
# from https://tyk.io/docs/tyk-self-managed/install/linux
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
COMPONENTS=gateway
DRY_RUN=false
ENV_FILE=
VERSION=
DIST=
OSNAME=
MIRROR=https://packagecloud.io/tyk
RPM_KEY=

# Lookups are case statements rather than associative arrays so this runs on
# bash 3.2, which is what macOS ships -- --dry-run is meant to be reviewable
# from any host, not only from the Linux box being installed.
COMPONENT_LIST="gateway dashboard pump mdcb portal sync"
known()   { case " $COMPONENT_LIST " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
# packagecloud repository, package, and systemd service per component. Most are
# tyk-<component>; MDCB ships as tyk-sink from tyk-mdcb-stable, the Developer
# Portal as portal, and Tyk Sync is a command-line tool with no service.
repo_of() {
  case "$1" in mdcb) printf 'tyk-mdcb-stable' ;; portal) printf 'portal' ;; *) printf 'tyk-%s' "$1" ;; esac
}
pkg_of() {
  case "$1" in mdcb) printf 'tyk-sink' ;; portal) printf 'portal' ;; *) printf 'tyk-%s' "$1" ;; esac
}
svc_of() {
  case "$1" in sync) printf '' ;; *) pkg_of "$1" ;; esac
}
env_of()  { printf '%s.env' "$1"; }
conf_of() { printf '/opt/%s' "$(pkg_of "$1")"; }
# The licence variable a component's confs/<component>.env expands, if any.
licence_of() {
  case "$1" in
    dashboard) printf 'TYK_LICENSE_KEY' ;;
    mdcb)      printf 'TYK_MDCB_LICENSE' ;;
    portal)    printf 'TYK_PORTAL_LICENSE' ;;
    *)         printf '' ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [--components gateway,dashboard,pump] [options]

  --components  Comma-separated: gateway, dashboard, pump, mdcb, portal, sync.
                Default: gateway.
  --version     Pin a package version, e.g. 5.16.3. Default: the repo's latest.
  --env-file    File holding licence variables (TYK_LICENSE_KEY, ...). Values are
                never printed. Without this, the environment is used.
  --os/--dist   Override the upstream distribution used for the package repo, e.g.
                --os ubuntu --dist noble, or --os el --dist 9. Needed when your
                release is newer than Tyk's published builds (packagecloud returns
                404 for an unknown codename, and apt then reports "does not have a
                Release file"), or when /etc/os-release names a distribution this
                script does not map. Known-good: ubuntu noble/jammy, debian
                bookworm, el 8/9.
  --mirror      Base URL of a mirror laid out like https://packagecloud.io/tyk,
                for air-gapped hosts: <mirror>/tyk-gateway/gpgkey,
                <mirror>/tyk-gateway/ubuntu/..., <mirror>/tyk-gateway/el/9/...
                https:// or file:// (a local directory). See README.md,
                "Air-gapped hosts".
  --rpm-key     Where to get Tyk's RPM signing key. Default: the Tyk key server,
                or <mirror>/tyk.io.rpm.signing.key.2020 with --mirror.
  --dry-run     Print what would happen and exit. Safe to run anywhere.
  -h, --help    This message.

Redis is required for the gateway and MDCB; PostgreSQL for
the dashboard, pump, MDCB and portal. This script does NOT install or
configure either - point confs/<component>.env at yours.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --components) COMPONENTS=${2:?}; shift 2 ;;
    --version)    VERSION=${2:?}; shift 2 ;;
    --env-file)   ENV_FILE=${2:?}; shift 2 ;;
    --dist)       DIST=${2:?}; shift 2 ;;
    --os)         OSNAME=${2:?}; shift 2 ;;
    --mirror)     MIRROR=${2:?}; MIRROR=${MIRROR%/}; shift 2 ;;
    --rpm-key)    RPM_KEY=${2:?}; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

log()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
run()  {
  if [[ "$DRY_RUN" == true ]]; then printf '  would run: %s\n' "$*"; return 0; fi
  "$@"
}

IFS=',' read -r -a SELECTED <<< "$COMPONENTS"
for c in "${SELECTED[@]}"; do
  known "$c" || { printf 'Unknown component: %s\n' "$c" >&2; exit 2; }
done

# ---------------------------------------------------------------- platform
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then printf 'apt'; return 0; fi
  if command -v dnf >/dev/null 2>&1;     then printf 'dnf'; return 0; fi
  if command -v yum >/dev/null 2>&1;     then printf 'yum'; return 0; fi
  printf 'none'
}
PM=$(detect_pm)

step "Plan"
log "host:        $(uname -s) $(uname -m)"
log "package mgr: $PM"
log "components:  ${SELECTED[*]}"
log "version:     ${VERSION:-latest from repo}"
log "dry run:     $DRY_RUN"

if [[ "$PM" == none ]]; then
  printf '\nNo apt, dnf, or yum on this host.\n' >&2
  if [[ "$DRY_RUN" == true ]]; then
    printf 'Dry run continues so the plan can be reviewed anywhere; a real install\n' >&2
    printf 'needs a Linux host with systemd and apt or yum.\n' >&2
  else
    printf 'This path needs a Linux host with systemd and apt or yum.\n' >&2
    printf 'For macOS or Windows use ../docker/ instead.\n' >&2
    exit 1
  fi
fi

if ! command -v systemctl >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
  printf 'systemd not found. This path installs systemd units.\n' >&2
  exit 1
fi

if [[ "$DRY_RUN" != true && ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing packages and writing to /etc needs root. Re-run with sudo.\n' >&2
  exit 1
fi

# ---------------------------------------------------------------- licences
# Presence only. A value is never printed, and never passed on a command line.
step "Licences"
if [[ -n "$ENV_FILE" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
    log "loaded variables from $ENV_FILE (values not shown)"
  else
    printf 'env file not found: %s\n' "$ENV_FILE" >&2; exit 1
  fi
fi
for c in "${SELECTED[@]}"; do
  var=$(licence_of "$c")
  [[ -n "$var" ]] || continue
  if [[ -n "${!var:-}" ]]; then
    log "$var: set (value not shown)"
  else
    log "$var: MISSING - $c will not start without it"
    log "  add it to --env-file or export it; get one at https://tyk.io/sign-up/"
  fi
done

# ---------------------------------------------------------------- repositories
step "Package repositories"
# Each repository is written out explicitly and pinned to its signing key, as
# https://tyk.io/docs/tyk-self-managed/install/linux describes. Nothing fetched
# from the network is executed: packagecloud's install script is not used.
#
# The file names match the ones packagecloud's script writes, so a host set up
# that way is converted in place rather than left with two entries for the
# same repository (apt refuses conflicting Signed-By values).
os_field() {
  [[ -r /etc/os-release ]] || return 0
  sed -n "s/^$1=//p" /etc/os-release | tr -d '"' | head -n 1
}

resolve_upstream() {
  local id
  id=$(os_field ID)
  case "$PM" in
    apt)
      if [[ -z "$OSNAME" ]]; then
        case "$id" in ubuntu|debian) OSNAME=$id ;; esac
      fi
      [[ -n "$DIST" ]] || DIST=$(os_field VERSION_CODENAME)
      ;;
    yum|dnf)
      if [[ -z "$OSNAME" ]]; then
        case "$id" in rhel|centos|rocky|almalinux|ol) OSNAME=el ;; esac
      fi
      if [[ -z "$DIST" ]]; then
        DIST=$(os_field VERSION_ID)
        DIST=${DIST%%.*}
      fi
      ;;
    none)
      OSNAME=${OSNAME:-<os>}
      DIST=${DIST:-<dist>}
      return 0
      ;;
  esac
  if [[ -z "$OSNAME" || -z "$DIST" ]]; then
    printf '\nCannot map this distribution (%s) to a Tyk package repository.\n' "${id:-unknown}" >&2
    printf 'Pass one explicitly, e.g. --os ubuntu --dist noble, or --os el --dist 9.\n' >&2
    exit 2
  fi
}

# Write stdin to a file, or show it in a dry run.
write_file() {
  local dst=$1 mode=$2 content
  content=$(cat)
  if [[ "$DRY_RUN" == true ]]; then
    printf '  would write %s:\n' "$dst"
    printf '%s\n' "$content" | sed 's/^/      /'
    return 0
  fi
  install -d -m 0755 "$(dirname "$dst")"
  printf '%s\n' "$content" > "$dst.tmp"
  chmod "$mode" "$dst.tmp"
  mv "$dst.tmp" "$dst"
}

# Download a public signing key over HTTPS (or copy it from a local mirror), and
# refuse anything that is not one. A key is never fetched over plain HTTP.
fetch_key() {
  local url=$1 dst=$2
  if [[ "$DRY_RUN" == true ]]; then
    printf '  would download %s -> %s\n' "$url" "$dst"
    return 0
  fi
  install -d -m 0755 "$(dirname "$dst")"
  if ! curl -fsSL --proto '=https,file' --tlsv1.2 -o "$dst.tmp" "$url"; then
    printf 'Could not fetch %s (only https:// and file:// are accepted for keys).\n' "$url" >&2
    rm -f "$dst.tmp"
    exit 1
  fi
  if ! grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$dst.tmp"; then
    printf 'Not a PGP public key: %s\n' "$url" >&2
    rm -f "$dst.tmp"
    exit 1
  fi
  chmod 0644 "$dst.tmp"
  mv "$dst.tmp" "$dst"
}

# RPM packages are signed with Tyk's own key, and repository metadata with each
# packagecloud repository's key. Tyk's key is imported into rpm up front rather
# than listed in gpgkey=: dnf imports every listed key when it checks a package,
# and on EL9 the packagecloud key's SHA-1 self-signature is rejected by the
# default crypto policy, which fails the whole install. Listed alone, the
# packagecloud key is used for repository metadata only, which EL9 accepts.
if [[ -z "$RPM_KEY" ]]; then
  if [[ "$MIRROR" == https://packagecloud.io/tyk ]]; then
    RPM_KEY=https://keyserver.tyk.io/tyk.io.rpm.signing.key.2020
  else
    RPM_KEY="$MIRROR/tyk.io.rpm.signing.key.2020"
  fi
fi
RPM_KEY_IMPORTED=false

add_repo() {
  local repo=$1 base="$MIRROR/$1" key
  case "$PM" in
    apt)
      key="/etc/apt/keyrings/tyk_${repo}.asc"
      fetch_key "$base/gpgkey" "$key"
      printf 'deb [signed-by=%s] %s/%s/ %s main' "$key" "$base" "$OSNAME" "$DIST" \
        | write_file "/etc/apt/sources.list.d/tyk_${repo}.list" 0644
      ;;
    yum|dnf)
      if [[ "$RPM_KEY_IMPORTED" != true ]]; then
        key=/etc/pki/rpm-gpg/RPM-GPG-KEY-tyk
        fetch_key "$RPM_KEY" "$key"
        run rpm --import "$key"
        RPM_KEY_IMPORTED=true
      fi
      # A mirror built with reposync and createrepo has regenerated, unsigned
      # metadata, so only package signatures (Tyk's key, imported above) are
      # checked there. packagecloud itself also signs its metadata.
      local metacheck="repo_gpgcheck=1
gpgkey=${base}/gpgkey"
      [[ "$MIRROR" == https://packagecloud.io/tyk ]] || metacheck="repo_gpgcheck=0"
      write_file "/etc/yum.repos.d/tyk_${repo}.repo" 0644 <<EOF
[tyk_${repo}]
name=tyk_${repo}
baseurl=${base}/${OSNAME}/${DIST}/\$basearch
enabled=1
gpgcheck=1
${metacheck}
sslverify=1
metadata_expire=300
EOF
      ;;
    none)
      log "would add ${base}/${OSNAME}/ ${DIST}, pinned to ${base}/gpgkey"
      ;;
  esac
}

# The repository setup itself needs curl and CA certificates (minimal images
# often lack them on apt systems).
if [[ "$PM" == apt ]] && ! command -v curl >/dev/null 2>&1; then
  log "installing curl and ca-certificates"
  run apt-get update -y
  run apt-get install -y curl ca-certificates
fi

resolve_upstream
log "upstream:    ${OSNAME} ${DIST}"
SEEN=" "
for c in "${SELECTED[@]}"; do
  r=$(repo_of "$c")
  case "$SEEN" in *" $r "*) continue ;; esac
  SEEN="$SEEN$r "
  log "tyk/${r}"
  add_repo "$r"
done

# ---------------------------------------------------------------- packages
step "Packages"
installed() {
  case "$PM" in
    apt) dpkg -s "$1" >/dev/null 2>&1 ;;
    yum|dnf) rpm -q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
install_pkg() {
  local pkg=$1 spec=$1
  if installed "$pkg"; then
    log "$pkg already installed - skipping"
    return 0
  fi
  case "$PM" in
    apt)
      [[ -n "$VERSION" ]] && spec="${pkg}=${VERSION}"
      run apt-get update -y
      # Attempt the install and explain a failure, rather than pre-checking the
      # apt cache: a pre-check races the index refresh and reports false gaps.
      if ! run apt-get install -y "$spec"; then
        printf '\n%s could not be installed from the Tyk repository.\n' "$pkg" >&2
        printf 'The usual cause is that your distribution codename (%s) has no\n' \
          "$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-unknown}")" >&2
        printf 'published build - packagecloud 404s and apt reports a missing Release file.\n' >&2
        printf 'Re-run pinning a supported one, e.g.:\n  sudo ./install.sh --components %s --os ubuntu --dist noble\n' \
          "$COMPONENTS" >&2
        return 1
      fi
      ;;
    yum|dnf)
      [[ -n "$VERSION" ]] && spec="${pkg}-${VERSION}"
      run "$PM" install -y "$spec"
      ;;
    none) log "would install $spec" ;;
  esac
}
for c in "${SELECTED[@]}"; do install_pkg "$(pkg_of "$c")"; done

# ---------------------------------------------------------------- config
# The packaged units already read /etc/default/<name>, so that is where config
# goes -- no drop-in needed for settings.
#
# IMPORTANT: systemd's EnvironmentFile does NOT strip trailing comments. It takes
# everything after '=' literally, so `TYK_GW_HTTPSERVEROPTIONS_USESSL=false # PROD: ...`
# reaches Tyk as the string "false # PROD: ..." and the gateway exits with
# "strconv.ParseBool: invalid syntax". Docker Compose's env_file parser does strip
# them, which is why ../docker/*/confs works unchanged and this does not.
#
# So the annotated file in confs/ stays the human- and profiles.py-readable
# source, and what gets installed is a sanitised copy with comments removed.
strip_comments() {
  # KEY=value, dropping a whitespace-preceded trailing comment and any whole-line
  # comment. The '#' must be preceded by whitespace but may be followed by
  # anything: `=true #SSO related...` is a real line in confs/dashboard.env, and
  # requiring a space after the '#' silently let it through.
  sed -e 's/[[:space:]][[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
      -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$1"
}

# The confs mirror the Docker ones, which use ${VAR} for licences because Docker
# Compose's env_file expands them. systemd's EnvironmentFile does NOT: it would
# pass the literal string "${TYK_LICENSE_KEY}" to the Dashboard, which then
# reports an invalid licence. Expand here instead, from the environment loaded by
# --env-file, so the value never has to be written into a tracked confs/ file.
expand_vars() {
  # NOTE: the program is passed with -c, NOT via a heredoc. `python3 - <<EOF`
  # consumes stdin as the program, so the piped config never arrives and the
  # rendered file comes out EMPTY -- worse than the literal ${VAR} it replaced.
  python3 -c 'import os, re, sys
missing = set()
def repl(m):
    name = m.group(1)
    val = os.environ.get(name)
    if not val:
        missing.add(name)
        return m.group(0)
    return val
sys.stdout.write(re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", repl, sys.stdin.read()))
if missing:
    sys.stderr.write("UNEXPANDED:" + ",".join(sorted(missing)) + "\n")
'
}

step "Configuration"
for c in "${SELECTED[@]}"; do
  svc=$(svc_of "$c")
  if [[ -z "$svc" ]]; then
    log "$c: command-line tool, no service to configure ($(conf_of "$c")/$(pkg_of "$c"))"
    continue
  fi
  src="$SCRIPT_DIR/confs/$(env_of "$c")"
  dst="/etc/default/${svc}"

  [[ -f "$src" ]] || { printf 'missing %s\n' "$src" >&2; exit 1; }

  # Any '#' left in a value after sanitising reaches Tyk literally and, for a
  # boolean, is a guaranteed startup crash. Refuse rather than install it.
  if strip_comments "$src" | grep -qE '=[^#]*#'; then
    printf '\n%s still contains a value with an inline comment after sanitising:\n' \
      "$(env_of "$c")" >&2
    strip_comments "$src" | grep -nE '=[^#]*#' | sed 's/^/  /' >&2
    printf 'systemd passes this through literally and Tyk will fail to parse it.\n' >&2
    printf 'Fix the line in %s, or quote the value if the # is intentional.\n' "$src" >&2
    exit 1
  fi

  log "$src -> $dst (comments stripped, \${VAR} expanded)"
  if [[ "$DRY_RUN" == true ]]; then
    printf '  would write %s (%s settings)\n' "$dst" "$(strip_comments "$src" | grep -c '=' || true)"
    if strip_comments "$src" | grep -q '\${'; then
      printf '  would expand: %s\n' \
        "$(strip_comments "$src" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' | sort -u | tr '\n' ' ')"
    fi
  else
    umask 027
    if ! strip_comments "$src" | expand_vars > "$dst" 2>"$dst.err"; then
      printf 'failed rendering %s\n' "$dst" >&2; rm -f "$dst.err"; exit 1
    fi
    if [[ -s "$dst.err" ]]; then
      # A licence left unexpanded means the component will not start. Fail loudly
      # rather than installing a file containing a literal ${VAR}.
      printf '\n%s references variables that are not set:\n  %s\n' "$(env_of "$c")" \
        "$(sed 's/^UNEXPANDED://' "$dst.err")" >&2
      printf 'Supply them with --env-file, or export them, then re-run. Never put a licence\n' >&2
      printf 'into %s: .gitignore un-ignores confs/*.env, so it would be tracked.\n' "$src" >&2
      rm -f "$dst" "$dst.err"; exit 1
    fi
    rm -f "$dst.err"
    chmod 0640 "$dst"
  fi

  # confs/gateway.env mirrors the self-managed Docker config, which expects a
  # Dashboard. Installing the gateway WITHOUT the dashboard leaves it pointing at
  # a Dashboard that does not exist: /hello reports "warn" with dashboard "fail"
  # and no APIs ever load. Switch such a gateway to file-based config, which is
  # how the OSS gateway works.
  if [[ "$c" == gateway ]] && ! printf '%s\n' "${SELECTED[@]}" | grep -qx dashboard; then
    log "no dashboard selected -> configuring the gateway for file-based APIs"
    if [[ "$DRY_RUN" != true ]]; then
      run install -d -m 0755 "$(conf_of gateway)/apps" "$(conf_of gateway)/policies"
      [[ -f "$(conf_of gateway)/policies/policies.json" ]] || echo '{}' > "$(conf_of gateway)/policies/policies.json"
      cat >> "$dst" <<EOF
# --- appended by install.sh: gateway installed without a dashboard ---
TYK_GW_USEDBAPPCONFIGS=false
TYK_GW_POLICIES_POLICYSOURCE=file
TYK_GW_POLICIES_POLICYRECORDNAME=$(conf_of gateway)/policies/policies.json
TYK_GW_APPPATH=$(conf_of gateway)/apps
EOF
    fi
  fi

  # The drop-in now carries only hardening, not configuration.
  dropin="/etc/systemd/system/${svc}.service.d/override.conf"
  log "drop-in $dropin (hardening only)"
  run install -d -m 0755 "$(dirname "$dropin")"
  if [[ "$DRY_RUN" != true ]]; then
    cat > "$dropin" <<'EOF'
# Managed by tyk-install baremetal/install.sh. Re-running rewrites this file.
# Configuration lives in /etc/default/<service>, which the packaged unit
# already reads. This file is for hardening only.
[Service]
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
EOF
  fi
done

step "Services"
run systemctl daemon-reload
for c in "${SELECTED[@]}"; do
  svc=$(svc_of "$c")
  [[ -n "$svc" ]] || continue
  run systemctl enable "$svc"
  run systemctl restart "$svc"
  # Never assert a state change that a dry run did not make -- this line gets
  # copied into reports as evidence.
  if [[ "$DRY_RUN" == true ]]; then
    log "$svc would be enabled and restarted"
  else
    log "$svc enabled and restarted"
  fi
done

step "Next"
if [[ "$DRY_RUN" == true ]]; then
  log "dry run only - nothing was changed"
else
  log "verify with: $SCRIPT_DIR/verify.sh --components $COMPONENTS"
  log "logs with:   journalctl -u <service> -f"
fi
log "config dirs: /opt/<package> per component, e.g. $(conf_of "${SELECTED[0]}")"
log "docs:        https://tyk.io/docs/tyk-self-managed/install/linux"
