package com.zz9z9.blogcode.traffic.ratelimiter.support;

public class RateLimitExceededException extends RuntimeException {

    public RateLimitExceededException(String message) {
        super(message);
    }

}
