# Prefect on OpenShift

## What's here

- `postgres-credentials-secret.yaml` — republishes the `prefect` login
  role's demo password (provisioned server-side by
  `../install-platform.sh`'s `provision_prefect_db`) as a Kubernetes Secret,
  since that script only does the SQL-side provisioning.
- `server-deployment.yaml` / `server-service.yaml` / `server-route.yaml` —
  the Prefect 3.x OSS server, backed by the core datamesh Postgres (a
  separate `prefect` database + dedicated `prefect` role on the same shared
  cluster — see `decisions.md` DRA-013). Server listens on 4200 (API + UI).
- `worker-deployment.yaml` — a `process`-type worker polling the
  `default-pool` work pool, talking to the server over its ClusterIP Service.
- `example-flow-configmap.yaml` — a 2-task flow (`say_hello` → `say_goodbye`)
  used to prove a run actually reaches `Completed`.

## Prerequisite

`../install-platform.sh` must have already run its `provision_prefect_db`
step (database `prefect`, role `prefect`), since `postgres-credentials-secret.yaml`'s
password must match what that step actually created.

## Wiring

```
Deployment flow
  Developer/CI ──POST flow run──▶ prefect-server (Service :4200)
                                        │
                                        ▼  (stores run/task state)
                                   postgres (db=prefect)
                                        ▲
                                        │ polls for scheduled work
                                prefect-worker (process type, pool=default-pool)
                                        │
                                        ▼ runs the flow code as a local subprocess
                                  example-flow ConfigMap mounted at /flows
```

The worker executes flow code that must be present in its own filesystem —
mounting `prefect-example-flow` into the worker (or into a separate one-off
Pod) at `/flows/flow.py` is how the tiny proof-of-life flow gets to the
process that runs it.

## Apply order

```
oc apply -f postgres-credentials-secret.yaml
oc apply -f server-deployment.yaml -f server-service.yaml -f server-route.yaml
oc rollout status deployment/prefect-server -n datamesh
oc apply -f worker-deployment.yaml
oc apply -f example-flow-configmap.yaml
```

## Create the work pool (one-time, server-side state)

```
oc exec -n datamesh deploy/prefect-server -- \
  prefect --no-prompt work-pool create default-pool --type process || true
```

(`|| true` because a pool that already exists errors rather than no-ops —
safe to ignore on re-runs.)

## Verify a flow run reaches Completed

Mount the example flow into a throwaway Pod and run it directly against the
server/worker:

```
oc run prefect-example-runner -n datamesh --rm -it --restart=Never \
  --image=docker.io/prefecthq/prefect:3.8.8-python3.14 \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "prefect-example-runner",
      "image": "docker.io/prefecthq/prefect:3.8.8-python3.14",
      "command": ["python", "/flows/flow.py"],
      "env": [{"name": "PREFECT_API_URL", "value": "http://prefect-server.datamesh.svc:4200/api"}],
      "volumeMounts": [{"name": "flow", "mountPath": "/flows"}]
    }],
    "volumes": [{"name": "flow", "configMap": {"name": "prefect-example-flow"}}]
  }
}' -- true
```

Then confirm the run shows `Completed`:

```
oc exec -n datamesh deploy/prefect-server -- \
  prefect flow-run ls --limit 1
```

or open the UI via the Route (`oc get route prefect-server -n datamesh`) and
check the Flow Runs page.
