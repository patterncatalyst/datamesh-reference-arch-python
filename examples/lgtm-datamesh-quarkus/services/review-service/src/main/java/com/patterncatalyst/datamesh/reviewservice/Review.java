package com.patterncatalyst.datamesh.reviewservice;

import io.quarkus.hibernate.reactive.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Review — in the service's own {@code reviews} schema (CAP-003). Reviews
 * reference a product {@code sku} — the same identifier the inventory/product
 * domain owns — which is the basis for the cross-product lineage edge declared
 * in OpenMetadata (reviews -> products). Mirrors the Python model; the table is
 * created + seeded by Flyway.
 */
@Entity
@Table(name = "reviews")
public class Review extends PanacheEntityBase {

    @Id
    @Column(length = 36)
    public String id;

    @Column(length = 64, nullable = false)
    public String sku;

    @Column(nullable = false)
    public int rating;     // 1..5

    @Column(length = 64, nullable = false)
    public String reviewer;

    @Column(columnDefinition = "text")
    public String comment;

    @Column(name = "created_at", nullable = false)
    public OffsetDateTime createdAt = OffsetDateTime.now(ZoneOffset.UTC);
}
