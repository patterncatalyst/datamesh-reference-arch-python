package com.patterncatalyst.datamesh.orderservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * Boots the full app against Dev Services (Postgres + Kafka + Apicurio via
 * Testcontainers) and asserts the canary {@code /version} contract — the exact
 * signal the Istio weight-split demo keys on. Defaults to v1; the v2 behaviour
 * (additive {@code currency} field) is verified in {@link OrderVersionV2Test}.
 */
@QuarkusTest
class OrderResourceTest {

    @Test
    void liveness() {
        given().when().get("/q/health/live")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void versionDefaultsToV1WithoutCurrency() {
        given().when().get("/version")
                .then().statusCode(200)
                .body("service", is("order-service"))
                .body("api_version", is("v1"))
                .body("currency", nullValue());
    }
}
