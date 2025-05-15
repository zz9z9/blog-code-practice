package com.zz9z9.blogcode.traffic.ratelimiter.support;

import com.zz9z9.blogcode.traffic.ratelimiter.LimitRequest;
import com.zz9z9.blogcode.traffic.ratelimiter.RedisRateLimiter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.stereotype.Component;

import java.lang.reflect.Method;

@Slf4j
@Aspect
@Component
@RequiredArgsConstructor
public class LimitRequestAspect {

    private final RedisRateLimiter redisRateLimiter;

    @Around("@annotation(com.zz9z9.blogcode.traffic.ratelimiter.LimitRequest)")
    public Object around(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        LimitRequest limitRequest = method.getAnnotation(LimitRequest.class);

        String requestId = limitRequest.requestId();
        int count = limitRequest.count();

        boolean acquired = redisRateLimiter.tryAcquire(requestId, count);

        if (!acquired) {
            throw new RateLimitExceededException("Rate limit exceeded for " + requestId);
        }

        long start = System.currentTimeMillis();
        try {
            return joinPoint.proceed();
        } finally {
            long end = System.currentTimeMillis();
            long latency = end - start;
            redisRateLimiter.updateLatency(requestId, latency);
            redisRateLimiter.release(requestId);
        }
    }

}
