#!/bin/bash

echo "####### 설치 시작 #######"
sudo yum install java-17-amazon-corretto-devel -y
sudo dnf install git -y

echo "####### git clone #######"
rm -rf log-tracking-app
git clone https://github.com/dev-library/log-tracking-app

echo "####### start web app #######"
cd log-tracking-app
./gradlew bootRun
