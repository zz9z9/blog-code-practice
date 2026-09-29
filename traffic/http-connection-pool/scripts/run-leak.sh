#!/usr/bin/env bash
# 사용법: run-leak.sh <MODE: leaky|safe> <STATUS>
#
# 동시성 1 로 60번 순차 호출한다(부하 생성기 없이 curl 루프).
# 반납이 안 되면 동시성이 1인데도 요청 수만큼 커넥션이 늘어난다.
set -e
cd "$(dirname "$0")/.."
MODE="$1"; STATUS="$2"
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       POOL_KEEP_ALIVE_MS=-1 POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

OK=0; FIRST_FAIL=""
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' \
    "http://localhost:9080/call?delayMs=0&status=${STATUS}&mode=${MODE}")
  # 502 는 업스트림 에러를 caller 가 정상적으로 옮긴 것 -> 호출 자체는 성공
  if [ "$code" = "200" ] || [ "$code" = "502" ]; then OK=$((OK+1))
  elif [ -z "$FIRST_FAIL" ]; then FIRST_FAIL="$i"; fi
done

gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock()  { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
printf '%-6s + %-3s | 성공 %2d/60 | 첫 실패 %-6s | available=%-3s leased=%-3s | ESTABLISHED=%-3s CLOSE_WAIT=%s\n' \
  "$MODE" "$STATUS" "$OK" "${FIRST_FAIL:-없음}" \
  "$(gauge 'state="available"')" "$(gauge 'state="leased"')" "$(sock 01)" "$(sock 08)"
