package com.patterncatalyst.datamesh.reviewservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/** Backed by Dev Services (Testcontainers Postgres); Flyway seeds demo rows. */
@QuarkusTest
class ReviewResourceTest {

    @Test
    void version() {
        given().when().get("/version")
                .then().statusCode(200).body("service", is("review-service"));
    }

    @Test
    void listsSeededReviews() {
        given().when().get("/reviews")
                .then().statusCode(200).body("reviewer", hasItem("alice"));
    }
}
