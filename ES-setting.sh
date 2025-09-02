#!/bin/bash
#준비중
echo "##### 기존 엘라스틱 서치 제거 #####"
sudo systemctl stop elasticsearch 2>/dev/null || true
sudo systemctl disable elasticsearch 2>/dev/null || true

# 9200/9300 포트가 비었는지 확인
sudo ss -lntp | grep -E '(:9200|:9300)' || echo "ports free"

echo "##### Elasitcsearch 설치 #####"
cd ~
curl -LO https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.15.5-linux-x86_64.tar.gz
tar xzf elasticsearch-8.15.5-linux-x86_64.tar.gz
mv elasticsearch-8.15.5 es-8.15.5
cd es-8.15.5
# 데이터/로그 디렉토리는 tarball 기본 경로 내부를 사용(권한 이슈 최소화)
mkdir -p data logs

https://www.elastic.co/downloads/past-releases/kibana-8-15-5

https://artifacts.elastic.co/downloads/logstash/logstash-8.15.5-linux-aarch64.tar.gz