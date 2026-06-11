package com.patterncatalyst.datamesh.graphqlgateway;

import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * REST client for order-service. The base URL is configured via
 * {@code quarkus.rest-client.order-api.url} (the Helm chart injects the
 * in-cluster Service URL). One of the gateway's two federation paths — the
 * other is gRPC to inventory.
 */
@RegisterRestClient(configKey = "order-api")
@Path("/orders")
public interface OrderClient {

    @GET
    @Path("/{id}")
    @Produces(MediaType.APPLICATION_JSON)
    Uni<Order> getOrder(@PathParam("id") String id);
}
