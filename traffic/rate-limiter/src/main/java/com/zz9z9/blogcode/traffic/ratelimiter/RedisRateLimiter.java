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

    public boolean tryAcquire(String apiUrl) {
        String counterKey = "limit:" + apiUrl;
        Long current = redisTemplate.opsForValue().increment(counterKey);

        int maxConcurrent = getDynamicCount(requestId);

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

    public void updateLatency(String requestId, long latencyMillis) {
        int newCount = calculateNewCount(requestId, latencyMillis); // 상한값
        redisTemplate.opsForValue().set("ratelimit:count:" + requestId, newCount);
    }

    private int getDynamicCount(String requestId) {
        // 기본값
        int defaultCount = 10;

        // Redis에 저장된 동적 값이 있다면 사용
        Integer count = redisTemplate.opsForValue().get("ratelimit:count:" + requestId);
        return (count != null) ? count : defaultCount;
    }

    private int calculateNewCountBySlidingWindow(String requestId, long latencyMillis) {
        String latencyKey = "ratelimit:latency:" + requestId;
        String countKey = "ratelimit:count:" + requestId;

        // 최근 10개 응답 시간 유지
        redisTemplate.opsForList().rightPush(latencyKey, String.valueOf(latencyMillis));
        redisTemplate.opsForList().trim(latencyKey, -10, -1); // 최근 10개만 유지

        // 평균 계산
        List<String> latencyList = redisTemplate.opsForList().range(latencyKey, 0, -1);
        double avgLatency = latencyList.stream()
                .mapToLong(Long::parseLong)
                .average()
                .orElse(latencyMillis); // 없으면 현재 latency 사용

        // 예: 200ms 기준으로 증가/감소 (단순 선형 비례)
        int newCount = (int) Math.round(200.0 / Math.max(100.0, avgLatency) * 10);
        newCount = Math.max(MIN_COUNT, Math.min(MAX_COUNT, newCount));

        redisTemplate.opsForValue().set(countKey, newCount);
        return newCount;
    }

    // 이전 평균에 새로운 값을 가중치로 반영해 부드럽게 변하는 평균을 만듭니다.
    // EWMA_new = α × latency_new + (1 - α) × EWMA_old
    // α가 클수록 새 값에 민감하게 반응 , α가 작을수록 부드럽게 반응
    private int calculateNewCountByEWMA(String requestId, long latencyMillis) {
        String ewmaKey = "ratelimit:ewma:" + requestId;
        String countKey = "ratelimit:count:" + requestId;
        final double alpha = 0.3;

        String ewmaStr = redisTemplate.opsForValue().get(ewmaKey);
        double ewma;
        if (ewmaStr == null) {
            ewma = latencyMillis;
        } else {
            double previousEwma = Double.parseDouble(ewmaStr);
            ewma = alpha * latencyMillis + (1 - alpha) * previousEwma;
        }

        redisTemplate.opsForValue().set(ewmaKey, String.valueOf(ewma));

        // 예: 200ms 기준으로 scaling
        int newCount = (int) Math.round(200.0 / Math.max(100.0, ewma) * 10);
        newCount = Math.max(MIN_COUNT, Math.min(MAX_COUNT, newCount));

        redisTemplate.opsForValue().set(countKey, newCount);
        return newCount;
    }

}
