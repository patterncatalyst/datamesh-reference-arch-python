#!/usr/bin/env bash
#
# publish-discovery-contracts.sh — publish the mesh's *discovery* contracts to
# Apicurio, alongside the Avro *runtime* contract that order-service already
# registers. These are the discovery artifacts OpenMetadata will later ingest
# (CAP-018): they're published for discovery, not on any runtime path.
#
# Publishes three artifacts via Apicurio's native v3 API
# (POST /apis/registry/v3/groups/{group}/artifacts):
#   - order-service-openapi  (OPENAPI)  ← fetched from order-service /openapi.json
#   - inventory-grpc-proto   (PROTOBUF) ← read from the committed .proto file
#   - graphql-gateway-sdl    (GRAPHQL)  ← fetched from the gateway /sdl endpoint
#
# Idempotent: an artifact that already exists (HTTP 409) is treated as already
# published. (Production CI would add a new version instead.)
#
# Reachable URLs are supplied by the caller (the smoke script brings up SSH
# tunnels and passes localhost URLs):
#   APICURIO_URL   e.g. http://127.0.0.1:8084   (apicurio tunnel)
#   ORDER_URL      e.g. http://127.0.0.1:8080   (order-service tunnel)
#   GATEWAY_URL    e.g. http://127.0.0.1:8081   (KEDA interceptor tunnel)
#   GATEWAY_HOST   Host header routing the interceptor to the gateway
#                  (default graphql-gateway.capstone) — required because the
#                  gateway is KEDA-scaled-to-zero and only reachable via the
#                  interceptor, which routes by Host.
#   PROTO_PATH     e.g. proto/capstone/inventory/v1/inventory.proto

set -euo pipefail

APICURIO_URL="${APICURIO_URL:?set APICURIO_URL}"
ORDER_URL="${ORDER_URL:?set ORDER_URL}"
GATEWAY_URL="${GATEWAY_URL:?set GATEWAY_URL}"
GATEWAY_HOST="${GATEWAY_HOST:-graphql-gateway.capstone}"
PROTO_PATH="${PROTO_PATH:?set PROTO_PATH}"
GROUP="${APICURIO_GROUP:-default}"

[[ -f "$PROTO_PATH" ]] || { echo "proto not found: $PROTO_PATH" >&2; exit 1; }

python3 - "$APICURIO_URL" "$ORDER_URL" "$GATEWAY_URL" "$PROTO_PATH" "$GROUP" "$GATEWAY_HOST" <<'PY'
import json, sys, urllib.request, urllib.error

apicurio, order_url, gateway_url, proto_path, group, gateway_host = sys.argv[1:7]

def fetch(url, as_text=False, headers=None, timeout=10):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read().decode("utf-8")
    return data if as_text else data

def publish(artifact_id, artifact_type, content, content_type):
    """Create an artifact in Apicurio via the native v3 API. 409 => already there."""
    body = json.dumps({
        "artifactId": artifact_id,
        "artifactType": artifact_type,
        "firstVersion": {
            "content": {"content": content, "contentType": content_type}
        },
    }).encode("utf-8")
    url = f"{apicurio}/apis/registry/v3/groups/{group}/artifacts"
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            r.read()
        print(f"    ✓ published {artifact_id} ({artifact_type})")
    except urllib.error.HTTPError as e:
        if e.code == 409:
            print(f"    ✓ {artifact_id} ({artifact_type}) already registered")
        else:
            print(f"    ✗ {artifact_id}: HTTP {e.code} {e.read().decode('utf-8','ignore')[:200]}", file=sys.stderr)
            raise

# 1) OpenAPI — order-service's live spec (the REST discovery contract).
print("==> OpenAPI (order-service /openapi.json)")
openapi = fetch(f"{order_url}/openapi.json")
publish("order-service-openapi", "OPENAPI", openapi, "application/json")

# 2) Protobuf — the committed gRPC definition (no service needed).
print("==> Protobuf (inventory .proto)")
with open(proto_path, encoding="utf-8") as f:
    proto = f.read()
publish("inventory-grpc-proto", "PROTOBUF", proto, "text/plain")

# 3) GraphQL SDL — the gateway's schema (the GraphQL discovery contract).
#    Fetched THROUGH the KEDA interceptor, so send the Host header it routes on.
print("==> GraphQL SDL (gateway /sdl via interceptor)")
sdl = fetch(f"{gateway_url}/sdl", as_text=True, headers={"Host": gateway_host}, timeout=60)
publish("graphql-gateway-sdl", "GRAPHQL", sdl, "text/plain")

print("==> Done — discovery contracts published to Apicurio")
PY
