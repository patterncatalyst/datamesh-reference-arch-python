package com.patterncatalyst.datamesh.orderservice;

import capstone.order.v1.OrderPlaced;
import io.smallrye.mutiny.Uni;
import io.smallrye.reactive.messaging.MutinyEmitter;
import io.smallrye.reactive.messaging.kafka.api.OutgoingKafkaRecordMetadata;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Message;
import org.jboss.logging.Logger;

/**
 * Publishes the order.placed event as registered Avro. order-service owns this
 * contract: the canonical schema lives in {@code src/main/avro/order-placed.avsc}
 * beside the service that produces it. The Apicurio Avro serializer registers
 * the schema and frames its id into each message (Confluent-compatible);
 * notification-service fetches that schema by id to decode — neither side can
 * encode or decode without the registry.
 *
 * <p>Mirrors the Python {@code app/events.py}: emit is best-effort and happens
 * only after the order is durably persisted (the dual-write caveat is the same;
 * the outbox pattern is the production answer).
 */
@ApplicationScoped
public class OrderEvents {

    private static final Logger LOG = Logger.getLogger(OrderEvents.class);

    @Channel("order-placed")
    MutinyEmitter<OrderPlaced> emitter;

    public Uni<Void> publishOrderPlaced(Order order) {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId(order.id)
                .setCustomerId(order.customerId)
                .setItemSku(order.itemSku)
                .setQuantity(order.quantity)
                .setAmount(order.amount.toPlainString())
                .setStatus(order.status.name())
                .setCreatedAt(order.createdAt.toString())
                .build();

        // Key the message by order id (compaction-friendly, ordered per order).
        Message<OrderPlaced> message = Message.of(event).addMetadata(
                OutgoingKafkaRecordMetadata.<String>builder().withKey(order.id).build());

        return emitter.sendMessage(message)
                .onItem().invoke(() -> LOG.infof("published order.placed (Avro) for %s", order.id))
                .onFailure().recoverWithUni(err -> {
                    LOG.warnf("failed to publish order.placed for %s: %s", order.id, err.getMessage());
                    return Uni.createFrom().voidItem();
                });
    }
}
