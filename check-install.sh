#!/usr/bin/env bash
# 특정 프로그램 설치 방식/기록을 확인하는 스크립트
# 사용법:  명령어 뒤 서비스 명을 적는다.
# ex) ./check-install.sh grafana

set -euo pipefail

PKG="${1:-}"
if [[ -z "$PKG" ]]; then
  echo "Usage: $0 <package-or-program-name>"
  exit 1
fi

echo "### [1] Running process"
pgrep -a "$PKG" || echo "no running process"

echo -e "\n### [2] systemd units"
systemctl list-unit-files | grep -i "$PKG" || echo "no unit file"
systemctl status "${PKG}-server" --no-pager -l 2>/dev/null || true

echo -e "\n### [3] APT packages"
dpkg -l | grep -i "$PKG" || echo "no apt package found"
apt-cache policy "$PKG" 2>/dev/null | sed -n '1,20p' || true

echo -e "\n### [4] Snap packages"
command -v snap >/dev/null 2>&1 && (snap list | grep -i "$PKG" || echo "no snap package") || echo "snap not installed"

echo -e "\n### [5] Docker/Podman containers"
command -v docker >/dev/null 2>&1 && (docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i "$PKG" || true) || echo "docker not installed"
command -v podman >/dev/null 2>&1 && (podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i "$PKG" || true) || echo "podman not installed"

echo -e "\n### [6] Binary paths"
command -v "$PKG" >/dev/null 2>&1 && (echo "binary path: $(command -v $PKG)") || echo "binary not in PATH"
command -v "${PKG}-server" >/dev/null 2>&1 && (echo "binary path: $(command -v ${PKG}-server)") || true

echo -e "\n### [7] APT/dpkg install history"
zgrep -h -i "$PKG" /var/log/apt/history.log* /var/log/dpkg.log* 2>/dev/null | tail -n 40 || echo "no apt/dpkg history found"

echo -e "\n### [8] journalctl (system logs, last 40 lines)"
journalctl _COMM=apt-get -u apt-daily.service -n 40 | grep -i "$PKG" || echo "no apt-get journal logs"
