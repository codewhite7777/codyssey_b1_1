#!/usr/bin/env bash
# setup/05-environment.sh — 환경 변수 + 키 파일
# 멱등: 기존 AGENT_ 변수 제거 후 재추가, 키 파일은 if not exists

set -euo pipefail

AGENT_HOME="/home/agent-admin/agent-app"
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
BASH_PROFILE="/home/agent-admin/.bash_profile"

echo "===== [05/06] 환경 변수·키 파일 ====="

# 1. 키 파일 생성
if [ ! -f "$KEY_FILE" ]; then
    echo "agent_api_key_test" | sudo tee "$KEY_FILE" >/dev/null
    echo "[OK] 키 파일 생성: $KEY_FILE"
else
    echo "[SKIP] 키 파일 이미 존재: $KEY_FILE"
fi

# 키 파일 권한 — agent-core 그룹만 read (수정 차단)
sudo chown agent-admin:agent-core "$KEY_FILE"
sudo chmod 440 "$KEY_FILE"

# 2. 환경 변수를 .bash_profile에 영구 등록 (멱등)
#    기존 AGENT_ 변수와 setup 마커를 제거 후 재추가
sudo touch "$BASH_PROFILE"
sudo sed -i '/^export AGENT_/d' "$BASH_PROFILE"
sudo sed -i '/^# --- agent-app env ---/,/^# --- end agent-app env ---/d' "$BASH_PROFILE"

sudo tee -a "$BASH_PROFILE" >/dev/null <<'EOF'

# --- agent-app env ---
export AGENT_HOME="/home/agent-admin/agent-app"
export AGENT_PORT="15034"
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
export AGENT_LOG_DIR="/var/log/agent-app"
[ -f ~/.bashrc ] && . ~/.bashrc
# --- end agent-app env ---
EOF

sudo chown agent-admin:agent-admin "$BASH_PROFILE"
sudo chmod 644 "$BASH_PROFILE"

echo "[OK] 환경 변수 등록 완료"
echo ""
echo "[검증] 새 셸에서 AGENT_ 변수 확인"
sudo -u agent-admin bash -lc 'env | grep ^AGENT_'

echo ""
echo "[검증] 키 파일 내용·권한"
sudo -u agent-admin cat "$KEY_FILE"
ls -l "$KEY_FILE"
