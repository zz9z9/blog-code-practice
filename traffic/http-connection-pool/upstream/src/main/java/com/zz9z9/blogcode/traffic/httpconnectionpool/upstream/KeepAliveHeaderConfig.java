package com.zz9z9.blogcode.traffic.httpconnectionpool.upstream;

import org.apache.coyote.ProtocolHandler;
import org.apache.coyote.http11.AbstractHttp11Protocol;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.embedded.tomcat.TomcatConnectorCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 톰캣은 요청에 Connection: keep-alive 가 있으면 응답에 Keep-Alive: timeout=N 을 붙여 자기 타임아웃을 알려준다.
 * 이 헤더를 끄면 "자기 타임아웃을 안 알려주는 서버" 가 된다.
 * 그러면 클라이언트는 RequestConfig.connectionKeepAlive(기본 3분)로 떨어지고,
 * 서버가 그보다 먼저 끊으므로 설정이 어긋나서 생기는 stale 을 만들 수 있다 (11번).
 */
@Configuration
public class KeepAliveHeaderConfig {

    @Bean
    TomcatConnectorCustomizer keepAliveHeaderCustomizer(
            @Value("${lab.keep-alive-response-header:true}") boolean enabled) {
        return connector -> {
            ProtocolHandler handler = connector.getProtocolHandler();
            if (handler instanceof AbstractHttp11Protocol<?> protocol) {
                protocol.setUseKeepAliveResponseHeader(enabled);
            }
        };
    }
}
