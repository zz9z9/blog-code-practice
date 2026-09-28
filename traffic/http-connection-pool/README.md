# HTTP 커넥션 풀 실측

[HTTP 커넥션 풀과 keep-alive, 직접 재보기](https://zz9z9.github.io/posts/http-connection-pool-and-keep-alive/) 의 실습 코드.

## 구성

```
k6 ──▶ caller:8080 ──▶ upstream:8080       (http)    전부 같은 브리지 네트워크
                   └─▶ upstream-tls:8443  (https)
                         ▲   ▲
       (TCP 장애가        │   └─ netem: 각 upstream 의 netns 에 egress 지연
        필요할 때만)       │
            toxiproxy ────┘
```

- **caller** — 측정 대상. HttpClient5 풀 설정을 전부 환경변수로 뺐다. 음수는 "설정하지 않음"(라이브러리 기본값)을 뜻한다.
- **upstream** — 상대 서버 흉내. `/echo?delayMs=&sizeBytes=&status=&close=` 로 HTTP 레벨만 제어한다.
- **netem** — RTT. toxiproxy 의 latency toxic 은 핸드셰이크를 못 늦춰서 이쪽으로 건다.
- **toxiproxy** — TCP 레벨 장애. 기본 경로 밖이고, 9번(말없이 끊기는 커넥션)에서만 경로에 낀다.

## 준비

```bash
./gradlew build -x test
./scripts/gen-keystore.sh          # https 실험용 자체서명 인증서
cd docker && docker-compose up -d
```

## 실행

```bash
# 풀 사이즈 / 재사용 여부를 바꿔가며 부하 (설명, maxTotal, maxPerRoute, close)
./scripts/run-case.sh "풀 50" 50 50 false
SIZE_BYTES=102400 ./scripts/run-case.sh "100KB" 50 50 false
UPSTREAM_BASE_URL=https://upstream-tls:8443 ./scripts/run-case.sh "https" 50 50 false

# 느린 업스트림이 무관한 API 를 잡아먹는지 (설명, 풀, connectionRequestTimeout)
./scripts/run-bulkhead.sh "CRT 60s" 50 60000

# 말없이 끊긴 커넥션 (validateAfterInactivity, 재시도, idle 초)
./scripts/run-stale.sh -1 false 0.3

# 풀이 센 값 vs 커널이 본 소켓 상태
./scripts/pool-stat.sh
```

## 주의

`tc netem` 의 qdisc 는 컨테이너 netns 에 붙어 있어서 컨테이너가 재생성되면 사라진다.
게다가 compose 는 매번 현재 셸 환경으로 서비스 정의를 다시 계산하므로,
`caller` 만 다시 만들려고 해도 의존 서비스인 `upstream` 까지 기본값으로 되돌려 만든다.
그래서 `run-case.sh` 는 매 회차 netem 을 다시 걸고 `connect` 시간으로 검증한 뒤 결과에 같이 찍는다.
