# Debugging

Read this before changing configuration. Most failures here look like each other from the outside,
so identify which one you have before editing anything.

## Order of investigation

1. What does `/hello` say, per component? `curl -s localhost:8080/hello | jq` breaks it down.
   A component reported `fail` there names the problem directly.
2. What do the logs say? `docker compose logs tyk-gateway` or
   `kubectl logs -n tyk deploy/...`. Read the first error, not the last — later errors are usually
   consequences.
3. Is it a config problem or a connectivity problem? If the Gateway starts and reports healthy but
   a route 404s, it is configuration. If the Gateway will not start, it is connectivity or licence.

## Gateway will not start

| Log signal | Cause | Fix |
| --- | --- | --- |
| `Could not connect to redis` | Redis unreachable or wrong address | Check `TYK_GW_STORAGE_ADDRS` resolves *inside* the network. In Compose that is the service name (`tyk-redis:6379`), never `localhost`. |
| `Dashboard connection failed`, retry loop | Dashboard not up yet, or wrong URL | Self-Managed only. Check `TYK_GW_DBAPPCONFOPTIONS_CONNECTIONSTRING`. Expected briefly at startup; a persistent loop is real. |
| `no such file or directory` for apps/ | OSS with no API definitions mounted | Confirm the `./apps` mount and that `TYK_GW_APPPATH` matches the container path. |
| exits immediately, no useful log | malformed env file | A stray quote or trailing space in `confs/*.env` fails silently. `docker compose config` will not catch it; bisect the file. |

## Dashboard will not start

| Log signal | Cause | Fix |
| --- | --- | --- |
| `license is invalid` / `expired` | wrong or stale licence | Check `TYK_LICENSE_KEY` in `.env`. Trials expire — re-issue at https://tyk.io/sign-up/. Never print the value while checking it. |
| `pq: database "tyk_analytics" does not exist` | Postgres init script did not run | The init SQL runs only on an empty volume. `docker compose down -v` and up again, which destroys data — confirm first. |
| `connection refused` to Postgres | Postgres not ready | The Compose healthcheck should prevent this; if it recurs, Postgres is crash-looping — read its own logs. |

## A route returns the wrong thing

| Symptom | Cause |
| --- | --- |
| 404 on a path you defined | `listen_path` mismatch, or the definition never loaded. Grep the Gateway log for `API Loaded` and the API name. In OSS, restart the Gateway after editing a file. |
| 404 on every path | No APIs loaded at all. In OSS check the mount; in Self-Managed check the Gateway reached the Dashboard. |
| 503 with an HTML error body | The upstream is failing, not Tyk. An HTML body from nginx or a cloud LB means Tyk proxied correctly and the upstream answered 503. Test the upstream directly. |
| 502 | Tyk cannot reach the upstream at all. Check `target_url` resolves inside the container network. |
| 401 where you expected none | `use_keyless` is false. Keyless requires it explicitly. |
| Works via port-forward, not via ingress | Ingress or Route problem, not Tyk. |

Distinguishing 502 from 503 matters: 502 is Tyk's own failure to connect, 503 is usually the
upstream's response passed through. Do not reconfigure Tyk for someone else's 503.

## MDCB and hybrid RPC

| Log signal | Cause | Fix |
| --- | --- | --- |
| `rpc: connection refused` | control plane not serving, or wrong host/port | MDCB listens on 9091. Confirm the control plane is up first — ordering matters. |
| `Login failed`, `access denied` | wrong org ID, API key, or group ID | Re-read all three from the control-plane Dashboard. They are separate values; one wrong is enough. |
| `certificate signed by unknown authority` | TLS to MDCB | For development set `TYK_GW_SLAVEOPTIONS_SSLINSECURESKIPVERIFY=true`. Never in production — install the CA instead. |
| connects, then no APIs appear | group ID mismatch, or APIs not tagged for this data plane | Check the API's segment tags against the data plane's group. |

## Kubernetes specifics

```bash
kubectl get events -n tyk --sort-by=.lastTimestamp | tail -20
kubectl describe pod -n tyk <pod>
```

| Symptom | Cause |
| --- | --- |
| `CreateContainerConfigError` | a referenced Secret or key is missing. `kubectl describe` names it. |
| `Pending` forever | no schedulable node, or no default StorageClass for the PVC. |
| `CrashLoopBackOff` | read the previous container's logs: `kubectl logs <pod> --previous`. |
| OpenShift: permission denied on start | SCC. Apply the `openshift` profile overlay — see `runtime.md`. |

## Recovering credentials

Use the APIs, not the database. Direct database access to recover a Dashboard password will
produce an account that behaves oddly later.

`docker/getting-started/` prints its bootstrapped credentials; `utils/bootstrap/` writes them to
its `bootstrap-output/` directory, which is gitignored.

## When you cannot resolve it

Report the actual first error, the component, the edition, and the versions running. Do not report
a deployment as working because the containers are up — say which check failed and what it
returned. `verify_deployment.sh` exits non-zero precisely so this is not glossed over.

## Reference

- https://tyk.io/docs/troubleshooting
- https://tyk.io/docs/api-management/gateway-config-tyk-oas
- https://support.tyk.io/hc/en-gb
