package com.zz9z9.blogcode.traffic.ratelimiter.common;

import com.zz9z9.blogcode.traffic.ratelimiter.support.RateLimitExceededException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler
    public ResponseEntity<ApiResponse<String>> handleRateLimitExceededException(RateLimitExceededException ex) {
        log.error(ex.getMessage(), ex);
        return ResponseEntity.badRequest().body(ApiResponse.error(HttpStatus.TOO_MANY_REQUESTS.value(), "잠시 후 다시 요청해주세요."));
    }

}
