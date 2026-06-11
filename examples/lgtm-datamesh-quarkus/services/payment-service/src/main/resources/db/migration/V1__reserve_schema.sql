-- payment-service owns the `payments` schema (per-service ownership, CAP-003),
-- created by Flyway. No domain tables yet — the skeleton reserves the schema
-- and stands up health/metrics, mirroring the Python skeleton.
CREATE SCHEMA IF NOT EXISTS payments;
