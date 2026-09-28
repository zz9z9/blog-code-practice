#!/usr/bin/env bash
# 풀이 센 값과 커널이 본 소켓 상태를 나란히 찍는다.
# temurin 이미지에 ss/netstat 이 없어 /proc/net/tcp 를 직접 읽는다.
#   $2 local, $3 remote, $4 상태 (01=ESTABLISHED, 06=TIME_WAIT, 08=CLOSE_WAIT)
# caller 입장에서 remote 포트가 8080(1F90) 인 것 = caller -> upstream 커넥션
gauge() {
  curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'
}
sock() {
  docker exec docker_caller_1 sh -c \
    "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"
}
printf '풀: available=%-4s leased=%-4s pending=%-4s | 커널(caller->upstream): ESTABLISHED=%-4s CLOSE_WAIT=%-4s TIME_WAIT=%s\n' \
  "$(gauge 'state="available"')" "$(gauge 'state="leased"')" "$(gauge 'pool_total_pending')" \
  "$(sock 01)" "$(sock 08)" "$(sock 06)"
