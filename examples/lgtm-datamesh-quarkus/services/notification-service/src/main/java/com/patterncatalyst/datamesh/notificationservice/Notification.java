package com.patterncatalyst.datamesh.notificationservice;

import io.quarkus.hibernate.reactive.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * A persisted order.placed notification, in the service's own
 * {@code notifications} schema (CAP-003). Mirrors the Python model. The table
 * is created + evolved by Flyway (not Hibernate), so this entity only maps it.
 *
 * <p>Idempotency: at-least-once Kafka delivery means the same order can arrive
 * more than once; the unique {@code order_id} constraint (and an existence
 * check in the consumer) makes a redelivery a no-op rather than a duplicate.
 */
@Entity
@Table(name = "notifications",
        uniqueConstraints = @UniqueConstraint(name = "uq_notifications_order_id", columnNames = "order_id"))
public class Notification extends PanacheEntityBase {

    @Id
    public String id;            // reuse the stable, unique order_id as the PK

    @Column(name = "order_id", nullable = false)
    public String orderId;

    @Column(name = "event_type", nullable = false)
    public String eventType;

    @Column(name = "customer_id")
    public String customerId;

    @Column(name = "item_sku")
    public String itemSku;

    public Integer quantity;

    public String amount;

    public String status;

    @Column(name = "created_at", nullable = false)
    public OffsetDateTime createdAt = OffsetDateTime.now(ZoneOffset.UTC);
}
