package com.patterncatalyst.datamesh.inventoryservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * Component test backed by Quarkus Dev Services (Testcontainers Postgres), so
 * Flyway runs the real migration + seed. This is the idiomatic Quarkus analog
 * of the Python tests' SQLite-in-memory approach; it needs a container runtime
 * (podman/docker), which the repo already assumes.
 */
@QuarkusTest
class InventoryServiceTest {

    @Test
    void liveness() {
        given().when().get("/q/health/live")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void readinessChecksPostgres() {
        given().when().get("/q/health/ready")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void stockEndpointReturnsSeededRows() {
        given().when().get("/stock")
                .then().statusCode(200).body("sku", hasItem("WIDGET-001"));
    }
}
