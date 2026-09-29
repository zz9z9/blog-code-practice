package com.zz9z9.blogcode.traffic.httpconnectionpool.caller;

import java.util.concurrent.TimeUnit;

import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.ssl.DefaultClientTlsStrategy;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.client5.http.ssl.TrustAllStrategy;
import org.apache.hc.core5.ssl.SSLContexts;
import org.apache.hc.core5.http.io.SocketConfig;
import org.apache.hc.core5.util.TimeValue;
import org.apache.hc.core5.util.Timeout;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.httpcomponents.hc5.PoolingHttpClientConnectionManagerMetricsBinder;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Slf4j
@Configuration
public class HttpClientConfig {

    @Bean
    public PoolingHttpClientConnectionManager connectionManager(PoolProperties props) {
        ConnectionConfig.Builder connectionConfig = ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofMilliseconds(props.connectTimeoutMs()))
                .setSocketTimeout(Timeout.ofMilliseconds(props.socketTimeoutMs()));

        // 음수면 아예 안 건드린다 -> 매니저가 null 을 보고 2초로 채운다 (resolveValidateAfterInactivity)
        if (props.validateAfterInactivityMs() >= 0) {
            connectionConfig.setValidateAfterInactivity(TimeValue.ofMilliseconds(props.validateAfterInactivityMs()));
        }
        if (props.timeToLiveMs() >= 0) {
            connectionConfig.setTimeToLive(TimeValue.ofMilliseconds(props.timeToLiveMs()));
        }

        PoolingHttpClientConnectionManagerBuilder builder = PoolingHttpClientConnectionManagerBuilder.create()
                .setDefaultConnectionConfig(connectionConfig.build())
                .setDefaultSocketConfig(SocketConfig.custom().setTcpNoDelay(true).build())
                // 실습용 자체서명 인증서를 그대로 신뢰한다 (4번에서 https 를 재기 위한 것)
                .setTlsSocketStrategy(new DefaultClientTlsStrategy(trustAll(), NoopHostnameVerifier.INSTANCE));

        // 0 이하로 두면 builder 가 덮어쓰지 않는다 -> 라이브러리 기본값 perRoute 5 / total 25 (가설 2)
        if (props.maxTotal() > 0) {
            builder.setMaxConnTotal(props.maxTotal());
        }
        if (props.maxPerRoute() > 0) {
            builder.setMaxConnPerRoute(props.maxPerRoute());
        }

        PoolingHttpClientConnectionManager manager = builder.build();
        log.info("pool: maxTotal={}, maxPerRoute={}, validateAfterInactivity={}",
                manager.getMaxTotal(), manager.getDefaultMaxPerRoute(), manager.getValidateAfterInactivity());
        return manager;
    }

    private static javax.net.ssl.SSLContext trustAll() {
        try {
            return SSLContexts.custom().loadTrustMaterial(TrustAllStrategy.INSTANCE).build();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @Bean
    public CloseableHttpClient httpClient(PoolingHttpClientConnectionManager manager, PoolProperties props) {
        RequestConfig.Builder requestConfig = RequestConfig.custom()
                .setResponseTimeout(props.responseTimeoutMs(), TimeUnit.MILLISECONDS);

        // 음수면 무한 대기 (가설 7 의 "포기가 없는" 쪽)
        if (props.connectionRequestTimeoutMs() >= 0) {
            requestConfig.setConnectionRequestTimeout(props.connectionRequestTimeoutMs(), TimeUnit.MILLISECONDS);
        } else {
            requestConfig.setConnectionRequestTimeout(Timeout.DISABLED);
        }

        var clientBuilder = HttpClients.custom()
                .setConnectionManager(manager)
                .setConnectionManagerShared(true)
                .setDefaultRequestConfig(requestConfig.build());

        // 음수면 기본 전략(DefaultConnectionKeepAliveStrategy) 그대로 -> 서버의 Keep-Alive: timeout=N 을 따른다.
        // 값을 주면 서버가 뭐라 하든 이 값으로 고정한다 (가설 13)
        if (props.keepAliveMs() >= 0) {
            TimeValue fixed = TimeValue.ofMilliseconds(props.keepAliveMs());
            clientBuilder.setKeepAliveStrategy((response, context) -> fixed);
        }
        if (!props.retryEnabled()) {
            clientBuilder.disableAutomaticRetries();   // 가설 10 — 기본값은 멱등 요청을 1회 재시도한다
        }
        if (props.evictIdleMs() >= 0) {
            clientBuilder.evictIdleConnections(TimeValue.ofMilliseconds(props.evictIdleMs()));
        }
        return clientBuilder.build();
    }

    @Bean
    public PoolingHttpClientConnectionManagerMetricsBinder poolMetrics(PoolingHttpClientConnectionManager manager,
                                                                      MeterRegistry registry) {
        PoolingHttpClientConnectionManagerMetricsBinder binder =
                new PoolingHttpClientConnectionManagerMetricsBinder(manager, "caller-pool");
        binder.bindTo(registry);
        return binder;
    }
}
