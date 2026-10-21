#!/usr/bin/env bash
# Static checks on the Grafana dashboards in ../dashboards: valid JSON, a unique UID each,
# datasources taken from variables or the provisioned tyk-* UIDs, and no leftovers from the
# environments they were built in.
# Usage: observability/scripts/check-dashboards.sh   (needs jq)
set -euo pipefail

dir="$(cd "$(dirname "$0")/../dashboards" && pwd)"
fail=0
uids=""

for f in "$dir"/*.json; do
  name="$(basename "$f")"
  if ! jq empty "$f" 2>/dev/null; then
    echo "FAIL $name: invalid JSON"; fail=1; continue
  fi
  # v1 dashboards carry .uid, v2 ones .metadata.name
  uid="$(jq -r '.uid // .metadata.name // empty' "$f")"
  if [ -z "$uid" ]; then
    echo "FAIL $name: no uid"; fail=1
  elif printf '%s\n' "$uids" | grep -qx "$uid"; then
    echo "FAIL $name: duplicate uid $uid"; fail=1
  fi
  uids="$(printf '%s\n%s' "$uids" "$uid")"

  bad_ds="$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid // empty
    | select(test("^(\\$\\{.*\\}|\\$[a-z_]+|-- Grafana --|grafana|__expr__|tyk-(prometheus|tempo|loki|alertmanager))$") | not)] | unique | join(", ")' "$f")"
  if [ -n "$bad_ds" ]; then
    echo "FAIL $name: hardcoded datasource uid(s): $bad_ds"; fail=1
  fi

  leftovers="$(grep -o -E 'webstore-[a-z]+|/grafana/(d|explore)|tyk-demo|demo\.env|localhost:[0-9]+' "$f" | sort -u | tr '\n' ' ' || true)"
  if [ -n "$leftovers" ]; then
    echo "FAIL $name: environment-specific strings: $leftovers"; fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "OK: $(find "$dir" -name '*.json' | wc -l | tr -d ' ') dashboards"
exit "$fail"
