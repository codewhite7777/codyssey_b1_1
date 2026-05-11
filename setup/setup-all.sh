#!/usr/bin/env bash
# setup/setup-all.sh — 모든 setup 스크립트 순차 실행 + monitor 배포 + verify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "##############################################"
echo "# codyssey_b1_1 setup-all"
echo "# repo: $REPO_ROOT"
echo "##############################################"
echo ""

# 1. 각 setup 스크립트 실행
for script in 01-ssh.sh 02-firewall.sh 03-users-groups.sh 04-directories.sh 05-environment.sh 06-cron.sh; do
    echo ""
    echo ">>> 실행: setup/$script"
    bash "$SCRIPT_DIR/$script"
done

# 2. monitor.sh, report.sh를 $AGENT_HOME/bin/에 배포 + 권한
echo ""
echo ">>> monitor.sh, report.sh 배포"
AGENT_BIN="/home/agent-admin/agent-app/bin"

sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/monitor.sh" "$AGENT_BIN/monitor.sh"
sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/report.sh" "$AGENT_BIN/report.sh"

echo "[OK] $AGENT_BIN/monitor.sh, report.sh 배포 완료"
ls -l "$AGENT_BIN/"

# 3. 검증 스크립트 실행
echo ""
echo ">>> 전체 검증 (verify.sh)"
bash "$SCRIPT_DIR/verify.sh"

echo ""
echo "##############################################"
echo "# setup-all 완료"
echo "##############################################"
echo ""
echo "다음 단계 (수동):"
echo "  1. agent-admin 으로 전환: sudo -u agent-admin -i"
echo "  2. agent-app 실행: python \$AGENT_HOME/agent_app.py"
echo "  3. 1-2분 후 cron 로그 확인: tail /var/log/agent-app/monitor.log"
