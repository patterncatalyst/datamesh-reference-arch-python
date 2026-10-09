# Plan: minikube capstone on Docker Engine + containerd/runc (podman only in the CRC appendix)

Planned 2026-10-08 (Opus). Move to `_plans/archive/` once executed.

## Decisions

- **Profile.** `minikube start -p capstone --ports=<loopback pairs> --memory=$MINIKUBE_MEMORY(24g) --cpus=$MINIKUBE_CPUS(16)
  --disk-size=$MINIKUBE_DISK(80g) --driver=docker --container-runtime=containerd --addons=metrics-server`.
  - No rootless, no CRI-O, no registry or rancher addons, and no local-path default.
  - The pre-flight rejects `minikube config get rootless == true`, `MINIKUBE_ROOTLESS`, and rootless Docker. It also rejects a profile created with another driver or runtime.
- **Engine.** Docker Engine is required: native docker-ce on Linux. A VM-based engine (Docker Desktop) is an option, never a requirement.
  - `docker_engine_ok` pre-flight with a hint.
  - The capacity check compares `docker info` NCPU and MemTotal with the overrides.
  - On VM engines the inotify check runs inside the node instead of on the host.
- **Host access unchanged (DRA-017).** Only the inspection backend moves: `podman container inspect` becomes `docker container inspect`.
- **`ensure_node_forwarding` kept as a guard** (`docker exec`, runtime-neutral comment). Record whether it fires.
- **Image pipeline.** No registry: `docker build -f Containerfile` and then `minikube -p capstone image load`.
  - Names are `capstone/<svc>:v1` with `imagePullPolicy: Never`.
  - `build-image.sh` restarts every Deployment referencing the image.
  - New `demos/lib/images.sh` provides `image_ref`, `image_in_profile`, `docker_engine_ok`, `chart_repo_ok` and `CAPSTONE_SERVICES`.
  - `registry_host_port` and all `localhost:5000` usages are removed.
  - Fallback if a load reports "image not found": `docker image save` to a tar, then `image load` from the tar.
- **Podman stays only in the CRC appendix** (`_docs/11`, `openshift/`, `build-and-push.sh`, diagram 19), with explicit scope notes.
- **Decision records.** DRA-018 is marked superseded. New DRA-019 records the docker+containerd decision, the image pipeline, the rejected alternatives, and local-path as the fallback if CNPG hits `initdb: Permission denied`.
- **LESSONS.** Rootless-era lessons move under "Historical: the rootless-podman era (superseded by DRA-019)". Two new lessons are added: a loopback registry push works only on a native engine, and local images use `pullPolicy: Never` with a restart on rebuild.
- **CI.** New scan 5 in `forbidden-syntax.sh` checks podman, rootless, cri-o, crun, `MINIKUBE_ROOTLESS` and `localhost:5000`.
  - Excluded: the CRC appendix allowlist (openshift/, _docs/11, decisions.md, reconciliation.md, openshift-crc-appendix-plan.md) and lines marked `forbidden-ok`.

## Waves (file-disjoint within each wave)

0. `demos/lib/endpoints.sh` (docker inspect, `profile_container_exists/running`, drop `registry_host_port`) and the new `demos/lib/images.sh`.
1. Scripts, charts and demos:
   - A. `setup-capstone-profile.sh`.
   - B. `build-image.sh`.
   - C. `cluster-up`, `cluster-status`, `bootstrap-capstone`, `setup-kafka-operator`.
   - D. `show-endpoints`.
   - E. The 7 chart values files, `istio/order-service-v2.yaml`, `scaffold-service.sh`.
   - F. The demos (`chart_repo_ok`; "Building + loading"; drop `MINIKUBE_ROOTLESS`; diagnostics via `minikube image ls`).
   - G. `config.py` docstrings and `order-service/README.md` (`docker run`).
   - H. `audit-fedora-prereqs.sh`, `lib/_helpers.sh`, `test-template.sh`, `editorial-audit.sh`, `setup-istio.sh`.
2. Docs:
   - I. `setup.html`, `index.html`, `README.md`, `PRD.md`.
   - J. `GETTING-STARTED.md`, `LESSONS-LEARNED.md`.
   - K. `_docs/02`, `_docs/03`, `_docs/06`, `_docs/11` (scope note only).
   - L. `EX/README.md`, the `openshift/` README and `build-and-push.sh` comments.
   - M. `decisions.md` (DRA-019, DRA-018 superseded, DRA-017 wording).
   - N. `03-minikube-topology` svg and excalidraw text.
3. Gate: `forbidden-syntax.sh` scan 5, then fix every remaining hit.
4. Live run, then the verified-state docs (reconciliation row, PRD/README "verified", whether the FORWARD guard fired).

## Acceptance (summary)

**Static**
- The runtime-term grep outside the allowlist returns 0.
- 0 hits each for `MINIKUBE_ROOTLESS`, `--rootless`, `registry_host_port`, `storage-provisioner-rancher`, `cri-o`, `localhost:5000` and `podman ` in the minikube scripts and demos.
- All 7 charts use `capstone/` with `pullPolicy: Never`.
- `endpoints.sh` uses `docker container inspect`.
- The CRC appendix still uses podman.
- forbidden-syntax and cross-reference checks pass; `bash -n` passes.

**Live**
- Start flags: docker driver and containerd, no rootless.
- The node runtime is `containerd://`, using runc.
- `docker port capstone` shows the 14 loopback pairs and nothing on 0.0.0.0.
- 6 `capstone/*:v1` images are in the profile, there are no pull errors, and the images survive stop/start.
- Bootstrap is green through all 10 tiers on the `standard` StorageClass.
- `show-endpoints` and `cluster-status` are green.
- The demo set and the walkthrough pass 5/5.
- A rebuild triggers a restart and the `imageID` changes.
- The FORWARD policy is ACCEPT.

## Live procedure

- **Isolation:** CRC stopped and no other profiles running.
- **Engine:** the docker context points at a running engine.
  - On native Docker Engine, run with the defaults (16 CPUs, 24g).
  - On Docker Desktop, size the VM to at least 28 GB, or set `MINIKUBE_CPUS` to the VM's CPU count.
- **Run:** `bootstrap-capstone.sh`, the acceptance checks, the demos, the walkthrough, and stop/start resilience.
- **Afterwards:** stop the profile and return the engine to its idle state.

## Risks

- `image load` with Docker 29's containerd image store; use the tar fallback.
- A stale `:v1` image; run `image rm` before loading.
- FORWARD DROP; the guard covers it.
- CNPG on `standard`; local-path is the fallback.
- `--disk-size` is ignored by the docker driver on Linux (data lives under the engine's data root).
- VM engines need the overrides.
- Membership in the docker group is root-equivalent; say so.
- Deferred "verified" wording must not merge before the live run passes.
