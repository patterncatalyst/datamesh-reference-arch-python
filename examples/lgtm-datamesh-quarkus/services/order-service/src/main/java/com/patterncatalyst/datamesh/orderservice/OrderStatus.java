package com.patterncatalyst.datamesh.orderservice;

/**
 * Order lifecycle states. Mirrors the Python {@code OrderStatus} enum; stored
 * as a string column (rather than a Postgres enum type) for portability.
 */
public enum OrderStatus {
    placed,
    paid,
    shipped,
    cancelled
}
