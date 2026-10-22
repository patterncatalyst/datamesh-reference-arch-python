# notification-service

A §17 final project data product. Owns the `notifications` Postgres schema
(per-service ownership, CAP-003).

**r22 scope (skeleton):** the service starts, ensures its schema exists, and
serves health probes:

- `GET /health` — liveness (process up)
- `GET /healthz` — readiness (Postgres reachable)

Its domain surface is added in later iterations (REST/gRPC/GraphQL/Kafka as
appropriate to the service).

## Build + deploy

```bash
# from examples/lgtm-datamesh/
./scripts/build-image.sh services/notification-service notification-service v1
helm upgrade --install notification-service charts/datamesh/charts/notification-service -n datamesh
kubectl rollout status deployment/notification-service -n datamesh --timeout=120s
```

Or run the health smoke test, which does all of the above and asserts the
probes: `./demos/demo-service.sh notification`
