-- notification-service schema. Flyway runs this at startup against the
-- service's own `notifications` schema (quarkus.flyway.schemas). The Quarkus
-- counterpart of the Python Alembic 0001_create_notifications migration; the
-- unique order_id constraint backs the consumer's at-least-once idempotency.
CREATE TABLE IF NOT EXISTS notifications (
    id          VARCHAR PRIMARY KEY,
    order_id    VARCHAR NOT NULL,
    event_type  VARCHAR NOT NULL,
    customer_id VARCHAR,
    item_sku    VARCHAR,
    quantity    INTEGER,
    amount      VARCHAR,
    status      VARCHAR,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_notifications_order_id UNIQUE (order_id)
);
