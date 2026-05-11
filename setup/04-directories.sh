#!/usr/bin/env bash
# setup/04-directories.sh — 디렉토리 구조 + 권한
# 멱등: mkdir -p, chown·chmod는 항상 안전

set -euo pipefail

AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"

echo "===== [04/06] 디렉토리·권한 ====="

# 1. AGENT_HOME — 앱 루트 (agent-admin 소유, core 그룹)
sudo mkdir -p "$AGENT_HOME"
sudo chown agent-admin:agent-core "$AGENT_HOME"
sudo chmod 750 "$AGENT_HOME"

# 2. upload_files — 공유 (agent-common 그룹 RW, setgid로 새 파일도 common 상속)
sudo mkdir -p "$AGENT_HOME/upload_files"
sudo chown agent-admin:agent-common "$AGENT_HOME/upload_files"
sudo chmod 2770 "$AGENT_HOME/upload_files"   # 2=setgid, 770=rwxrwx---

# 3. api_keys — 자격 증명 (agent-core 그룹 ONLY)
sudo mkdir -p "$AGENT_HOME/api_keys"
sudo chown agent-admin:agent-core "$AGENT_HOME/api_keys"
sudo chmod 770 "$AGENT_HOME/api_keys"

# 4. /var/log/agent-app — 모니터링 로그 (agent-core 그룹 RW, setgid)
sudo mkdir -p "$LOG_DIR"
sudo chown agent-admin:agent-core "$LOG_DIR"
sudo chmod 2770 "$LOG_DIR"

# 5. bin — monitor.sh 위치 (agent-dev 소유, agent-core 그룹)
sudo mkdir -p "$AGENT_HOME/bin"
sudo chown agent-dev:agent-core "$AGENT_HOME/bin"
sudo chmod 750 "$AGENT_HOME/bin"

echo "[OK] 디렉토리·권한 설정 완료"
echo ""
echo "[검증] ls -ld"
ls -ld "$AGENT_HOME" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "$AGENT_HOME/bin" "$LOG_DIR"

echo ""
echo "[검증] agent-test 가 api_keys 접근 차단 확인 (EACCES 기대)"
sudo -u agent-test ls "$AGENT_HOME/api_keys" 2>&1 || echo "  ✓ 정상 차단됨"
