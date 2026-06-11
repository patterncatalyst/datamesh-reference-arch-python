package com.patterncatalyst.datamesh.graphqlgateway;

/**
 * GraphQL Stock type — the live stock for an order's SKU, resolved from
 * inventory-service over gRPC. {@code available} is relative to the order's
 * quantity (computed in the order's context).
 */
public class Stock {
    public String sku;
    public int quantityOnHand;
    public boolean available;
}
