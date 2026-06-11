package com.patterncatalyst.datamesh.inventoryservice;

import capstone.inventory.v1.CheckStockRequest;
import capstone.inventory.v1.CheckStockResponse;
import capstone.inventory.v1.InventoryService;
import io.quarkus.grpc.GrpcService;
import io.quarkus.hibernate.reactive.panache.common.WithSession;
import io.smallrye.mutiny.Uni;

/**
 * gRPC server for inventory-service — implements InventoryService.CheckStock,
 * the first real cross-service call in the mesh (order-service dials
 * {@code inventory-service:50051}).
 *
 * <p>The stubs are generated at build time from {@code src/main/proto}
 * (quarkus-grpc) rather than committed — see DRA-002. The Mutiny service
 * interface {@link InventoryService} is the reactive analog of the Python
 * {@code InventoryServicer}; {@link WithSession} opens a reactive Hibernate
 * session for the duration of the call.
 */
@GrpcService
public class InventoryGrpcService implements InventoryService {

    @Override
    @WithSession
    public Uni<CheckStockResponse> checkStock(CheckStockRequest request) {
        return Stock.<Stock>findById(request.getSku())
                .map(stock -> {
                    int onHand = stock == null ? 0 : stock.quantityOnHand;
                    boolean available = request.getQuantity() > 0 && onHand >= request.getQuantity();
                    return CheckStockResponse.newBuilder()
                            .setAvailable(available)
                            .setQuantityOnHand(onHand)
                            .build();
                });
    }
}
