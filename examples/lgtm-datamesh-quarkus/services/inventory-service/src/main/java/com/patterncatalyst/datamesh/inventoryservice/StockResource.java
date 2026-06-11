package com.patterncatalyst.datamesh.inventoryservice;

import io.quarkus.hibernate.reactive.panache.common.WithSession;
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.List;

/**
 * Read-only convenience endpoint listing current stock — for demos and
 * debugging. Mirrors the Python {@code GET /stock}.
 */
@Path("/stock")
@Produces(MediaType.APPLICATION_JSON)
public class StockResource {

    @GET
    @WithSession
    public Uni<List<Stock>> listStock() {
        return Stock.listAll();
    }
}
