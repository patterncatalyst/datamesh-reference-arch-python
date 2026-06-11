package com.patterncatalyst.datamesh.notificationservice;

import capstone.order.v1.OrderPlaced;
import io.quarkus.hibernate.reactive.panache.common.WithTransaction;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.jboss.logging.Logger;

/**
 * Consumes registered Avro {@code order.placed} events and persists each one.
 * The writer schema is fetched from Apicurio by the id framed into the message
 * (the Apicurio deserializer handles this) — the consumer needs no local copy.
 * Mirrors the Python {@code app/consumer.py}.
 *
 * <p>At-least-once delivery (DDIA): the same order can be redelivered, so the
 * write is idempotent — an existence check on the unique {@code order_id}
 * makes a redelivery a no-op. A persistence failure is logged but does not
 * stop the stream (the message is still acked), matching the Python loop.
 */
@ApplicationScoped
public class NotificationConsumer {

    private static final Logger LOG = Logger.getLogger(NotificationConsumer.class);

    @Incoming("order-placed")
    @WithTransaction
    public Uni<Void> consume(OrderPlaced event) {
        String orderId = event.getOrderId();
        return Notification.count("orderId", orderId)
                .onItem().transformToUni(existing -> {
                    if (existing > 0) {
                        return Uni.createFrom().voidItem();  // idempotent no-op
                    }
                    Notification n = new Notification();
                    n.id = orderId;
                    n.orderId = orderId;
                    n.eventType = event.getEventType();
                    n.customerId = event.getCustomerId();
                    n.itemSku = event.getItemSku();
                    n.quantity = event.getQuantity();
                    n.amount = event.getAmount();
                    n.status = event.getStatus();
                    return n.persist()
                            .onItem().invoke(() -> LOG.infof("persisted %s for order %s",
                                    n.eventType, orderId))
                            .replaceWithVoid();
                })
                .onFailure().recoverWithUni(err -> {
                    LOG.errorf("failed to persist event for order %s: %s", orderId, err.getMessage());
                    return Uni.createFrom().voidItem();
                });
    }
}
