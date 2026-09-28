#!/usr/bin/env bash
# 4번(https) 실험용 자체서명 인증서. 실습 전용이라 저장소에 넣지 않는다.
set -e
cd "$(dirname "$0")/../docker"
keytool -genkeypair -alias upstream -keyalg RSA -keysize 2048 -validity 3650 \
  -dname "CN=upstream, OU=lab, O=blogcode, C=KR" \
  -keystore keystore.p12 -storetype PKCS12 -storepass changeit -keypass changeit \
  -ext "SAN=dns:upstream-tls,dns:upstream,dns:localhost"
echo "생성 완료: $(pwd)/keystore.p12"
