#!/usr/bin/env bash
# 사용법: run-dead.sh
#
# "서버는 끊었는데 클라이언트는 모르는" 상황을 원인별로 만든다. 중간 장비(toxiproxy)는 안 쓴다.
#   D1. 배포 중 — 업스트림을 재기동하는 동안 0.2초 간격으로 계속 때린다. 검증 2초(기본)
#   D2. 같은 부하에 검증만 매 lease 마다 (validateAfterInactivity=0)
#         두 실패를 예외로 구분한다:
#           ConnectException     = 서버가 없던 동안의 정직한 실패
#           NoHttpResponseException = 서버가 돌아온 뒤 죽은 커넥션을 집어서 난 실패 (stale)
#   D3. 설정 어긋남 — 서버가 Keep-Alive 헤더를 안 주면 클라는 기본 3분을 잡는데 서버는 1초에 끊는다
#   D4. 네트워크 단절(blackhole) — FIN 도 RST 도 없다. 검증을 매번 해도 못 걸러낸다
set -e
cd "$(dirname "$0")/.."
PORT_HEX=1F90   # upstream 8080

boot() {   # <validate_ms> <keep_alive_timeout_ms> <keep_alive_header>
  export POOL_VALIDATE_AFTER_INACTIVITY_MS="$1" KEEP_ALIVE_TIMEOUT="$2" KEEP_ALIVE_RESPONSE_HEADER="$3" \
         POOL_RETRY_ENABLED=false POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 \
         POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_RESPONSE_TIMEOUT_MS=10000 \
         UPSTREAM_BASE_URL=http://upstream:8080 MAX_KEEP_ALIVE_REQUESTS=100 \
         LOGGING_LEVEL_ORG_APACHE_HC=DEBUG
  (cd docker && docker-compose up -d --force-recreate upstream caller >/dev/null 2>&1)
  for i in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
    sleep 1
  done
}
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:$PORT_HEX\$/ {n++} END {print n+0}' /proc/net/tcp"; }
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
errs() { docker logs docker_caller_1 2>&1 | tail -n +$((1+$1)) | grep -oE "NoHttpResponseException|SocketTimeoutException|HttpHostConnectException|ConnectException|Connection reset" | sort | uniq -c | tr '\n' ' '; }

# ── D1/D2. 배포 중에 계속 때린다
deploy_case() {   # <라벨> <validate_ms>
  boot "$2" 60000 true
  curl -s -o /dev/null http://localhost:9080/call          # 풀에 커넥션 1개
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  ( sleep 2; cd docker && docker-compose restart upstream >/dev/null 2>&1 ) &
  OK=0; BAD=0
  for i in $(seq 1 120); do                                # 0.2초 * 120 = 약 24초
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:9080/call)
    [ "$code" = "200" ] && OK=$((OK+1)) || BAD=$((BAD+1))
    sleep 0.2
  done
  wait
  printf '%-28s | 성공 %-4s 실패 %-4s | %s\n' "$1" "$OK" "$BAD" "$(errs "$N")"
}
deploy_case "D1. 배포, 검증 2초(기본)" -1
deploy_case "D2. 배포, 검증 매번(0)"    0

# ── D3/D4. 단발로 상태까지 본다
probe() {   # <라벨>
  STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  T0=$(date +%s)
  CODE=$(curl -s -o /dev/null -m 30 -w '%{http_code}' http://localhost:9080/call)
  T=$(( $(date +%s) - T0 ))
  LIFE=$(docker logs docker_caller_1 2>&1 | grep -o "can be kept alive .*" | head -1)
  printf '%-28s | 클라가 잡은 수명: %-26s | 끊긴 뒤: %-42s | 다음 요청 HTTP %-3s (%ss) | %s\n' \
    "$1" "$LIFE" "$STATE" "$CODE" "$T" "$(errs "$N")"
}

# D3. 서버가 Keep-Alive 헤더를 안 준다 -> 클라는 기본 3분, 서버는 1초에 끊는다
# 상태를 읽는 데 1초 가까이 걸리므로 상태 보기와 요청 쏘기를 따로 돌린다.
# (상태를 읽는 동안에는 lease 가 없으니 검증도 안 돈다 — 유휴가 길어져도 상관없다)
boot -1 1000 false
curl -s -o /dev/null http://localhost:9080/call            # 커넥션 하나
sleep 1.5                                                  # 서버는 1초에 끊는다
STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
LIFE=$(docker logs docker_caller_1 2>&1 | grep -o "can be kept alive .*" | head -1)

boot -1 1000 false                                         # 소켓을 깨끗이 비우고 요청만 쏜다
curl -s -o /dev/null http://localhost:9080/call
N=$(docker logs docker_caller_1 2>&1 | wc -l)
sleep 1.5                                                  # 서버는 끊었고 클라 검증 주기 2초는 아직 안 됐다
CODE=$(curl -s -o /dev/null -m 30 -w '%{http_code}' http://localhost:9080/call)
printf '%-28s | 클라가 잡은 수명: %-26s | 끊긴 뒤: %-42s | 다음 요청 HTTP %-3s | %s\n' \
  "D3. 헤더 없음, 검증 2초(기본)" "$LIFE" "$STATE" "$CODE" "$(errs "$N")"

# D4. 네트워크 단절 — FIN 도 RST 도 안 온다
boot 0 60000 true
curl -s -o /dev/null http://localhost:9080/call
docker network disconnect docker_default docker_upstream_1
sleep 0.3
probe "D4. 네트워크 단절, 검증 매번(0)"
docker network connect docker_default docker_upstream_1 >/dev/null 2>&1 || true
