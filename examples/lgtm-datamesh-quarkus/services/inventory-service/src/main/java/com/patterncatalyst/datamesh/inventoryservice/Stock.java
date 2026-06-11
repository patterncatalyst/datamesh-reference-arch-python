package com.patterncatalyst.datamesh.inventoryservice;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.quarkus.hibernate.reactive.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Stock — the inventory domain's one table, living in the service's own
 * {@code inventory} schema (per-service ownership, CAP-003). inventory-service
 * is the only writer. Mirrors the Python {@code app/models.py:Stock}.
 *
 * <p>The schema is set globally via
 * {@code quarkus.hibernate-orm.database.default-schema} so it stays
 * env-configurable, exactly like the Python {@code settings.service_schema}.
 */
@Entity
@Table(name = "stock")
public class Stock extends PanacheEntityBase {

    @Id
    @Column(length = 64)
    public String sku;

    @JsonProperty("quantity_on_hand")
    @Column(name = "quantity_on_hand", nullable = false)
    public int quantityOnHand;
}
