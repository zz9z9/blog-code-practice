package com.zz9z9.blogcode.traffic.ratelimiter;

import org.springframework.stereotype.Component;

@Component
public class ApiCaller {

    @LimitRequest(requestId = "barRequest", count = 10)
    public String requestSomething() {
        try {
            Thread.sleep(5000L);
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }

        return "result";
    }


}
