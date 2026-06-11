package com.patterncatalyst.datamesh.paymentservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/** Skeleton: liveness + readiness (Postgres reachable via Dev Services). */
@QuarkusTest
class PaymentServiceTest {

    @Test
    void liveness() {
        given().when().get("/q/health/live")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void readiness() {
        given().when().get("/q/health/ready")
                .then().statusCode(200).body("status", is("UP"));
    }
}
