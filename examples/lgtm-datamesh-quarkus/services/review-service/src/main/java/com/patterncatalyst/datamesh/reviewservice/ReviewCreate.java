package com.patterncatalyst.datamesh.reviewservice;

/** Request body for creating a review. */
public class ReviewCreate {
    public String sku;
    public int rating;
    public String reviewer;
    public String comment;
}
