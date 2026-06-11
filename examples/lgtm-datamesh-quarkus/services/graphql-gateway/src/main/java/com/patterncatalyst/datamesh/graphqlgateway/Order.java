package com.patterncatalyst.datamesh.graphqlgateway;

import java.math.BigDecimal;

/**
 * GraphQL Order type, also the deserialization target for order-service's REST
 * JSON. With the gateway's SNAKE_CASE Jackson strategy, incoming snake_case
 * JSON ({@code customer_id}, {@code item_sku}, {@code created_at}) binds to
 * these camelCase fields; SmallRye GraphQL exposes them camelCase in the schema
 * ({@code itemSku}, …), matching the Strawberry gateway's auto-camelCasing.
 */
public class Order {
    public String id;
    public String customerId;
    public String itemSku;
    public int quantity;
    public BigDecimal amount;
    public String status;
    public String createdAt;
}
