#!/usr/bin/env bash
# 사용법: run-cpu.sh <http|https> <reuse|noreuse>
#
# 4번에서 TLS 핸드셰이크에 비대칭키 연산 CPU 비용이 있다는 걸 curl 로 봤다.
# 부하 중 caller/upstream 의 실제 CPU 사용량을 재서, 재사용이 그 비용을 얼마나 없애는지 본다.
# CPU 는 cgroup 의 cpuacct 누적값 증분으로 잰다(나노초). docker stats 의 순간값보다 안정적이다.
set -e
cd "$(dirname "$0")/.."
PROTO="$1"; REUSE="$2"
[ "$PROTO" = "https" ] && URL=https://upstream-tls:8443 && SRV=docker_upstream-tls_1 || { URL=http://upstream:8080; SRV=docker_upstream_1; }
[ "$REUSE" = "noreuse" ] && CLOSE=true || CLOSE=false
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_KEEP_ALIVE_MS=-1 POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 \
       POOL_TIME_TO_LIVE_MS=-1 POOL_RETRY_ENABLED=false UPSTREAM_BASE_URL="$URL" \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
# RTT 는 양쪽 업스트림에 똑같이 건다. https 쪽만 빼먹으면 TPS 비교가 어긋난다
TARGET="$SRV" VERIFY_URL="$URL/echo" ./scripts/netem.sh 20 >/dev/null 2>&1

cpu() { docker exec "$1" sh -c "cat /sys/fs/cgroup/cpuacct/cpuacct.usage"; }   # 나노초 누적

docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS=50 -e DURATION=10s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js >/dev/null 2>&1   # 워밍업

C0=$(cpu docker_caller_1); U0=$(cpu "$SRV")
docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS=50 -e DURATION=30s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_cpu 2>&1
C1=$(cpu docker_caller_1); U1=$(cpu "$SRV")

REQ=$(grep -E "^ *http_reqs" /tmp/_cpu | sed -E 's/.*: ([0-9]+) .*/\1/')
TPS=$(grep -E "^ *http_reqs" /tmp/_cpu | sed -E 's#.* ([0-9.]+)/s.*#\1#')
CD=$((C1-C0)); UD=$((U1-U0))
# 요청 1건당 CPU(마이크로초) = 증분 / 요청 수
printf '%-5s %-8s | 요청 %-6s TPS %-5s | CPU 총 caller=%-7sms upstream=%-7sms | 요청당 caller=%-8sus upstream=%sus\n' \
  "$PROTO" "$REUSE" "$REQ" "${TPS%.*}" "$((CD/1000000))" "$((UD/1000000))" \
  "$(echo "scale=1; $CD/1000/$REQ" | bc)" "$(echo "scale=1; $UD/1000/$REQ" | bc)"
