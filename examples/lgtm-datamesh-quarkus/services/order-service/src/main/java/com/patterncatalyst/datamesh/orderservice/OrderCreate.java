package com.patterncatalyst.datamesh.orderservice;

import java.math.BigDecimal;

/**
 * Request body for placing an order. The API contract, kept separate from the
 * {@link Order} storage model — the same decoupling the Python tree draws
 * between its Pydantic schema and SQLAlchemy model. With the service's
 * SNAKE_CASE Jackson strategy, incoming JSON {@code customer_id}/{@code item_sku}
 * bind to these fields.
 */
public class OrderCreate {
    public String customerId;
    public String itemSku;
    public int quantity;
    public BigDecimal amount;
}
