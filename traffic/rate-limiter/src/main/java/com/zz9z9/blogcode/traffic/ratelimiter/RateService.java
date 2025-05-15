package com.zz9z9.blogcode.traffic.ratelimiter;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class RateService {

    private final ApiCaller caller;

    public String doSomething() {
        String result = caller.requestSomething();

        // ... 비즈니르 로직 처리

        return "something";
    }

}
