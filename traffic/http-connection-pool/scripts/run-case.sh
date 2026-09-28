#!/usr/bin/env bash
# 사용법: run-case.sh "<설명>" <MAX_TOTAL> <MAX_PER_ROUTE> <CLOSE> [DELAY_MS] [VUS]
#   MAX_TOTAL / MAX_PER_ROUTE 에 0 = "설정하지 않음" -> httpclient5 기본값
#   env: NETEM_MS(기본 20), SIZE_BYTES(기본 0), UPSTREAM_BASE_URL
set -e
cd "$(dirname "$0")/.."
DESC="$1"; TOTAL="$2"; PER_ROUTE="$3"; CLOSE="$4"; DELAY="${5:-50}"; VUS="${6:-50}"
NET=docker_default
D="${NETEM_MS:-20}"

export POOL_MAX_TOTAL="$TOTAL" POOL_MAX_PER_ROUTE="$PER_ROUTE"
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

# qdisc 는 컨테이너 netns 에 붙어 있어 재생성 때마다 사라진다. 매 실험 전에 다시 걸고 검증한다.
TARGET=docker_upstream_1 ./scripts/netem.sh "$D" >/dev/null
if [ -n "${UPSTREAM_BASE_URL##*upstream:8080}" ] && [ -n "$UPSTREAM_BASE_URL" ]; then
  RTT=$(TARGET=docker_upstream-tls_1 VERIFY_URL=https://upstream-tls:8443/echo ./scripts/netem.sh "$D" | grep -o 'connect=[0-9.]*ms')
else
  RTT=$(TARGET=docker_upstream_1 ./scripts/netem.sh "$D" | grep -o 'connect=[0-9.]*ms')
fi
EFF=$(docker logs docker_caller_1 2>&1 | grep -o 'pool: maxTotal=[0-9]*, maxPerRoute=[0-9]*' | tail -1)

k6run() {
  docker run --rm --network "$NET" --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e VUS="$VUS" -e DURATION="$1" -e DELAY_MS="$DELAY" -e CLOSE="$CLOSE" -e MODE=safe \
    -e SIZE_BYTES="${SIZE_BYTES:-0}" \
    grafana/k6:0.53.0 run --quiet /scripts/scenario.js 2>&1
}
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

k6run 15s >/dev/null 2>&1                      # JIT warmup — 버린다
( k6run 30s > /tmp/_k6out 2>&1 ) &
sleep 15
MID="leased=$(gauge 'state="leased"') pending=$(gauge 'pool_total_pending') callerThreads=$(gauge '^tomcat_threads_busy')"
wait
OUT=$(cat /tmp/_k6out)
AVG=$(echo "$OUT" | grep -E "^ *http_req_duration" | sed -E 's/.*avg=([^ ]+).*/\1/')
TPS=$(echo "$OUT" | grep -E "^ *http_reqs" | sed -E 's#.* ([0-9.]+)/s.*#\1#')
printf '%-28s | %-34s | %-15s | %-9s | %-7s | %s\n' "$DESC" "$EFF" "$RTT" "$AVG" "${TPS%.*}" "$MID"
