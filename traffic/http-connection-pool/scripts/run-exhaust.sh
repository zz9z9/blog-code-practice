#!/usr/bin/env bash
# 사용법: run-exhaust.sh <port|fd>
#
# 풀 상한이 없을 때 뭐가 먼저 바닥나는지 본다. 실제 한계까지 가려면 오래 걸리므로
# caller 컨테이너의 한계를 좁혀서 같은 상황을 빨리 만든다.
#   port — ephemeral port 를 500개로 줄이고, 클라이언트가 커넥션을 버리게 해서 TIME_WAIT 을 쌓는다
#   fd   — 열 수 있는 파일 수를 256개로 줄이고, 느린 업스트림에 상한 없는 풀로 붙는다
set -e
cd "$(dirname "$0")/.."
KIND="$1"
case "$KIND" in
  port) export PORT_RANGE="32768 33267" NOFILE=1048576 \
               POOL_MAX_TOTAL=10000 POOL_MAX_PER_ROUTE=10000 POOL_TIME_TO_LIVE_MS=0 \
               DELAY=50 VUS=50 ;;
  fd)   export PORT_RANGE="32768 60999" NOFILE=256 \
               POOL_MAX_TOTAL=10000 POOL_MAX_PER_ROUTE=10000 POOL_TIME_TO_LIVE_MS=-1 \
               DELAY=3000 VUS=200 ;;
esac
export POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_KEEP_ALIVE_MS=-1 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_RETRY_ENABLED=false \
       POOL_RESPONSE_TIMEOUT_MS=20000 POOL_SOCKET_TIMEOUT_MS=20000 \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 CALLER_TOMCAT_THREADS_MAX=200
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
echo "  한계: 포트=$(docker exec docker_caller_1 cat /proc/sys/net/ipv4/ip_local_port_range | tr '\t' '-') nofile=$(docker exec docker_caller_1 sh -c 'ulimit -n')"

N=$(docker logs docker_caller_1 2>&1 | wc -l)
docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS="$VUS" -e DURATION=30s -e DELAY_MS="$DELAY" -e CLOSE=false -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_ex 2>&1
LOG=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)))

REQ=$(grep -E "^ *http_reqs" /tmp/_ex | sed -E 's/.*: ([0-9]+) .*/\1/')
FAIL=$(grep -E "^ *http_req_failed" /tmp/_ex | sed -E 's/.*: ([0-9.]+%).*✓ ([0-9]+).*/\1 (\2건)/')
echo "  요청 $REQ, 실패 $FAIL"
# 스택트레이스에 같은 문구가 여러 번 나오므로 로그 줄 수가 아니라 k6 실패 수가 기준이다
echo "$LOG" | grep -oiE "Cannot assign requested address|Too many open files|Address already in use|Connection refused|No buffer space" \
  | sort | uniq -c | sed 's/^/  /' || echo "  (해당 에러 없음)"
