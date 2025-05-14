package com.zz9z9.blogcode.traffic.ratelimiter;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

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
            redisTemplate.opsForValue().decrement(counterKey); // 롤백
            return false;
        }

        return true;
    }

    public void release(String apiUrl) {
        String counterKey = "limit:" + apiUrl;
        redisTemplate.opsForValue().decrement(counterKey);
    }

}
