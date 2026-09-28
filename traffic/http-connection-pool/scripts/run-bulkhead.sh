#!/usr/bin/env bash
# 사용법: run-bulkhead.sh "<설명>" <POOL> <CRT_MS>   (CRT_MS 음수 = 무한 대기)
set -e
cd "$(dirname "$0")/.."
DESC="$1"; POOL="$2"; CRT="$3"
export POOL_MAX_TOTAL="$POOL" POOL_MAX_PER_ROUTE="$POOL" POOL_CONNECTION_REQUEST_TIMEOUT_MS="$CRT"
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }

( docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e SLOW_VUS="${SLOW_VUS:-250}" -e DURATION=30s -e DELAY_MS="${DELAY_MS:-3000}" \
    grafana/k6:0.53.0 run --quiet /scripts/bulkhead.js > /tmp/_bh 2>&1 ) &
sleep 18
MID="threads=$(gauge '^tomcat_threads_busy') leased=$(gauge 'state="leased"') pending=$(gauge 'pool_total_pending') EST=$(sock 01)"
wait
OUT=$(cat /tmp/_bh)
m() { echo "$OUT" | grep -E "^ *$1\\.*" | sed -E "s/.*avg=([^ ]+).*p\\(95\\)=([^ ]+).*/\\1 \\2/"; }
read -r CALL_AVG CALL_P95 <<< "$(m call_duration)"
read -r LOC_AVG LOC_P95 <<< "$(m local_duration)"
FAIL=$(echo "$OUT" | grep -E "^ *call_failed" | sed -E "s/.*: ([0-9.]+%).*/\\1/")
RPS=$(echo "$OUT" | grep -E "^ *http_reqs" | sed -E "s#.* ([0-9.]+)/s.*#\\1#")
printf '%-20s | call avg=%-9s p95=%-9s | local avg=%-9s p95=%-9s | 실패=%-7s | %s\n' \
  "$DESC" "$CALL_AVG" "$CALL_P95" "$LOC_AVG" "$LOC_P95" "$FAIL" "$MID"
