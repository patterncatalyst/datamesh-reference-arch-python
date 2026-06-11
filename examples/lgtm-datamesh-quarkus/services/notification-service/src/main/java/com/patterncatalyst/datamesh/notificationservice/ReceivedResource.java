package com.patterncatalyst.datamesh.notificationservice;

import io.quarkus.hibernate.reactive.panache.common.WithSession;
import io.quarkus.panache.common.Sort;
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.List;

/**
 * Lists notifications persisted from consumed events (newest first). Mirrors
 * the Python {@code GET /received}.
 */
@Path("/received")
@Produces(MediaType.APPLICATION_JSON)
public class ReceivedResource {

    @GET
    @WithSession
    public Uni<List<Notification>> received() {
        return Notification.listAll(Sort.descending("createdAt"));
    }
}
