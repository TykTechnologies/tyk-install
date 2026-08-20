#!/usr/bin/env bash
# Collect executable evidence that a Tyk deployment actually works.
#
# Container status is not evidence: a gateway can be "running" and route nothing.
# The check that matters is the last one -- a request reaching an upstream through
# the gateway and coming back with the upstream's response.
#
#   verify_deployment.sh --edition oss
#   verify_deployment.sh --edition self-managed --route /httpbin/get
#   verify_deployment.sh --edition mdcb-data-plane --gateway http://localhost:8081
#
# On Kubernetes or OpenShift, pass --namespace so component checks use kubectl
# instead of Docker, and point --gateway at a port-forward or Route:
#   kubectl port-forward -n tyk svc/gateway-svc-tyk-tyk-gateway 8080:8080 &
#   verify_deployment.sh --edition self-managed --namespace tyk --route /httpbin/get
#
# Exits non-zero if any required check fails, so it can gate a deployment report.
# Never prints a licence, token, or password.
set -uo pipefail

EDITION=self-managed
GATEWAY=http://localhost:8080
DASHBOARD=http://localhost:3000
PORTAL=http://localhost:3001
ROUTE=
STACK=
NAMESPACE=
KCTX=
TIMEOUT=90

usage() {
  cat <<'EOF'
Usage: verify_deployment.sh --edition <name> [options]

  --edition    oss | self-managed | hybrid | mdcb-control-plane | mdcb-data-plane | ai-studio
  --gateway    Gateway base URL          (default http://localhost:8080)
  --dashboard  Dashboard base URL        (default http://localhost:3000)
  --portal     Developer Portal base URL (default http://localhost:3001)
  --route      Path to prove proxying, e.g. /httpbin/get. Required for real evidence.
  --stack      Only inspect containers whose name contains this string. Use it when
               more than one Tyk stack runs on the host, e.g. --stack cp or --stack dp.
  --namespace  Kubernetes namespace. Switches component checks from Docker to kubectl,
               so this works on a cluster and on OpenShift. Without it, Docker is used.
  --context    kubectl context to use with --namespace (default: current context).
  --timeout    Seconds to wait for components to come up (default 90)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --edition)   EDITION=${2:?}; shift 2 ;;
    --gateway)   GATEWAY=${2:?}; shift 2 ;;
    --dashboard) DASHBOARD=${2:?}; shift 2 ;;
    --portal)    PORTAL=${2:?}; shift 2 ;;
    --route)     ROUTE=${2:?}; shift 2 ;;
    --stack)     STACK=${2:?}; shift 2 ;;
    --namespace) NAMESPACE=${2:?}; shift 2 ;;
    --context)   KCTX=${2:?}; shift 2 ;;
    --timeout)   TIMEOUT=${2:?}; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

PASS=0; FAIL=0; SKIP=0
pass() { printf '  ok    %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '  --    %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; SKIP=$((SKIP+1)); }

have() { command -v "$1" >/dev/null 2>&1; }

# Kubernetes mode is selected by --namespace. Without it nothing changes and Docker
# is used, so existing invocations behave exactly as before.
on_kube() { [[ -n "$NAMESPACE" ]]; }
kc() { kubectl ${KCTX:+--context "$KCTX"} -n "$NAMESPACE" "$@"; }

# Name of a running pod whose name matches a role, or empty.
pod_for() {
  local role=$1
  kc get pods -o name 2>/dev/null | sed 's|^pod/||' | grep -E "$role" | head -1
}

# Run a command inside the workload matching a role, on either platform.
in_component() {
  local role=$1; shift
  if on_kube; then
    local pod; pod=$(pod_for "$role")
    [[ -z "$pod" ]] && return 127
    kc exec "$pod" -- "$@" 2>/dev/null
  else
    local name; name=$(container_for "$role")
    [[ -z "$name" ]] && return 127
    docker exec "$name" "$@" 2>/dev/null
  fi
}

# Logs of the workload matching a role, on either platform.
logs_of() {
  local role=$1
  if on_kube; then
    local pod; pod=$(pod_for "$role")
    [[ -z "$pod" ]] && return 127
    kc logs "$pod" --tail=400 2>&1
  else
    local name; name=$(container_for "$role")
    [[ -z "$name" ]] && return 127
    docker logs "$name" 2>&1 | tail -400
  fi
}

# Human label for whatever is serving a role, for the report.
where_component() {
  if on_kube; then printf 'pod %s' "$(pod_for "$1")"; else printf '%s' "$(container_for "$1")"; fi
}

component_present() {
  if on_kube; then [[ -n "$(pod_for "$1")" ]]; else [[ -n "$(container_for "$1")" ]]; fi
}

runtime_available() {
  if on_kube; then have kubectl; else have docker; fi
}

# Pick a running container by role, restricted to --stack when given so a second
# Tyk stack on the same host is never mistaken for this one.
container_for() {
  local role=$1
  docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -E "$role" \
    | { if [[ -n "$STACK" ]]; then grep -- "$STACK"; else cat; fi; } \
    | head -1
}
have curl || { echo "curl is required" >&2; exit 2; }

# Wait until a URL returns 200, up to --timeout.
wait_200() {
  local url=$1 deadline=$((SECONDS + TIMEOUT))
  while (( SECONDS < deadline )); do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)" == "200" ]] && return 0
    sleep 2
  done
  return 1
}

status_of() { curl -s -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }

# ---------------------------------------------------------------- gateway health
check_gateway() {
  if ! wait_200 "$GATEWAY/hello"; then
    fail "gateway $GATEWAY/hello" "returned $(status_of "$GATEWAY/hello") after ${TIMEOUT}s"
    return 1
  fi
  local body; body=$(curl -s "$GATEWAY/hello")
  local overall; overall=$(printf '%s' "$body" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [[ "$overall" == "pass" ]]; then
    local version; version=$(printf '%s' "$body" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    pass "gateway healthy (Tyk ${version:-unknown})"
  else
    fail "gateway health status is '${overall:-unreadable}'" "$body"
    return 1
  fi

  # Component-level detail, when this edition reports it.
  if have jq; then
    local redis dash
    redis=$(printf '%s' "$body" | jq -r '.details.redis.status // empty' 2>/dev/null)
    dash=$(printf '%s' "$body" | jq -r '.details.dashboard.status // empty' 2>/dev/null)
    [[ -n "$redis" ]] && { [[ "$redis" == "pass" ]] && pass "gateway -> redis" || fail "gateway -> redis is '$redis'"; }
    [[ -n "$dash"  ]] && { [[ "$dash"  == "pass" ]] && pass "gateway -> dashboard" || fail "gateway -> dashboard is '$dash'"; }
  else
    skip "gateway component detail" "install jq to break /hello down per component"
  fi
}

# -------------------------------------------------------------- dashboard health
check_dashboard() {
  if ! wait_200 "$DASHBOARD/hello"; then
    fail "dashboard $DASHBOARD/hello" "returned $(status_of "$DASHBOARD/hello") after ${TIMEOUT}s"
    return 1
  fi
  pass "dashboard healthy"
  # A licence problem shows up in the logs rather than /hello.
  if runtime_available && component_present 'dashboard'; then
    if logs_of 'dashboard' | grep -qiE 'license.*(invalid|expired)|no license'; then
      fail "dashboard licence" "licence rejected - check the logs of $(where_component 'dashboard')"
    else
      pass "dashboard licence accepted"
    fi
  else
    skip "dashboard licence" "no dashboard workload to read logs from"
  fi
}

# ------------------------------------------------------------------ the real one
check_proxy() {
  if [[ -z "$ROUTE" ]]; then
    skip "proxied request" "pass --route <path> to prove a request reaches an upstream"
    return
  fi
  local code; code=$(status_of "$GATEWAY$ROUTE")
  if [[ "$code" == "200" ]]; then
    pass "proxied request $ROUTE -> HTTP 200 from upstream"
    printf '        %s\n' "$(curl -s "$GATEWAY$ROUTE" | head -c 200 | tr '\n' ' ')"
  else
    fail "proxied request $ROUTE" "HTTP $code - the gateway is up but not serving this route"
  fi
  # An undefined route must 404, proving the gateway is routing rather than
  # blanket-forwarding everything it receives.
  local miss; miss=$(status_of "$GATEWAY/__verify_no_such_route__/")
  if [[ "$miss" == "404" ]]; then
    pass "undefined route returns 404"
  else
    fail "undefined route returned HTTP $miss" "expected 404"
  fi
}

check_redis() {
  runtime_available || { skip "redis" "no docker or kubectl available"; return; }
  component_present 'redis' || { skip "redis" "no redis workload found"; return; }
  if [[ "$(in_component 'redis' redis-cli ping)" == "PONG" ]]; then
    pass "redis responding ($(where_component 'redis'))"
  else
    fail "redis not responding ($(where_component 'redis'))"
  fi
}

check_postgres() {
  runtime_available || { skip "postgres" "no docker or kubectl available"; return; }
  component_present 'postgres' || { skip "postgres" "no postgres workload found"; return; }
  if in_component 'postgres' pg_isready >/dev/null 2>&1; then
    pass "postgres accepting connections ($(where_component 'postgres'))"
  else
    fail "postgres not ready ($(where_component 'postgres'))"
  fi
}

check_portal() {
  local code; code=$(status_of "$PORTAL/ready")
  if [[ "$code" == "200" ]]; then pass "developer portal ready"
  else skip "developer portal" "HTTP $code at $PORTAL/ready - not deployed, or still starting"; fi
}

check_rpc() {
  runtime_available || { skip "mdcb rpc" "no docker or kubectl available"; return; }
  component_present 'gateway' || { skip "mdcb rpc" "no gateway workload found"; return; }
  local logs; logs=$(logs_of 'gateway')
  # A logged-in data plane writes RPC backups and reports a definition count.
  # "RPC Login incorrect" is the credential/org failure; note it is also what a
  # gateway reports when MDCB itself cannot read tyk_organisations.
  if printf '%s' "$logs" | grep -qiE 'Storing RPC (policies|Definitions) backup|Detected [0-9]+ APIs'; then
    pass "data plane logged in to MDCB over RPC"
  elif printf '%s' "$logs" | grep -qi 'RPC Login incorrect'; then
    fail "MDCB RPC login rejected" \
         "check org id / api key / group id, that the org is hybrid_enabled, and that MDCB points at the Dashboard's MAIN database"
  elif printf '%s' "$logs" | grep -qiE 'rpc.*(connection refused|dial|no such host)'; then
    fail "cannot reach MDCB" "check the connection string and that the control plane is up"
  else
    skip "mdcb rpc" "no RPC status in gateway logs yet"
  fi
}

printf 'verifying: %s\n' "$EDITION"
case "$EDITION" in
  oss)                check_gateway; check_redis; check_proxy ;;
  self-managed)       check_gateway; check_dashboard; check_redis; check_postgres; check_portal; check_proxy ;;
  hybrid)             check_gateway; check_redis; check_rpc; check_proxy ;;
  mdcb-control-plane) check_gateway; check_dashboard; check_redis; check_postgres ;;
  mdcb-data-plane)    check_gateway; check_redis; check_rpc; check_proxy ;;
  ai-studio)          check_postgres; check_proxy ;;
  *) printf 'Unknown edition: %s\n' "$EDITION" >&2; usage >&2; exit 2 ;;
esac

printf '\n%d passed, %d failed, %d not applicable\n' "$PASS" "$FAIL" "$SKIP"
if (( FAIL > 0 )); then
  printf 'Deployment is NOT verified. See tyk-deployment-runner/references/debugging.md\n'
  exit 1
fi
if [[ -z "$ROUTE" ]]; then
  printf 'Components are healthy, but no request was proxied. Re-run with --route to\n'
  printf 'prove end-to-end traffic before reporting this deployment as working.\n'
  exit 0
fi
printf 'Verified end to end.\n'
