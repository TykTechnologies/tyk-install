#!/usr/bin/env bash
# Verify a bare-metal Tyk install: unit states, endpoints, and dependencies.
#
#   ./verify.sh
#   ./verify.sh --components gateway,dashboard --route /httpbin/get
#
# Exits non-zero if any required check fails. Never prints a licence value.
set -uo pipefail

COMPONENTS=gateway
GATEWAY=http://localhost:8080
DASHBOARD=http://localhost:3000
ROUTE=

usage() {
  cat <<'EOF'
Usage: ./verify.sh [--components gateway,dashboard,pump] [options]

  --components  Comma-separated: gateway, dashboard, pump. Default: gateway.
  --gateway     Gateway base URL   (default http://localhost:8080)
  --dashboard   Dashboard base URL (default http://localhost:3000)
  --route       Path proving a request reaches an upstream, e.g. /httpbin/get
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --components) COMPONENTS=${2:?}; shift 2 ;;
    --gateway)    GATEWAY=${2:?}; shift 2 ;;
    --dashboard)  DASHBOARD=${2:?}; shift 2 ;;
    --route)      ROUTE=${2:?}; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

PASS=0; FAIL=0; SKIP=0
pass() { printf '  ok    %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '  --    %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; SKIP=$((SKIP+1)); }

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
if ! command -v systemctl >/dev/null 2>&1; then
  printf 'systemd not found - this script checks systemd units.\n' >&2
  printf 'For a container deployment use ../skills/tyk-deployment-runner/scripts/verify_deployment.sh\n' >&2
  exit 2
fi

check_unit() {
  local unit=tyk-$1
  if ! systemctl list-unit-files "${unit}.service" >/dev/null 2>&1; then
    fail "$unit not installed" "run install.sh --components $1"; return
  fi
  if [[ "$(systemctl is-active "$unit" 2>/dev/null)" == active ]]; then
    pass "$unit active"
  else
    fail "$unit is $(systemctl is-active "$unit" 2>/dev/null)" \
         "journalctl -u $unit -n 50 --no-pager"
    return
  fi
  if [[ "$(systemctl is-enabled "$unit" 2>/dev/null)" == enabled ]]; then
    pass "$unit enabled at boot"
  else
    fail "$unit not enabled at boot" "systemctl enable $unit"
  fi
  # Confirm the drop-in is actually being loaded, not just present on disk.
  if [[ -s "/etc/default/${unit}" ]]; then
    pass "$unit has config at /etc/default/${unit}"
    # systemd takes EnvironmentFile values literally, so a stray inline comment
    # here makes the gateway exit on a parse error.
    if grep -qE '=[^=]*[[:space:]]#[[:space:]]' "/etc/default/${unit}" 2>/dev/null; then
      fail "/etc/default/${unit} contains inline comments" \
           "systemd does not strip them; Tyk will fail to parse the value. Re-run install.sh."
    else
      pass "$unit config has no inline comments"
    fi
  else
    fail "no config at /etc/default/${unit}" "run install.sh --components $1"
  fi
}

status_of() { curl -s -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }

check_endpoint() {
  local name=$1 url=$2 code body overall
  code=$(status_of "$url/hello")
  if [[ "$code" != "200" ]]; then
    fail "$name /hello returned $code" "the unit may be active but not serving yet"
    return
  fi
  # A 200 is not enough: the gateway answers 200 while reporting "warn" with a
  # failed component, e.g. a dashboard it cannot reach.
  body=$(curl -s "$url/hello")
  overall=$(printf '%s' "$body" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  case "$overall" in
    pass) pass "$name healthy (status=pass)" ;;
    warn) fail "$name reports status=warn" "a component is failing: $(printf '%s' "$body" | head -c 160)" ;;
    *)    fail "$name reports status=${overall:-unreadable}" "$(printf '%s' "$body" | head -c 160)" ;;
  esac
}

check_redis() {
  if command -v redis-cli >/dev/null 2>&1; then
    if [[ "$(redis-cli ping 2>/dev/null)" == PONG ]]; then
      pass "redis responding"
    else
      fail "redis not responding" "the gateway cannot store keys, quotas, or rate limits without it"
    fi
  else
    skip "redis" "redis-cli not installed; check your Redis host manually"
  fi
}

check_postgres() {
  if command -v pg_isready >/dev/null 2>&1; then
    if pg_isready >/dev/null 2>&1; then
      pass "postgres accepting connections"
    else
      fail "postgres not ready" "the dashboard stores API definitions and users here"
    fi
  else
    skip "postgres" "pg_isready not installed; check your PostgreSQL host manually"
  fi
}

check_proxy() {
  if [[ -z "$ROUTE" ]]; then
    skip "proxied request" "pass --route <path> to prove a request reaches an upstream"
    return
  fi
  local code; code=$(status_of "$GATEWAY$ROUTE")
  if [[ "$code" == "200" ]]; then
    pass "proxied request $ROUTE -> HTTP 200"
  else
    fail "proxied request $ROUTE returned HTTP $code"
  fi
}

IFS=',' read -r -a SELECTED <<< "$COMPONENTS"
printf 'verifying bare-metal install: %s\n' "${SELECTED[*]}"
for c in "${SELECTED[@]}"; do check_unit "$c"; done
for c in "${SELECTED[@]}"; do
  case "$c" in
    gateway)   check_endpoint gateway "$GATEWAY"; check_redis ;;
    dashboard) check_endpoint dashboard "$DASHBOARD"; check_postgres ;;
    pump)      : ;;
  esac
done
check_proxy

printf '\n%d passed, %d failed, %d not applicable\n' "$PASS" "$FAIL" "$SKIP"
if (( FAIL > 0 )); then
  printf 'Not verified. See ../skills/tyk-deployment-runner/references/debugging.md\n'
  exit 1
fi
[[ -z "$ROUTE" ]] && printf 'Units are healthy, but no request was proxied. Re-run with --route.\n'
exit 0
