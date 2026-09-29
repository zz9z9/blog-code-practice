#!/usr/bin/env bash
# 사용법: run-keepalive.sh <KEEP_ALIVE_MS> <VALIDATE_MS> <IDLE_SEC>
#
# 커넥션을 풀에 얼마나 둘지는 ConnectionKeepAliveStrategy 가 응답마다 정한다.
# 기본 전략(KEEP_ALIVE_MS < 0)은 서버의 Keep-Alive: timeout=N 을 그대로 따르고,
# 값을 주면 서버가 뭐라 하든 그 값으로 고정한다.
# 톰캣은 5초(=timeout=5)로 알려주게 두고, 유휴 시간을 그 앞뒤로 둬서 갈리는 지점을 본다.
set -e
cd "$(dirname "$0")/.."
KEEP_ALIVE="$1"; VALIDATE="$2"; IDLE="$3"
export POOL_KEEP_ALIVE_MS="$KEEP_ALIVE" POOL_VALIDATE_AFTER_INACTIVITY_MS="$VALIDATE" \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_RETRY_ENABLED=false POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       UPSTREAM_BASE_URL=http://upstream:8080 LOGGING_LEVEL_ORG_APACHE_HC=DEBUG \
       KEEP_ALIVE_TIMEOUT=5000 MAX_KEEP_ALIVE_REQUESTS=100 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

# 톰캣이 실제로 뭐라고 알려주는지 먼저 확인한다 (클라가 Connection: keep-alive 를 보내야 붙는다)
ADV=$(docker exec docker_caller_1 sh -c \
  "curl -s -D - -o /dev/null -H 'Connection: keep-alive' http://upstream:8080/echo" \
  | tr -d '\r' | grep -i '^Keep-Alive:' || echo "(알려주지 않음)")

N=$(docker logs docker_caller_1 2>&1 | wc -l)
BODY=$(curl -s -m 40 "http://localhost:9080/keepalive?idleMs=$((IDLE*1000))")
DUR=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "can be kept alive (for [0-9]+ [A-Z]+|indefinitely)" | head -1)

K=$([ "$KEEP_ALIVE" -lt 0 ] && echo "기본(서버따름)" || echo "$((KEEP_ALIVE/1000))s고정")
V=$([ "$VALIDATE" -lt 0 ] && echo "2s(기본)" || echo "$((VALIDATE/1000))s")
printf '전략=%-14s 검증=%-8s idle=%-4s | %-42s | %s\n' "$K" "$V" "${IDLE}s" "${DUR:-로그없음}" "$BODY"
echo "  ($ADV)"
