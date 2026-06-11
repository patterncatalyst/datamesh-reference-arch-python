package com.patterncatalyst.datamesh.orderservice;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.junit.QuarkusTestProfile;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * The v2 side of the canary contract: the same image with API_VERSION=v2
 * advertises an additive {@code currency} field.
 */
@QuarkusTest
@TestProfile(OrderVersionV2Test.V2Profile.class)
class OrderVersionV2Test {

    public static class V2Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of("api.version", "v2");
        }
    }

    @Test
    void versionV2AddsCurrency() {
        given().when().get("/version")
                .then().statusCode(200)
                .body("api_version", is("v2"))
                .body("currency", is("USD"));
    }
}
