package com.zz9z9.blogcode.traffic.httpconnectionpool.caller;

import java.io.IOException;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.CloseableHttpResponse;
import org.apache.hc.core5.http.ParseException;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Slf4j
@RestController
@RequiredArgsConstructor
public class CallController {

    private final CloseableHttpClient httpClient;
    private final PoolProperties props;

    /** 업스트림을 호출하지 않는 엔드포인트. 느린 업스트림이 무관한 API 까지 잡아먹는지 보는 대조군이다. */
    @GetMapping("/local")
    public ResponseEntity<String> local() {
        return ResponseEntity.ok("ok");
    }

    /**
     * 요청 -> idleMs 만큼 쉼 -> 요청. 두 응답의 X-Peer(caller 소스 포트)가 같으면 커넥션을 재사용한 것이다.
     * 유휴 시간을 서버가 알려준 Keep-Alive: timeout=N 의 앞뒤로 두면 풀이 그 말을 지키는지 보인다 (13번).
     */
    @GetMapping("/keepalive")
    public ResponseEntity<String> keepAlive(@RequestParam(defaultValue = "1000") long idleMs)
            throws IOException, InterruptedException {
        String first = peer();
        Thread.sleep(idleMs);

        try {
            String second = peer();
            return ResponseEntity.ok("first=%s second=%s reused=%s".formatted(first, second, first.equals(second)));
        } catch (IOException e) {
            log.warn("두 번째 요청 실패", e);
            return ResponseEntity.status(500)
                    .body("first=%s second=%s: %s".formatted(first, e.getClass().getSimpleName(), e.getMessage()));
        }
    }

    /** 한 번 호출하고 업스트림이 본 내 소스 포트를 돌려준다. */
    private String peer() throws IOException {
        HttpGet request = new HttpGet(props.upstreamBaseUrl() + "/echo");
        try (CloseableHttpResponse response = httpClient.execute(request)) {
            EntityUtils.consume(response.getEntity());
            return response.getFirstHeader("X-Peer").getValue();
        }
    }

    @GetMapping("/call")
    public ResponseEntity<String> call(@RequestParam(defaultValue = "0") long delayMs,
                                       @RequestParam(defaultValue = "0") int sizeBytes,
                                       @RequestParam(defaultValue = "200") int status,
                                       @RequestParam(defaultValue = "false") boolean close,
                                       @RequestParam(defaultValue = "safe") String mode) throws IOException {
        HttpGet request = new HttpGet("%s/echo?delayMs=%d&sizeBytes=%d&status=%d&close=%s"
                .formatted(props.upstreamBaseUrl(), delayMs, sizeBytes, status, close));
        return "leaky".equals(mode) ? leaky(request) : safe(request);
    }

    /**
     * 에러 경로에서 본문을 안 읽고 빠져나간다.
     * 정상 경로에만 close 가 있어서, 평소에는 멀쩡하다가 업스트림 에러율이 오르면 풀이 마른다.
     */
    private ResponseEntity<String> leaky(HttpGet request) throws IOException {
        CloseableHttpResponse response = httpClient.execute(request);

        if (response.getCode() >= 400) {
            log.warn("업스트림 에러: {}", response.getCode());
            return ResponseEntity.status(502).body("upstream=" + response.getCode());
        }

        try {
            String body = EntityUtils.toString(response.getEntity());
            response.close();
            return ResponseEntity.ok("upstream=200, " + body.length() + " bytes");
        } catch (ParseException e) {
            throw new IOException(e);
        }
    }

    /** try-with-resources 로 감싸서 어느 경로로 나가든 본문을 소비하고 닫는다. */
    private ResponseEntity<String> safe(HttpGet request) throws IOException {
        try (CloseableHttpResponse response = httpClient.execute(request)) {
            EntityUtils.consume(response.getEntity());
            int code = response.getCode();
            return code >= 400
                    ? ResponseEntity.status(502).body("upstream=" + code)
                    : ResponseEntity.ok("upstream=" + code);
        }
    }
}
