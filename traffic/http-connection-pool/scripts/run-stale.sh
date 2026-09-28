#!/usr/bin/env bash
# 사용법: run-stale.sh <VALIDATE_MS> <RETRY_ENABLED> <IDLE_SEC>
#
# upstream(톰캣)은 Keep-Alive: timeout=60 을 광고한다. 클라이언트는 그 말을 믿는다.
# 그런데 경로 중간의 toxiproxy 가 그보다 먼저, 아무 통보 없이 커넥션을 끊는다.
# 실제 LB·프록시가 idle timeout 으로 끊는 상황과 같은 모양이다.
set -e
cd "$(dirname "$0")/.."
VALIDATE="$1"; RETRY="$2"; IDLE="$3"
export POOL_VALIDATE_AFTER_INACTIVITY_MS="$VALIDATE" POOL_RETRY_ENABLED="$RETRY" \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       UPSTREAM_BASE_URL=http://toxiproxy:8666 \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller upstream toxiproxy >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:21DA\$/ {n++} END {print n+0}' /proc/net/tcp"; }  # 8666 = 21DA
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

curl -s -o /dev/null http://localhost:9080/call                                   # 커넥션 하나를 풀에 만든다
curl -s -X POST -d '{"enabled":false}' http://localhost:8474/proxies/upstream_http >/dev/null  # 중간 장비가 말없이 끊는다
curl -s -X POST -d '{"enabled":true}'  http://localhost:8474/proxies/upstream_http >/dev/null
sleep "$IDLE"
BEFORE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
N=$(docker logs docker_caller_1 2>&1 | wc -l)
code=$(curl -s -o /dev/null -m 20 -w '%{http_code}' http://localhost:9080/call)
err=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "NoHttpResponseException|Connection reset|SocketException" | head -1)

V=$([ "$VALIDATE" -lt 0 ] && echo "2s(기본)" || echo "$((VALIDATE/1000))s")
printf '검증=%-8s 재시도=%-5s idle=%-5s | 요청 전: %-44s | HTTP %-3s | %s\n' \
  "$V" "$RETRY" "${IDLE}s" "$BEFORE" "$code" "${err:-예외없음}"
