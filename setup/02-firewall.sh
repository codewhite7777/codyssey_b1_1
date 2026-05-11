#!/usr/bin/env bash
# setup/02-firewall.sh — ufw 방화벽 (20022, 15034만 허용)
# 멱등: --force reset으로 초기화 후 재구성

set -euo pipefail

echo "===== [02/06] 방화벽 설정 ====="

# 1. ufw 설치 확인
if ! command -v ufw >/dev/null 2>&1; then
    echo "[INFO] ufw 설치 중..."
    sudo apt-get update -qq
    sudo apt-get install -y ufw
fi

# 2. 멱등 초기화 (기존 룰 모두 제거)
sudo ufw --force reset

# 3. 기본 정책: 인바운드 거부, 아웃바운드 허용
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 4. 필요한 포트만 허용
sudo ufw allow 20022/tcp comment 'SSH'
sudo ufw allow 15034/tcp comment 'agent-app'

# 5. 활성화 (--force로 confirm 프롬프트 우회)
sudo ufw --force enable

echo "[OK] 방화벽 설정 완료"
echo ""
echo "[검증] ufw status verbose"
sudo ufw status verbose
