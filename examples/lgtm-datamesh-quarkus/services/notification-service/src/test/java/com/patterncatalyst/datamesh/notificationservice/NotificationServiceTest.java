package com.patterncatalyst.datamesh.notificationservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * Boots against Dev Services (Postgres + Kafka + Apicurio via Testcontainers).
 * Flyway runs the migration; {@code /received} starts empty until events flow.
 */
@QuarkusTest
class NotificationServiceTest {

    @Test
    void liveness() {
        given().when().get("/q/health/live")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void receivedStartsEmpty() {
        given().when().get("/received")
                .then().statusCode(200).body("size()", is(0));
    }
}
