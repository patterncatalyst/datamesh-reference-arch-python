#!/usr/bin/env bash
#
# sync-protos.sh — distribute the canonical proto to the gRPC services.
#
# Unlike the Python tree (scripts/gen-protos.sh, which generates and commits
# Python stubs per service — CAP-013), the Quarkus build generates gRPC stubs
# at build time from each service's src/main/proto via quarkus-grpc. So there
# are no committed stubs; this script only keeps each gRPC service's proto copy
# in sync with the canonical definition in proto/ (see DRA-002).
#
# Run it whenever proto/capstone/**/*.proto changes, then rebuild.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANON="${ROOT_DIR}/proto"

# Services that compile gRPC stubs (server or client).
GRPC_SERVICES=(inventory-service order-service graphql-gateway)

step() { printf '\n==> %s\n' "$1"; }

[[ -d "$CANON" ]] || { echo "ERROR: canonical proto dir $CANON not found" >&2; exit 1; }

for svc in "${GRPC_SERVICES[@]}"; do
    dest="${ROOT_DIR}/services/${svc}/src/main/proto"
    step "Syncing proto -> services/${svc}/src/main/proto"
    mkdir -p "$dest"
    # Mirror the package directory tree (capstone/...) under src/main/proto.
    ( cd "$CANON" && find . -name '*.proto' -print0 ) | while IFS= read -r -d '' f; do
        mkdir -p "$dest/$(dirname "$f")"
        cp "$CANON/$f" "$dest/$f"
        printf '    %s\n' "$f"
    done
done

printf '\n==> Done. Rebuild with ./mvnw package — quarkus-grpc regenerates stubs.\n'
