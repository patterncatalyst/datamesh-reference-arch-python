package com.patterncatalyst.datamesh.orderservice;

import capstone.inventory.v1.CheckStockRequest;
import capstone.inventory.v1.InventoryService;
import io.quarkus.grpc.GrpcClient;
import io.quarkus.hibernate.reactive.panache.Panache;
import io.quarkus.hibernate.reactive.panache.common.WithSession;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * order-service REST surface. Mirrors the Python {@code app/main.py}:
 *
 * <ul>
 *   <li>{@code POST /orders} — validate stock over gRPC, persist, then
 *       best-effort publish an order.placed Avro event;</li>
 *   <li>{@code GET /orders}, {@code GET /orders/{id}} — reads;</li>
 *   <li>{@code GET /version} — the canary signal (v2 adds a {@code currency}
 *       field), the exact contract the Istio weight-split demo keys on.</li>
 * </ul>
 *
 * Liveness/readiness are served by SmallRye Health at {@code /q/health/*}.
 */
@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    private static final Logger LOG = Logger.getLogger(OrderResource.class);

    @GrpcClient("inventory")
    InventoryService inventory;

    @Inject
    OrderEvents events;

    @ConfigProperty(name = "api.version", defaultValue = "v1")
    String apiVersion;

    /**
     * Canary signal (r26). v1 and v2 run the same image with a different
     * API_VERSION; the Istio VirtualService splits traffic between the two
     * subsets, and this side-effect-free endpoint reports which served the
     * request. v2 advertises the additive contract change — a {@code currency}
     * field — the backward-compatible evolution you canary.
     */
    @GET
    @Path("/version")
    public Map<String, String> version() {
        if ("v2".equals(apiVersion)) {
            return Map.of("service", "order-service", "api_version", apiVersion, "currency", "USD");
        }
        return Map.of("service", "order-service", "api_version", apiVersion);
    }

    @POST
    @Path("/orders")
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> placeOrder(OrderCreate payload) {
        // r23: validate stock with inventory-service over gRPC before persisting.
        // Fail closed — we never place an order we couldn't validate.
        CheckStockRequest req = CheckStockRequest.newBuilder()
                .setSku(payload.itemSku)
                .setQuantity(payload.quantity)
                .build();

        return inventory.checkStock(req)
                .onFailure().transform(err -> new WebApplicationException(
                        "inventory-service unreachable: " + err.getMessage(),
                        Response.Status.SERVICE_UNAVAILABLE))
                .onItem().transformToUni(resp -> {
                    if (!resp.getAvailable()) {
                        return Uni.createFrom().item(Response
                                .status(Response.Status.CONFLICT)
                                .entity(Map.of("detail", "insufficient stock for " + payload.itemSku
                                        + " (" + resp.getQuantityOnHand() + " on hand)"))
                                .build());
                    }
                    Order order = new Order();
                    order.id = UUID.randomUUID().toString();
                    order.customerId = payload.customerId;
                    order.itemSku = payload.itemSku;
                    order.quantity = payload.quantity;
                    order.amount = payload.amount;
                    order.status = OrderStatus.placed;
                    // r25: persist (commit) first, then emit the event only
                    // after the order is durably persisted. A publish failure
                    // must not fail the order (best-effort — the outbox pattern
                    // is the production answer).
                    return Panache.<Order>withTransaction(order::persist)
                            .onItem().call(saved -> events.publishOrderPlaced(saved))
                            .onItem().transform(saved -> Response
                                    .status(Response.Status.CREATED).entity(saved).build());
                });
    }

    @GET
    @Path("/orders")
    @WithSession
    public Uni<List<Order>> listOrders(@QueryParam("limit") Integer limit) {
        int cap = (limit == null || limit <= 0) ? 100 : limit;
        return Order.findAll(io.quarkus.panache.common.Sort.descending("createdAt"))
                .page(0, cap).list();
    }

    @GET
    @Path("/orders/{id}")
    @WithSession
    public Uni<Response> getOrder(@PathParam("id") String id) {
        return Order.<Order>findById(id)
                .onItem().transform(order -> order == null
                        ? Response.status(Response.Status.NOT_FOUND)
                                .entity(Map.of("detail", "order not found")).build()
                        : Response.ok(order).build());
    }
}
