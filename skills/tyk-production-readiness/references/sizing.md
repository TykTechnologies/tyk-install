# Sizing

There is no universal answer, and this file deliberately does not invent one. What follows is how
to reason about it and what to measure. If someone needs a number, the honest answer is to run the
measurement, not to quote a table.

## What drives Gateway cost

In rough order of impact:

1. **Requests per second.** The baseline.
2. **Middleware per request.** Auth, transforms, validation, and rate limiting each add work.
   A keyless passthrough and a JWT-validated, body-transformed, quota-counted route differ by
   more than an order of magnitude.
3. **Detailed analytics recording.** Stores full bodies. Significant CPU and very significant
   storage.
4. **JavaScript middleware.** The JSVM is single-threaded per Gateway; heavy JS becomes the
   bottleneck. `TYK_GW_ENABLEJSVM=false` when unused.
5. **Response body size.** Large payloads are memory and network, not CPU.

Gateways are stateless, so scale horizontally. Prefer more small Gateways over fewer large ones:
it gives better failure granularity and rolling upgrades.

## Measuring rather than guessing

```bash
# Establish a baseline on one Gateway with the real API and real middleware
# then measure again with the middleware chain the requirement actually needs.
```

Measure with the actual API definition, the actual auth method, and representative payload sizes.
A benchmark against a keyless mock tells you almost nothing about a JWT-validated route with a
body transform.

Watch, per Gateway: CPU, memory, p99 latency added by Tyk (not total latency), Redis connection
pool saturation, and Pump lag. Scale on the one that saturates first — usually CPU, or the Redis
pool if `MAXACTIVE` is too low.

## Redis

Redis is the component people under-provision.

- Sizing is driven by *key count and TTL*, not request rate: keys, quotas, rate-limit counters,
  and OAuth tokens, each with a lifetime.
- `TYK_GW_STORAGE_MAXACTIVE` and `MAXIDLE` cap the connection pool per Gateway. Too low and
  requests queue on connection acquisition, which presents as latency with idle CPU — a
  characteristic and easily misdiagnosed symptom.
- A separate analytics Redis matters more than a bigger single one, because analytics writes stop
  competing with the request path.
- Redis Cluster for availability. Rate limiting stays correct across a cluster.

## PostgreSQL

Sized by *configuration volume and analytics retention*, not request rate:

- API definitions, policies, and users are small and change rarely.
- Analytics, if Pump writes to Postgres, dominates. Retention policy is the main lever; without
  one the database grows without bound.
- Consider a separate analytics database from the configuration database, so an analytics
  problem cannot take the Dashboard down.

## Distributed rate limiting

`DRLTHRESHOLD=-1` and a higher `DRLNOTIFICATIONFREQUENCY` make distributed rate limits more
accurate at the cost of more Redis chatter. Accuracy and Redis load trade directly against each
other — pick deliberately based on whether the limit is a billing boundary or a safety valve.

## Kubernetes resources

Always set requests and limits. Without requests the scheduler cannot place pods sensibly; without
limits one Gateway can starve its neighbours.

Derive the numbers from your own measurement above, then leave headroom for the p99 rather than
the mean. Set them in an overlay, never by editing the tracked values file:

```yaml
tyk-gateway:
  gateway:
    resources:
      requests: { cpu: "", memory: "" }   # from measurement
      limits:   { cpu: "", memory: "" }
```

Use a HorizontalPodAutoscaler on the Gateway once a baseline exists. Autoscaling before you have a
baseline just makes the behaviour harder to reason about.

## Reference

- <https://tyk.io/docs/planning-for-production>
- <https://tyk.io/docs/api-management/rate-limit>
- <https://tyk.io/docs/tyk-pump>
