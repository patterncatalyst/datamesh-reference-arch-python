package com.patterncatalyst.datamesh.graphqlgateway;

import capstone.inventory.v1.CheckStockRequest;
import capstone.inventory.v1.InventoryService;
import io.quarkus.grpc.GrpcClient;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;
import org.eclipse.microprofile.rest.client.inject.RestClient;

/**
 * The unified graph. The {@code order} query resolves an order from
 * order-service (REST); the nested {@code stock} field on that order resolves
 * from inventory-service (gRPC). The client asks one question and gets a
 * stitched answer spanning two services and two protocols — the value GraphQL
 * adds over calling each service directly (CAP-012). Mirrors the Python
 * Strawberry schema.
 */
@GraphQLApi
public class GatewayApi {

    @Inject
    @RestClient
    OrderClient orderClient;

    @GrpcClient("inventory")
    InventoryService inventory;

    @Query("order")
    public Uni<Order> order(@Name("id") String id) {
        // Fetch a single order (REST); its `stock` field federates to gRPC.
        // A missing order (or any downstream error) resolves to null rather
        // than failing the whole query.
        return orderClient.getOrder(id)
                .onFailure().recoverWithItem((Order) null);
    }

    /**
     * Field resolver adding {@code stock} to the Order type — the live stock
     * for the order's SKU, fetched from inventory-service over gRPC.
     * {@code available} is computed relative to the order's quantity.
     */
    public Uni<Stock> stock(@Source Order order) {
        CheckStockRequest req = CheckStockRequest.newBuilder()
                .setSku(order.itemSku)
                .setQuantity(order.quantity)
                .build();
        return inventory.checkStock(req).map(resp -> {
            Stock s = new Stock();
            s.sku = order.itemSku;
            s.quantityOnHand = resp.getQuantityOnHand();
            s.available = resp.getAvailable();
            return s;
        });
    }
}
