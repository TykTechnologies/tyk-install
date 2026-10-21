#!/usr/bin/env bash
# Checks that a running observability stack receives Tyk's telemetry: Gateway metrics in
# Prometheus, the alert rules loaded, the Tyk dashboards and datasources in Grafana, and
# Gateway traces in Tempo and logs in Loki (read through Grafana's datasource proxy).
# Send some traffic through the Gateway first.
#
# Usage: observability/scripts/smoke-test.sh   (needs curl and jq)
#   PROMETHEUS_URL  default http://localhost:9090
#   GRAFANA_URL     default http://localhost:3002 (anonymous access, as shipped)
#   TIMEOUT         seconds to wait for each check, default 180
set -uo pipefail

prom="${PROMETHEUS_URL:-http://localhost:9090}"
grafana="${GRAFANA_URL:-http://localhost:3002}"
timeout="${TIMEOUT:-180}"
fail=0

# check <description> <command printing a number>: passes once the number is above zero.
check() {
  local what="$1" cmd="$2" n=0 waited=0
  while [ "$waited" -lt "$timeout" ]; do
    n="$(eval "$cmd" 2>/dev/null || echo 0)"
    if [ -n "$n" ] && [ "$n" != "null" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      echo "PASS $what ($n)"; return 0
    fi
    sleep 5; waited=$((waited + 5))
  done
  echo "FAIL $what"; fail=1
}

promq() { curl -sf "$prom/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result | length'; }

check "Gateway request metrics" "promq 'http_server_request_duration_seconds_count{service_name=\"tyk-gateway\"}'"
check "Gateway API metrics" "promq 'tyk_api_requests_total{service_name=\"tyk-gateway\"}'"
check "Gateway runtime metrics" "promq 'go_goroutine_count{service_name=\"tyk-gateway\"}'"
check "Gateway loaded APIs" "promq 'tyk_gateway_apis_loaded{service_name=\"tyk-gateway\"}'"
check "Collector scraped" "promq 'up{job=~\"(.+/)?(tyk|otel-collector.*)\"} == 1'"
check "Alert rule groups loaded" "curl -sf '$prom/api/v1/rules' | jq '[.data.groups[] | select(.name | startswith(\"tyk-\")) | select(all(.rules[]; .health == \"ok\"))] | length'"
check "Tyk dashboards in Grafana" "curl -sf '$grafana/api/search?type=dash-db&tag=tyk' | jq length"
for ds in tyk-prometheus tyk-tempo tyk-loki; do
  check "Grafana datasource $ds healthy" "curl -sf '$grafana/api/datasources/uid/$ds/health' | jq '[select(.status == \"OK\")] | length'"
done
check "Gateway traces in Tempo" "curl -sf '$grafana/api/datasources/proxy/uid/tyk-tempo/api/search?tags=service.name%3Dtyk-gateway&limit=20' | jq '.traces | length'"
check "Gateway logs in Loki" "curl -sfG '$grafana/api/datasources/proxy/uid/tyk-loki/loki/api/v1/query_range' --data-urlencode 'query={service_name=\"tyk-gateway\"}' --data-urlencode 'since=1h' --data-urlencode 'limit=20' | jq '[.data.result[].values[]] | length'"
check "Gateway access logs with trace ids" "curl -sfG '$grafana/api/datasources/proxy/uid/tyk-loki/loki/api/v1/query_range' --data-urlencode 'query={service_name=\"tyk-gateway\"} | tyk_prefix=\"access-log\" | tyk_trace_id!=\"\"' --data-urlencode 'since=1h' --data-urlencode 'limit=20' | jq '[.data.result[].values[]] | length'"

exit "$fail"
