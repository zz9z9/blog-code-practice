#!/usr/bin/env bash
# upstream netns 에 egress 지연을 건다.
# qdisc 는 컨테이너 netns 에 붙어 있어서 upstream 이 재생성되면 조용히 사라진다.
# 실험마다 다시 걸고, 실제로 걸렸는지 connect 시간으로 검증한다.
DELAY="${1:-20}"
docker run --rm --network container:${TARGET:-docker_upstream_1} --cap-add NET_ADMIN pool-lab-net \
  tc qdisc replace dev eth0 root netem delay "${DELAY}ms"
# 컨테이너 첫 요청은 DNS 등으로 느리게 나오므로 3회 재서 중앙값을 쓴다
docker run --rm --network docker_default pool-lab-net sh -c \
  "for i in 1 2 3; do curl -sk -o /dev/null -H 'Connection: close' -w '%{time_connect}\n' ${VERIFY_URL:-http://upstream:8080/echo}; done" \
  | sort -n | sed -n 2p | awk '{printf "RTT 검증: connect=%.1fms\n", $1*1000}'
