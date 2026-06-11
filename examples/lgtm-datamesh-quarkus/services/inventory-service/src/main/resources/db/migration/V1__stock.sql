-- inventory-service schema + demo seed. Flyway runs this at startup against
-- the service's own `inventory` schema (quarkus.flyway.schemas). The Quarkus
-- counterpart of the Python init_schema + seed_demo_stock; ON CONFLICT keeps
-- the seed idempotent. Gives the smoke test a known in-stock SKU and a known
-- out-of-stock SKU.
CREATE TABLE IF NOT EXISTS stock (
    sku              VARCHAR(64) PRIMARY KEY,
    quantity_on_hand INTEGER NOT NULL DEFAULT 0
);

INSERT INTO stock (sku, quantity_on_hand) VALUES
    ('WIDGET-001', 50),   -- in stock
    ('WIDGET-OOS', 0)     -- out of stock
ON CONFLICT (sku) DO NOTHING;
