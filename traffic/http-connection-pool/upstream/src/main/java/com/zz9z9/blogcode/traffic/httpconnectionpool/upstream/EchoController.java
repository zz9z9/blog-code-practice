package com.zz9z9.blogcode.traffic.httpconnectionpool.upstream;

import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.http.ResponseEntity.BodyBuilder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 상대 서버 흉내. HTTP 레벨(응답 내용·시간·헤더)만 담당한다.
 * 커넥션·네트워크 장애(RTT, reset)는 toxiproxy 가 맡는다.
 */
@RestController
public class EchoController {

    /** 요청마다 만들면 upstream 의 GC·CPU 를 재게 된다. 미리 만들어둔다 */
    private static final Map<Integer, byte[]> BODIES = Stream.of(0, 1024, 102400)
            .collect(Collectors.toMap(size -> size, EchoController::filled));

    private final AtomicLong served = new AtomicLong();

    @GetMapping("/echo")
    public ResponseEntity<byte[]> echo(@RequestParam(defaultValue = "0") long delayMs,
                                       @RequestParam(defaultValue = "0") int sizeBytes,
                                       @RequestParam(defaultValue = "200") int status,
                                       @RequestParam(defaultValue = "false") boolean close,
                                       HttpServletRequest servletRequest)
            throws InterruptedException {
        if (delayMs > 0) {
            Thread.sleep(delayMs);   // 스레드는 점유, CPU 는 안 쓴다
        }
        byte[] body = BODIES.get(sizeBytes);
        if (body == null) {
            throw new IllegalArgumentException("미리 만들어둔 크기가 아니다: " + sizeBytes + " (" + BODIES.keySet() + ")");
        }

        BodyBuilder builder = ResponseEntity.status(status)
                .header("X-Served", Long.toString(served.incrementAndGet()))
                // caller 의 소스 포트. 두 요청의 값이 같으면 같은 TCP 커넥션이다 (가설 13)
                .header("X-Peer", servletRequest.getRemoteAddr() + ":" + servletRequest.getRemotePort());
        if (close) {
            builder.header(HttpHeaders.CONNECTION, "close");   // 재시작 없이 keep-alive 만 끈다
        }
        return builder.body(body);
    }

    private static byte[] filled(int size) {
        byte[] body = new byte[size];
        java.util.Arrays.fill(body, (byte) 'x');
        return body;
    }
}
