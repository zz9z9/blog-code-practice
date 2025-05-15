package com.zz9z9.blogcode.traffic.ratelimiter;

import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class RedisRateLimiter {

    private final StringRedisTemplate redisTemplate;

    public RedisRateLimiter(StringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    public boolean tryAcquire(String apiUrl, long maxConcurrent) {
        String counterKey = "limit:" + apiUrl;
        Long current = redisTemplate.opsForValue().increment(counterKey);

        if (current == null || current > maxConcurrent) {
            log.warn("fail --> current count : {}, max : {}", current, maxConcurrent);
            redisTemplate.opsForValue().decrement(counterKey); // 롤백
            return false;
        }

        log.info("success --> current count : {}, max : {}", current, maxConcurrent);

        return true;
    }

    public void release(String apiUrl) {
        String counterKey = "limit:" + apiUrl;
        redisTemplate.opsForValue().decrement(counterKey);
    }

}
