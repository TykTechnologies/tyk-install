#!/usr/bin/env python3
"""Run every Prometheus and Loki query of the Tyk dashboards against a live stack.

Queries go through Grafana's datasource proxy (tyk-prometheus, tyk-loki), so the same check
works on Docker and Kubernetes. Dashboard variables are replaced with match-all values, or the
ones given with --var. Fails on any query error (a broken query, a duplicate-series join, ...);
panels that return nothing are only reported, since they need traffic of that kind.

Usage: observability/scripts/check-panels.py [--grafana URL] [--var name=value ...]
                                              [--show-empty] [dashboard-uid ...]
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

DASHBOARDS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dashboards")

# Values for Grafana's built-in variables; any other variable matches everything.
BUILTINS = {
    "__rate_interval": "2m", "__interval": "1m", "__range": "15m", "__auto": "1m",
    "service_name": "tyk-gateway", "slo_availability_target": "99.9", "slo_latency_ms": "500",
}


def interpolate(expr, values):
    def rep(m):
        name = (m.group(1) or m.group(2)).split(":")[0]
        return values.get(name, ".*")
    return re.sub(r"\$\{([^}]+)\}|\$([A-Za-z_]\w*)", rep, expr)


def queries(dash):
    """(panel title, datasource kind, expr) for v1 and v2 dashboards."""
    found = []

    def walk(o, title=None, ds=None):
        if isinstance(o, dict):
            title = o.get("title", title)
            d = o.get("datasource")
            if isinstance(d, dict):
                ds = d.get("type") or d.get("uid") or d.get("name") or ds
            elif isinstance(d, str):
                ds = d
            if o.get("group") in ("prometheus", "loki", "tempo"):
                ds = o["group"]
            expr = o.get("expr")
            if isinstance(expr, str) and expr.strip():
                loki = "loki" in str(ds).lower() or expr.lstrip().startswith("{") or "_over_time({" in expr
                found.append((title, "loki" if loki else "prometheus", expr))
            for v in o.values():
                walk(v, title, ds)
        elif isinstance(o, list):
            for v in o:
                walk(v, title, ds)

    walk(dash)
    return found


def run(grafana, kind, expr):
    if kind == "loki":
        path = "/api/datasources/proxy/uid/tyk-loki/loki/api/v1/query_range?" + urllib.parse.urlencode(
            {"query": expr, "limit": "5", "since": "15m"})
    else:
        path = "/api/datasources/proxy/uid/tyk-prometheus/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    try:
        r = json.load(urllib.request.urlopen(grafana + path, timeout=30))
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            body = json.loads(body).get("error") or json.loads(body).get("message") or body
        except ValueError:
            pass
        return "error", body.strip()[:160]
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach Grafana at {grafana}: {e.reason}")
    data = r.get("data", {})
    if data.get("resultType") == "streams":
        return "ok", sum(len(s.get("values", [])) for s in data.get("result", []))
    return "ok", len(data.get("result", []))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--grafana", default=os.environ.get("GRAFANA_URL", "http://localhost:3002"))
    p.add_argument("--var", action="append", default=[], help="dashboard variable, e.g. api_id=my-api")
    p.add_argument("--show-empty", action="store_true", help="list the panels that returned nothing")
    p.add_argument("uids", nargs="*", help="dashboards to check (default: all)")
    args = p.parse_args()

    values = dict(BUILTINS)
    for v in args.var:
        k, _, val = v.partition("=")
        values[k] = val

    errors = 0
    for path in sorted(glob.glob(os.path.join(DASHBOARDS, "*.json"))):
        dash = json.load(open(path, encoding="utf-8"))
        uid = dash.get("uid") or dash.get("metadata", {}).get("name") or os.path.basename(path)
        if args.uids and uid not in args.uids:
            continue
        data, empty, failed = 0, [], []
        for title, kind, expr in queries(dash):
            status, n = run(args.grafana.rstrip("/"), kind, interpolate(expr, values))
            if status == "error":
                failed.append(f"{title}: {n}")
            elif n == 0:
                empty.append(title)
            else:
                data += 1
        errors += len(failed)
        print(f"{'FAIL' if failed else 'OK  '} {uid:28s} queries with data={data:3d} empty={len(empty):3d} errors={len(failed)}")
        for f in failed:
            print(f"       error  {f}")
        if args.show_empty:
            for t in sorted(set(empty)):
                print(f"       empty  {t}")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
