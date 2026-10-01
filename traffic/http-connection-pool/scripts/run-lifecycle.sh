#!/usr/bin/env bash
# 사용법: run-lifecycle.sh
#
# 풀이 커넥션을 "언제 만들고 / 언제 반납받고 / 반납 후 어떻게 하는지" 를 단계별로 찍는다.
# 동시성을 내가 정해야 하므로 부하 생성기 대신 curl 을 직접 띄운다.
#   available  = 풀에 놀고 있는 PoolEntry, leased = 빌려준 PoolEntry
#   ESTABLISHED= caller -> upstream 살아 있는 소켓 (/proc/net/tcp)
#   새 소켓    = /proc/net/snmp ActiveOpens 증분. 괄호는 그 단계에서 새로 만든 수
set -e
cd "$(dirname "$0")/.."
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       POOL_KEEP_ALIVE_MS=-1 POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 \
       MAX_KEEP_ALIVE_REQUESTS=1000 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock()  { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
opens() { docker exec docker_caller_1 sh -c "awk '/^Tcp:/{if(h){split(h,a,\" \");split(\$0,b,\" \");for(i=1;i<=length(a);i++) if(a[i]==\"ActiveOpens\") print b[i]} else h=\$0}' /proc/net/snmp"; }

A0=$(opens); PREV=0
show() {
  local now=$(( $(opens) - A0 ))
  printf '%-30s | available=%-3s leased=%-3s | ESTABLISHED=%-3s CLOSE_WAIT=%-3s | 새 소켓 %-3s (+%s)\n' \
    "$1" "$(gauge 'state="available"')" "$(gauge 'state="leased"')" "$(sock 01)" "$(sock 08)" "$now" "$((now-PREV))"
  PREV=$now
}
# call <delayMs> <close> <mode> <sizeBytes>
call() { curl -s -o /dev/null -m 30 \
  "http://localhost:9080/call?delayMs=${1:-0}&close=${2:-false}&mode=${3:-safe}&sizeBytes=${4:-0}"; }
loop() { local n="$1"; shift; for i in $(seq 1 "$n"); do call "$@"; done; }

echo "# 1) 풀을 미리 채워두는가"
show "기동 직후 — 요청 0회"
call;        show "요청 1회"
loop 19;     show "순차 20회 (동시성 1)"

echo
echo "# 2) 동시성이 오르면 / 내려가면"
for i in $(seq 1 10); do call 1000 & done; sleep 0.6; show "동시 10 — 처리 중"
wait;                                                 show "동시 10 — 끝난 뒤"
for i in $(seq 1 3);  do call 1000 & done; sleep 0.6; show "동시 3 — 처리 중"
wait;                                                 show "동시 3 — 끝난 뒤"

echo
echo "# 3) 반납 시점"
call 3000 & sleep 1; show "응답 대기 중 (delayMs=3000)"
wait;                show "응답 다 읽은 뒤"

echo
echo "# 4) 서버가 Connection: close 를 붙이면"
call 0 true;      show "close 응답 1회"
loop 19 0 true;   show "close 순차 20회"
call;             show "다시 keep-alive 1회"

echo
echo "# 5) 응답을 닫기만 하고 본문을 안 읽으면 (100KB 본문)"
loop 20 0 false safe      102400; show "safe 순차 20회"
loop 20 0 false closeonly  102400; show "closeonly 순차 20회"
loop 20 0 false safe      102400; show "다시 safe 순차 20회"

echo
echo "# 6) 서버가 알려준 keep-alive 가 지나면 (upstream 재기동: timeout=5s)"
export KEEP_ALIVE_TIMEOUT=5000
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
A0=$(opens); PREV=0
for i in $(seq 1 10); do call 1000 & done; wait;  show "동시 10 — 끝난 뒤"
sleep 8;                                          show "8초 유휴 (서버 timeout=5s)"
call;                                             show "그 뒤 요청 1회"
