-- review-service schema + demo seed, in the service's own `reviews` schema.
-- The Quarkus counterpart of the Python init_schema + seed_if_empty, so the
-- catalog/lineage demo has data to show immediately.
CREATE TABLE IF NOT EXISTS reviews (
    id         VARCHAR(36) PRIMARY KEY,
    sku        VARCHAR(64) NOT NULL,
    rating     INTEGER NOT NULL,
    reviewer   VARCHAR(64) NOT NULL,
    comment    TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_reviews_sku ON reviews (sku);

INSERT INTO reviews (id, sku, rating, reviewer, comment) VALUES
    ('11111111-1111-1111-1111-111111111111', 'WIDGET-001', 5, 'alice', 'Excellent widget, exactly as described.'),
    ('22222222-2222-2222-2222-222222222222', 'WIDGET-001', 4, 'bob',   'Solid build, fast shipping.'),
    ('33333333-3333-3333-3333-333333333333', 'WIDGET-001', 3, 'carol', 'Does the job, packaging could be better.')
ON CONFLICT (id) DO NOTHING;
