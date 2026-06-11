package com.patterncatalyst.datamesh.reviewservice;

import io.quarkus.hibernate.reactive.panache.Panache;
import io.quarkus.hibernate.reactive.panache.common.WithSession;
import io.quarkus.panache.common.Sort;
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * review-service REST surface. Mirrors the Python {@code app/main.py}:
 * create/list/get reviews plus a {@code /version} endpoint read by the
 * discovery publish step. Health is served at {@code /q/health/*}.
 */
@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class ReviewResource {

    @ConfigProperty(name = "quarkus.application.version", defaultValue = "1.0.0")
    String version;

    @GET
    @Path("/version")
    public Map<String, String> version() {
        return Map.of("service", "review-service", "version", version);
    }

    @POST
    @Path("/reviews")
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> createReview(ReviewCreate payload) {
        Review review = new Review();
        review.id = UUID.randomUUID().toString();
        review.sku = payload.sku;
        review.rating = payload.rating;
        review.reviewer = payload.reviewer;
        review.comment = payload.comment;
        return Panache.<Review>withTransaction(review::persist)
                .onItem().transform(saved -> Response.status(Response.Status.CREATED).entity(saved).build());
    }

    @GET
    @Path("/reviews")
    @WithSession
    public Uni<List<Review>> listReviews(@QueryParam("sku") String sku,
                                         @QueryParam("limit") Integer limit) {
        int cap = (limit == null || limit <= 0) ? 100 : limit;
        if (sku != null && !sku.isBlank()) {
            return Review.find("sku", Sort.descending("createdAt"), sku).page(0, cap).list();
        }
        return Review.findAll(Sort.descending("createdAt")).page(0, cap).list();
    }

    @GET
    @Path("/reviews/{id}")
    @WithSession
    public Uni<Response> getReview(@PathParam("id") String id) {
        return Review.<Review>findById(id)
                .onItem().transform(r -> r == null
                        ? Response.status(Response.Status.NOT_FOUND)
                                .entity(Map.of("detail", "review not found")).build()
                        : Response.ok(r).build());
    }
}
