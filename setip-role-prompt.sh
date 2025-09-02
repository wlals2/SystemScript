cat > ./setup-role-prompt.sh <<'BASH'
#!/usr/bin/env bash
# 역할별 프롬프트(ROLE + IP + user@host + pwd) 전역 적용
# - 로그인 셸: /etc/profile.d/*.sh 로 적용
# - 비로그인 셸: /etc/bash.bashrc.d/ 또는 /etc/bash.bashrc 에서도 적용되도록 연결
set -euo pipefail

# sudo
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    echo "root 권한이 필요합니다. sudo 로 다시 실행하세요."; exit 1
  fi
else SUDO=""; fi

ROLE_FILE="/etc/profile.d/00-role.sh"
PS1_FILE="/etc/profile.d/99-ps1-role.sh"
BASHRC_D="/etc/bash.bashrc.d"
BASHRC_LINK="$BASHRC_D/99-ps1-role.bashrc"
BASHRC_SYS="/etc/bash.bashrc"

echo "역할을 선택하세요:"
echo "  1) ES"
echo "  2) LOGSTASH"
echo "  3) KIBANA"
echo "  4) WEB"
echo "  5) PROMETHEUS"
echo "  6) GRAFANA"
read -rp "번호 입력: " NUM

case "$NUM" in
  1) ROLE="ES" ;;
  2) ROLE="LOGSTASH" ;;
  3) ROLE="KIBANA" ;;
  4) ROLE="WEB" ;;
  5) ROLE="PROMETHEUS" ;;
  6) ROLE="GRAFANA" ;;
  *) echo "유효하지 않은 입력입니다."; exit 1 ;;
esac

echo "-> SERVER_ROLE='${ROLE}' 로 설정합니다."

# 1) ROLE 환경변수 (전역)
$SUDO tee "$ROLE_FILE" >/dev/null <<EOF
# 자동 생성: 서버 역할/프롬프트용 환경변수
export SERVER_ROLE="${ROLE}"
# 필요 시 고정 IP 지정 (주석 해제)
# export PROMPT_IP="192.168.1.x"
EOF
$SUDO chmod 0644 "$ROLE_FILE"

# 2) PS1 스크립트(전역) - 로그인/비로그인 공통 내용
$SUDO tee "$PS1_FILE" >/dev/null <<'EOF'
# 자동 생성: 역할/아이피 표시 컬러 프롬프트
# 인터랙티브 셸만 적용
case $- in *i*) ;; *) return ;; esac
[ -n "$BASH_VERSION" ] || return

# IP 계산: PROMPT_IP > 기본 경로 src IP > hostname -I 첫번째 > N/A
if [ -n "${PROMPT_IP:-}" ]; then
  __PROMPT_IP="$PROMPT_IP"
else
  if command -v ip >/dev/null 2>&1; then
    __PROMPT_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  if [ -z "${__PROMPT_IP:-}" ] && command -v hostname >/dev/null 2>&1; then
    __PROMPT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  : "${__PROMPT_IP:=N/A}"
fi
export __PROMPT_IP

# 역할별 색상
case "${SERVER_ROLE:-HOST}" in
  ES)            ROLE_COLOR='\[\e[1;31m\]' ;; # 빨강
  LOGSTASH)      ROLE_COLOR='\[\e[1;33m\]' ;; # 노랑
  KIBANA)        ROLE_COLOR='\[\e[1;35m\]' ;; # 자주
  WEB|WEBSERVER) ROLE_COLOR='\[\e[1;32m\]' ;; # 초록
  PROMETHEUS)    ROLE_COLOR='\[\e[1;36m\]' ;; # 시안
  GRAFANA)       ROLE_COLOR='\[\e[1;34m\]' ;; # 파랑
  *)             ROLE_COLOR='\[\e[1;34m\]' ;; # 기본 파랑
esac

# [ROLE IP user@host /full/path]$
PS1="\[\e[0;90m\][${ROLE_COLOR}\${SERVER_ROLE:-HOST}\[\e[0m\] \[\e[1;90m\]\${__PROMPT_IP}\[\e[0m\] \u@\h \w]\\$ "
export PS1
EOF
$SUDO chmod 0644 "$PS1_FILE"

# 3) 비로그인 셸에도 보장 적용
# 3-1) /etc/bash.bashrc.d 가 있으면 여기서 profile.d 스크립트 불러오게 함
if [ -d "$BASHRC_D" ]; then
  $SUDO tee "$BASHRC_LINK" >/dev/null <<EOF
# 자동 생성: 비로그인 인터랙티브 셸에서도 역할 프롬프트 적용
# /etc/profile.d 스크립트 재사용
[ -r "$PS1_FILE" ] && . "$PS1_FILE"
EOF
  $SUDO chmod 0644 "$BASHRC_LINK"
else
  # 3-2) fallback: /etc/bash.bashrc 에 source 라인 보강(중복 방지)
  if ! $SUDO grep -qF "$PS1_FILE" "$BASHRC_SYS"; then
    $SUDO tee -a "$BASHRC_SYS" >/dev/null <<EOF

# 자동 추가: 역할 프롬프트(비로그인 셸용)
if [ -f "$PS1_FILE" ]; then
  . "$PS1_FILE"
fi
EOF
  fi
fi

echo
echo "✅ 설정 완료 (재부팅/재접속/신규 셸 모두 유지)"
echo "적용 즉시 확인:  exec \$SHELL -l   또는   새 SSH 접속"
echo "역할 변경:       스크립트 다시 실행하여 번호만 선택"
echo "IP 고정:         /etc/profile.d/00-role.sh 의 PROMPT_IP 주석 해제/수정"
BASH

chmod +x ./setup-role-prompt.sh
sudo ./setup-role-prompt.sh
