package com.patterncatalyst.datamesh.orderservice;

import io.quarkus.hibernate.reactive.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Order — the order domain's aggregate, in the service's own {@code orders}
 * schema (per-service ownership, CAP-003). Mirrors the Python {@code Order}
 * model. The schema is set globally via
 * {@code quarkus.hibernate-orm.database.default-schema}; Hibernate creates the
 * schema + table on startup (the Quarkus analog of metadata.create_all).
 */
@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {

    @Id
    @Column(length = 36)
    public String id;

    @Column(name = "customer_id", length = 64)
    public String customerId;

    @Column(name = "item_sku", length = 64)
    public String itemSku;

    @Column(nullable = false)
    public int quantity;

    @Column(precision = 12, scale = 2, nullable = false)
    public BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(length = 20, nullable = false)
    public OrderStatus status = OrderStatus.placed;

    @Column(name = "created_at", nullable = false)
    public OffsetDateTime createdAt = OffsetDateTime.now(ZoneOffset.UTC);
}
