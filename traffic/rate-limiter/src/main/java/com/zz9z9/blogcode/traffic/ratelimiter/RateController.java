package com.zz9z9.blogcode.traffic.ratelimiter;

import com.zz9z9.blogcode.traffic.ratelimiter.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("api")
@RequiredArgsConstructor
public class RateController {

    private final RateService rateService;

    @GetMapping("foo")
    public ResponseEntity<ApiResponse<String>> foo() {
        try {
            Thread.sleep(1000);
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }

        return ResponseEntity.ok(ApiResponse.success("foo"));
    }

    @GetMapping("bar")
    public ResponseEntity<ApiResponse<String>> bar() {
        String result = rateService.doSomething();
        return ResponseEntity.ok(ApiResponse.success(result));
    }

}
