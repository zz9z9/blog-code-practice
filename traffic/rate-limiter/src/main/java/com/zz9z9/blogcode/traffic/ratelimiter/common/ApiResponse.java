package com.zz9z9.blogcode.traffic.ratelimiter.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;
import org.springframework.http.HttpStatus;

@Builder
public record ApiResponse<T>(int code, boolean successful, String message, @JsonInclude(JsonInclude.Include.NON_NULL) T data) {

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(HttpStatus.OK.value(), true, "success", data);
    }

    public static <T> ApiResponse<T> error(int status, String message) {
        return new ApiResponse<>(status, false, message, null);
    }

}