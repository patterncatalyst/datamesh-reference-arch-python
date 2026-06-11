package com.patterncatalyst.datamesh.graphqlgateway;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * The gateway is stateless and its downstream clients connect lazily, so this
 * boots with no external dependencies. Asserts liveness and that the generated
 * SDL (the gateway's discovery contract, served at /graphql/schema.graphql)
 * carries the federated shape — Order with a stitched stock field.
 */
@QuarkusTest
class GatewayApiTest {

    @Test
    void liveness() {
        given().when().get("/q/health/live")
                .then().statusCode(200).body("status", is("UP"));
    }

    @Test
    void sdlExposesFederatedSchema() {
        given().when().get("/graphql/schema.graphql")
                .then().statusCode(200)
                .body(allOf(
                        containsString("type Order"),
                        containsString("type Stock"),
                        containsString("quantityOnHand"),
                        containsString("itemSku")));
    }
}
