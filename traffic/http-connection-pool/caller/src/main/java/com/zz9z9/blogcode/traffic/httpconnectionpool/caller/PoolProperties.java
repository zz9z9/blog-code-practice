package com.zz9z9.blogcode.traffic.httpconnectionpool.caller;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 실험 조건은 전부 여기로 뺀다. 이미지 재빌드 없이 환경변수만 바꿔 재기동한다.
 * 음수는 "설정하지 않음"(라이브러리 기본값에 맡김)을 뜻한다.
 */
@ConfigurationProperties(prefix = "pool")
public record PoolProperties(
        String upstreamBaseUrl,
        int maxTotal,
        int maxPerRoute,
        long connectionRequestTimeoutMs,
        long connectTimeoutMs,
        long responseTimeoutMs,
        long socketTimeoutMs,
        long validateAfterInactivityMs,
        long evictIdleMs,
        long timeToLiveMs,
        boolean retryEnabled
) {
}
