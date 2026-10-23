---
title: "Services & data products"
order: 4
description: The services, the order-service template, and the anatomy of a data product; its ports, its internal transformation, and the container image that ships it.
duration: 30 min
---

## Learning objectives

By the end of this chapter you can:

- Map a data product's ports, transformation, and metadata onto a concrete domain-service boundary.
- Enumerate the five domain services plus the gateway and the protocol each one exposes.
- Trace the walking-skeleton build order for order-service, from image to a running pod with a real API round trip.
- Apply the multi-stage, non-root container packaging pattern shared by all six images.
- Load a locally built image into the minikube profile's containerd store and explain why `imagePullPolicy: Never` matters there.

## Why this matters

With the [principles]({{ '/docs/01-concepts/' | relative_url }}) and the
[Kubernetes mapping]({{ '/docs/02-kubernetes-substrate/' | relative_url }})
in place, this page gets concrete. What do the data products in this final project
actually look like? What's the one service we build end to end as a template for the
rest, and how does a data product get packaged and shipped as a container image? This
is the first implementation-heavy page; the conceptual scaffolding is behind us.

## What a data product looks like here

Open `order-service` and you can point at everything it does in one running process. It
owns a slice of Postgres that no other service reads directly. It serves orders over
REST, checks stock over gRPC before it writes anything, and publishes an event when an
order lands. Point at any one of those and you're pointing at part of a data product: an
input port, an output port, the transformation between them, or the metadata that
describes the whole thing.

That's also the formal definition. A data product, in Zhamak Dehghani's data mesh model,
is the *architectural quantum*: the smallest unit you can independently deploy and
operate, carrying everything it needs to do its job. It has input ports (where data
comes in), output ports (where it serves data out), the transformation logic between
them, and the metadata and policies that make it discoverable and governed.

![Anatomy of a data product: ports in, ports out, transformation and governance inside]({{ '/assets/diagrams/17-data-product-anatomy.svg' | relative_url }})

In this final project, that abstraction is concrete: **each domain service *is* a data
product.** It owns a slice of the database (its input/internal state), it serves data
through its APIs (output ports), it emits events as other domains' input, and it
publishes a contract and metadata so it can be discovered and depended on. The service
boundary and the data-product boundary are the same boundary. That's the cleanest way
to make domain ownership real instead of aspirational.

## The domain

The domain is order-placement-through-fulfillment, modeled small so the architecture
stays legible. There are **five domain services**, each a bounded context owning its
data and its contract, plus **one gateway** that composes reads across them (the
gateway is a read-layer convenience, not a domain data product, so six images in all).
The five domains:

| Service | Domain | Owns | Talks via |
|---|---|---|---|
| order-service | Order lifecycle | the `orders` schema, the order state machine | REST in from clients, gRPC out to inventory/payment/shipping, publishes `orders.placed` |
| inventory-service | Stock levels | the `inventory` schema | gRPC server, publishes `inventory.updated`, consumes `orders.placed` |
| payment-service | Payments | the `payments` schema | gRPC server, publishes `payments.processed`, consumes `orders.placed` |
| shipping-service | Shipments | the `shipments` schema | gRPC server, publishes `shipments.dispatched`, consumes `payments.processed` |
| notification-service | Notifications | the `notifications` schema | Kafka consumer only: reacts to events, emits notifications |

The variation is deliberate: **not every service exposes every protocol.** Each
exposes the protocols that fit its role, not a uniform surface. notification-service is
event-only because its job is to react, not to be called synchronously, and the
gateway exists to compose reads so clients don't have to fan out across five services.
The reasoning behind which protocol goes where is the subject of the
[data planes page]({{ '/docs/05-data-planes/' | relative_url }}); here the point is
just that the surface follows the role.

Each service owns its own schema in a shared Postgres cluster, one schema per domain,
so the database is partitioned by ownership even though it's one managed cluster. That
"one cluster, one schema per service" choice is what keeps per-domain data ownership
real without running five separate databases on a single learning node.

## Build one service end to end first

Rather than build all six services a layer at a time, the final project takes a
single service all the way through first: a *walking skeleton*. The point is to prove
the entire spine works before widening. Build the image, get it to the cluster, deploy
via Helm, have the operator-managed Postgres come up, the service connect, and data
round-trip through a real API call. Once that path is verified on real hardware, the
remaining services are mechanical repetition of the same pattern.

**order-service is that template.** It's a Python service that owns the `orders`
schema. It starts speaking only REST, and gRPC, GraphQL, and event publishing get
layered on in later steps, but the deployment spine is proven first with the simplest
possible surface.

### Check before you persist, persist before you publish

Once gRPC and events land on top of that REST skeleton, `POST /orders` has three
things to do in sequence: confirm there's stock, write the order, tell the rest of the
mesh it happened. Get the order of those three steps wrong and you get a service that
lies to somebody. Here's the wrong order first, because it's the one most people reach
for without thinking about it:

```python
# Naive: persist first, validate second.
order = Order(
    id=str(uuid.uuid4()),
    customer_id=payload.customer_id,
    item_sku=payload.item_sku,
    quantity=payload.quantity,
    amount=payload.amount,
)
async with SessionLocal() as session:
    session.add(order)
    await session.commit()                                    # A

await check_stock(payload.item_sku, payload.quantity)         # B
await publish_order_placed(order)
```

**#A** The row is durable before anyone has confirmed the warehouse can fill it. If the
stock check below fails, you're now deleting an order you already told Postgres
happened, or leaving it there if the delete fails too.

**#B** A rejected order from this check still has a row sitting in the `orders` table.
Publish the event before you've even reached this line and a downstream consumer has
already reacted to an order that was never valid.

`order-service` runs the steps in the opposite order, and a failure at any step stops
everything after it cleanly:

```python
try:
    await check_stock(payload.item_sku, payload.quantity)      # A
except StockUnavailable as exc:
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=f"insufficient stock for {exc.sku} ({exc.quantity_on_hand} on hand)",
    )

order = Order(
    id=str(uuid.uuid4()),
    customer_id=payload.customer_id,
    item_sku=payload.item_sku,
    quantity=payload.quantity,
    amount=payload.amount,
)
async with SessionLocal() as session:
    session.add(order)
    await session.commit()                                     # B

try:
    await publish_order_placed(order)                          # C
except Exception as exc:
    logger.warning("failed to publish order.placed for %s: %s", order.id, exc)
```

**#A** The gRPC call to inventory-service happens before anything touches Postgres. A
rejected order never gets a row, so there's nothing to clean up.

**#B** The order only becomes durable once inventory has said yes. By the time this
line finishes, the order is real no matter what happens next.

**#C** Publishing is best effort and happens after the commit. The
order already occurred; a Kafka hiccup here gets logged, not treated as a request
failure. That does leave a dual-write gap between "committed to Postgres" and
"published to Kafka," which is exactly what the outbox pattern closes in production
(see `app/events.py`).

That's nearly the actual body of `place_order` in `app/main.py`. Three steps, one
order, each one a gate for the next: check, then persist, then publish.

### Packaging the image

A couple of packaging choices carry across all six images. Dependencies are managed
with a lockfile so builds are reproducible, and the lockfile gets exported into the
image rather than carrying the dependency manager into the runtime.

The image itself is multi-stage: a builder stage resolves dependencies, and a slim
runtime stage copies only the resolved environment and the application code, runs as a
non-root user, and serves the app. That's standard production hygiene; the final
project just applies it from the start instead of retrofitting it later.

## The one part that fights back: getting images to the kubelet

This earns its own section because it's the single part of the final project that
reliably trips people up. The profile is a Docker container (the docker driver)
running containerd, and that container has its own image store, separate from the
Docker Engine on your host. An image you build locally is invisible to the kubelet
until you put it there, and a pod that can't find its image fails in ways that look
like a broken cluster.

### Build with Docker Engine, then load the image

The final project's answer is simple: **build with Docker Engine, then load the
image into the profile with `minikube image load`**. There's no registry to run and
no addresses to reconcile, and it works the same on a native engine and on a VM-based
one (Docker Desktop, for example). That portability is the reason for the choice:
pushing to a registry on the host's loopback only works when the engine's daemon
shares the host's network, and a VM-based engine's doesn't.

### Tags and pull policy

Images are tagged `datamesh/<svc>:v1` and the charts set `imagePullPolicy: Never`. The
policy matters in both directions. If an image was never loaded, the pod fails at once
with `ErrImageNeverPull` instead of quietly trying Docker Hub for a name that exists
nowhere. And because `:v1` is a mutable tag, a rebuild doesn't change what running pods
use on its own, so `scripts/build-image.sh` restarts the Deployments that use the
image it just loaded.

None of this is unique to the final project; any local cluster has some version of the
gap between the host's images and the node's. But the final project is where it bites,
because it's the first place you build and deploy your *own* images at scale. Get the
image workflow right once here, and every service afterward is the same three
commands. (The deeper operational sharp edges of running all this on a single node are
collected as gotchas, separate from this build-level friction.)

With a service shipped and running, the next question is how products describe
themselves so others can find and trust them: contracts and the catalog.

## For deeper coverage

- *Data Mesh* by Zhamak Dehghani: the architectural quantum and why a data product's boundary should match a service's boundary.
- *Cloud Native Patterns* by Cornelia Davis: packaging and runtime patterns for services that double as data products.
- *Kubernetes Patterns* by Bilgin Ibryam & Roland Huß: container image and workload patterns behind the build-load-deploy sequence.
- [Kubernetes documentation](https://kubernetes.io/docs/): image pull policies and the kubelet's image lifecycle.
- [FastAPI](https://fastapi.tiangolo.com/): the framework order-service and its siblings are built on.
