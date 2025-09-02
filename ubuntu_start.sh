#!/usr/bin/env bash
# Ubuntu 초기 셋업 스크립트
# 기능: Netplan 정적 IP 설정(172.16.0.x/16, GW 172.16.0.1, DNS 1.1.1.1),
#       필수 패키지 설치(net-tools, vim, openssh-server),
#       vim/alias 설정, 타임존, UFW, 약간의 안전한 sysctl 튜닝

set -euo pipefail

# --------- 기본 변수 (필요시 아래만 바꿔도 됨) ---------
PREFIX="16"                      # 255.255.0.0
GATEWAY="172.16.0.1"
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="8.8.8.8"
NETPLAN_FILE="/etc/netplan/01-static.yaml"
TIMEZONE="Asia/Seoul"
# ------------------------------------------------------

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
  echo "[ERR] root로 실행해야 합니다: sudo $0 <172.16.0.x>"
  exit 1
fi

# 원하는 IP 받기
if [[ ${1-} ]]; then
  STATIC_IP="$1"
else
  read -rp "설정할 IP (예: 172.16.0.50): " STATIC_IP
fi

# 아주 간단한 유효성 체크
if [[ ! $STATIC_IP =~ ^172\.16\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "[ERR] 172.16.0.x 형식의 IP를 입력하세요. 입력값: $STATIC_IP"
  exit 1
fi

# 기본 NIC 추출 (외부로 나갈 기본 경로 기준)
IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
if [[ -z "${IFACE}" ]]; then
  # 플랜B: UP 상태 NIC 중 첫 번째
  IFACE="$(ip -o link show | awk -F': ' '$3 ~ /state UP/ {print $2; exit}')"
fi
if [[ -z "${IFACE}" ]]; then
  echo "[ERR] 활성 네트워크 인터페이스를 찾지 못했습니다. 수동으로 수정 후 재실행하세요."
  exit 1
fi
echo "[INFO] 사용 인터페이스: ${IFACE}"

# 기존 netplan 백업
mkdir -p /etc/netplan/backup
ts="$(date +%Y%m%d-%H%M%S)"
if compgen -G "/etc/netplan/*.yaml" > /dev/null; then
  cp /etc/netplan/*.yaml "/etc/netplan/backup/${ts}." 2>/dev/null || true
fi

# Netplan 정적 IP 설정 쓰기
cat > "${NETPLAN_FILE}" <<EOF
# 작성: init-ubuntu.sh (${ts})
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${STATIC_IP}/${PREFIX}]
      routes:
        - to: 0.0.0.0/0
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS_PRIMARY}, ${DNS_SECONDARY}]
EOF

echo "[INFO] Netplan 적용 중..."
netplan apply || { echo "[ERR] netplan apply 실패"; exit 1; }

# 타임존 설정
timedatectl set-timezone "${TIMEZONE}" || true

# 패키지 인덱스/업데이트
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y net-tools vim openssh-server curl git bash-completion

# SSH 서버 활성화
systemctl enable --now ssh

# UFW(OpenSSH 허용 후 활성화) - 로컬 환경이면 편리
if command -v ufw >/dev/null 2>&1; then
  echo "[INFO] UFW 감지됨."
else
  apt-get install -y ufw
fi
ufw allow OpenSSH >/dev/null 2>&1 || true
yes | ufw enable >/dev/null 2>&1 || true

# 사용자 홈 결정(스크립트를 sudo로 돌렸다면 원 사용자에 적용)
apply_shell_vim() {
  local user_home="$1"
  local user_name="$2"

  # ~/.bashrc에 alias 추가 (중복 방지)
  if [[ -f "${user_home}/.bashrc" ]]; then
    if ! grep -q "alias vi='vim'" "${user_home}/.bashrc"; then
      echo "alias vi='vim'" >> "${user_home}/.bashrc"
    fi
    # 편의: ll/ls 컬러/프롬프트 살짝
    if ! grep -q "alias ll='ls -alF'" "${user_home}/.bashrc"; then
      {
        echo "alias ll='ls -alF'"
        echo "alias la='ls -A'"
        echo "alias l='ls -CF'"
      } >> "${user_home}/.bashrc"
    fi
    chown "${user_name}:${user_name}" "${user_home}/.bashrc" 2>/dev/null || true
  fi

  # ~/.vimrc 기본 설정(요청 + 추천 옵션)
  # 요청: set ai si ci bg=dark
  # 추천: number, relativenumber, expandtab, ts/sw, clipboard, mouse, encoding, ruler, wildmenu, incsearch, hlsearch, ignorecase/smartcase, undofile
  cat > "${user_home}/.vimrc" <<'VIMRC'
" --- 기본 편집기 설정 ---
set nocompatible
syntax on
set termguicolors

" 요청 옵션
set ai          " autoindent
set si          " smartindent
set cindent     " ci와 동일 개념 (코드 인덴트)
set bg=dark

" 가독/편의
set number
set relativenumber
set ruler
set showcmd
set wildmenu

" 검색
set incsearch
set hlsearch
set ignorecase
set smartcase

" 탭/스페이스
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set smarttab

" 인코딩
set encoding=utf-8
set fileencodings=utf-8,euc-kr,cp949,latin1

" 마우스/클립보드
set mouse=a
set clipboard=unnamedplus

" 기타
set backspace=indent,eol,start
set nowrap
set undofile
set updatetime=300
VIMRC
  chown "${user_name}:${user_name}" "${user_home}/.vimrc" 2>/dev/null || true
}

# 대상 사용자들: root + sudo 호출자
apply_shell_vim "/root" "root"
if [[ -n "${SUDO_USER-}" && "${SUDO_USER}" != "root" ]]; then
  user_home="$(eval echo "~${SUDO_USER}")"
  if [[ -d "${user_home}" ]]; then
    apply_shell_vim "${user_home}" "${SUDO_USER}"
  fi
fi

# 약한(안전한) 기본 sysctl 튜닝: 별도 파일로 적용
SYSCTL_FILE="/etc/sysctl.d/99-tuning.conf"
cat > "${SYSCTL_FILE}" <<'SYSCTL'
# 작성: init-ubuntu.sh - 보수적/안전한 기본값
fs.inotify.max_user_watches=524288
vm.swappiness=10
net.ipv4.tcp_syncookies=1
SYSCTL
sysctl --system >/dev/null 2>&1 || true

# bash-completion 로드(전역)
if [[ -f /etc/bash_completion ]]; then
  for rc in /root/.bashrc $( [[ -n "${SUDO_USER-}" && "${SUDO_USER}" != "root" ]] && eval echo "~${SUDO_USER}/.bashrc" ); do
    [[ -f "$rc" ]] || continue
    if ! grep -q "bash_completion" "$rc"; then
      {
        echo ""
        echo "# bash-completion"
        echo "[ -f /etc/bash_completion ] && . /etc/bash_completion"
      } >> "$rc"
    fi
  done
fi

echo
echo "==============================================="
echo "[OK] 초기 셋업 완료!"
echo "- 인터페이스  : ${IFACE}"
echo "- IP/Prefix   : ${STATIC_IP}/${PREFIX}"
echo "- Gateway     : ${GATEWAY}"
echo "- DNS         : ${DNS_PRIMARY}, ${DNS_SECONDARY}"
echo "- Netplan     : ${NETPLAN_FILE}"
echo "- 타임존      : ${TIMEZONE}"
echo "SSH가 켜졌습니다. 방화벽(UFW)은 OpenSSH 허용 후 활성화됨."
echo "변경사항 반영을 위해 필요시 재부팅하세요: sudo reboot"
echo "==============================================="
