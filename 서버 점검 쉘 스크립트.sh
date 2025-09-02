#!/bin/bash
# 서버 점검 쉘 스크립트
# 대체로 어떤 프로그램을 썼는지 확인. 웹서버에 따른 다른 전개 스크립트도 확인


echo "점검 시작"
echo "####################################"
echo "포트 확인"
ss -ltnp | grep :8080
echo "웹 사이트 확인"
curl -I 127.0.0.1:8080

echo "서버로 트래픽 들어오는 것을 확인"
sudo tcpdump -i any tcp port 8080 -nn