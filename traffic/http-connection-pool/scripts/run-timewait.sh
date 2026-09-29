#!/usr/bin/env bash
# 사용법: run-timewait.sh <CLOSER: none|server|client>
#
# 재사용을 끄는 방법이 두 가지인데, 먼저 닫는 쪽이 달라서 TIME_WAIT 이 쌓이는 자리가 다르다.
#   server — 업스트림이 Connection: close 를 붙인다 (1번에서 쓴 방법)
#   client — 풀이 빌려줄 때마다 TTL 만료로 버린다 (timeToLive=0) -> caller 가 먼저 닫는다
# 부하 중에 caller/upstream 양쪽의 TIME_WAIT 과 소켓 메모리를 같이 센다.
set -e
cd "$(dirname "$0")/.."
CLOSER="$1"
case "$CLOSER" in
  none)   CLOSE=false; TTL=-1 ;;
  server) CLOSE=true;  TTL=-1 ;;
  client) CLOSE=false; TTL=0  ;;
esac
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_KEEP_ALIVE_MS=-1 \
       POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 \
       POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS="$TTL" POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
TARGET=docker_upstream_1 ./scripts/netem.sh 20 >/dev/null 2>&1

# $4=상태(06=TIME_WAIT), 포트 1F90=8080. caller 는 remote(=$3), upstream 은 local(=$2) 이 8080 이다
tw() { docker exec "$1" sh -c \
  "awk 'NR>1 && \$4==\"06\" && \$$2 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
# sockstat 의 tw = TIME_WAIT 총계, mem = 소켓 버퍼로 잡은 페이지 수(4KB/페이지)
sockstat() { docker exec "$1" sh -c "grep '^TCP:' /proc/net/sockstat"; }

opens() { docker exec "$1" sh -c "awk '/^Tcp:/{if(h){split(h,a,\" \");split(\$0,b,\" \");for(i=1;i<=length(a);i++) if(a[i]==\"$2\") print b[i]} else h=\$0}' /proc/net/snmp"; }
A0=$(opens docker_caller_1 ActiveOpens); R0=$(opens docker_caller_1 EstabResets)

( docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e VUS=50 -e DURATION=30s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
    grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_tw 2>&1 ) &
sleep 25
C_TW=$(tw docker_caller_1 3); U_TW=$(tw docker_upstream_1 2)
C_SS=$(sockstat docker_caller_1); U_SS=$(sockstat docker_upstream_1)
wait
TPS=$(grep -E "^ *http_reqs" /tmp/_tw | sed -E 's#.* ([0-9.]+)/s.*#\1#')
REQ=$(grep -E "^ *http_reqs" /tmp/_tw | sed -E 's/.*: ([0-9]+) .*/\1/')
A1=$(opens docker_caller_1 ActiveOpens); R1=$(opens docker_caller_1 EstabResets)

printf '%-7s | 요청 %-6s TPS %-5s | 새 커넥션 %-6s RST 로 끝 %-6s | TIME_WAIT caller=%-5s upstream=%s\n' \
  "$CLOSER" "$REQ" "${TPS%.*}" "$((A1-A0))" "$((R1-R0))" "$C_TW" "$U_TW"
printf '          caller   %s\n' "$C_SS"
printf '          upstream %s\n' "$U_SS"
