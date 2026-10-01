#!/usr/bin/env bash
# 사용법: run-vanish.sh
#
# 풀에서 커넥션이 사라지는 경우를 "서버가 알려주고 닫는" 쪽과 "말없이 끊기는" 쪽으로 갈라 본다.
#   A. 응답에 Connection: close              -> 알려준다. 풀도 같이 버린다 (게이지와 소켓이 일치)
#   B. 서버가 keep-alive 를 안 씀            -> 알려준다. 매 응답에 Connection: close 가 붙는다
#   C. 중간 장비가 말없이 끊음               -> 안 알려준다. 게이지는 1 인데 소켓은 CLOSE_WAIT
# 셋 다 커넥션 1개로 "만들고 -> 끊고 -> 다시 쏜다" 를 돌린다. 부하 생성기는 안 쓴다.
# B 는 업스트림을 다시 띄워야 해서 마지막에 돌린다 (출력은 A, C, B 순).
set -e
cd "$(dirname "$0")/.."
export POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_RETRY_ENABLED=false \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       UPSTREAM_BASE_URL=http://toxiproxy:8666 \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
up() { (cd docker && docker-compose up -d --force-recreate "$@" >/dev/null 2>&1); }
health() { for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done; }
up caller upstream toxiproxy
health

sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:21DA\$/ {n++} END {print n+0}' /proc/net/tcp"; }  # 8666 = 21DA
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

probe() {   # <라벨> — 끊긴 직후 상태를 찍고, 그 커넥션을 쓸 차례의 요청 결과까지 찍는다
  STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  CODE=$(curl -s -o /dev/null -m 20 -w '%{http_code}' http://localhost:9080/call)
  ERR=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "NoHttpResponseException|Connection reset|SocketException" | head -1)
  printf '%-32s | 끊긴 뒤: %-44s | 다음 요청 HTTP %-3s | %s\n' "$1" "$STATE" "$CODE" "${ERR:-예외없음}"
}

# A. 서버가 이 응답만 close 로 닫는다 (EchoController 가 Connection: close 를 붙인다)
curl -s -o /dev/null 'http://localhost:9080/call?close=true'
sleep 0.3
probe "A. 응답에 Connection: close"

# C. 중간 장비가 말없이 끊는다
curl -s -o /dev/null http://localhost:9080/call                                                 # 풀에 커넥션 1개
curl -s -X POST -d '{"enabled":false}' http://localhost:8474/proxies/upstream_http >/dev/null   # 통보 없이 끊는다
curl -s -X POST -d '{"enabled":true}'  http://localhost:8474/proxies/upstream_http >/dev/null
sleep 0.3                                                                                       # 검증 주기 2초 안쪽
probe "C. 말없이 끊김 (idle 0.3s)"

# B. 서버가 keep-alive 자체를 안 쓴다 (max-keep-alive-requests=1 -> 매 응답에 Connection: close)
export MAX_KEEP_ALIVE_REQUESTS=1
up upstream
sleep 3
up caller        # 풀을 비우고 시작한다
health
echo "--- 응답 헤더 (max-keep-alive-requests=1)"
docker run --rm --network docker_default pool-lab-net sh -c \
  "curl -s -o /dev/null -D - -H 'Connection: keep-alive' http://upstream:8080/echo" | grep -iE '^(connection|keep-alive)'
curl -s -o /dev/null http://localhost:9080/call   # close 파라미터 없이 평범한 요청
sleep 0.3
probe "B. 서버가 keep-alive 를 안 씀"
