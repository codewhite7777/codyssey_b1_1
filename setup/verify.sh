#!/usr/bin/env bash
# setup/verify.sh — 명세의 모든 검증 항목 자동 점검
# 실패해도 끝까지 진행, 마지막에 종합 결과

set -uo pipefail

PASS=0
FAIL=0
FAILED_ITEMS=()

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  [OK]   $desc"
        ((PASS++)) || true
    else
        echo "  [FAIL] $desc"
        FAILED_ITEMS+=("$desc")
        ((FAIL++)) || true
    fi
}

echo "##############################################"
echo "# 명세 검증 (verify.sh)"
echo "##############################################"

echo ""
echo "===== [1] SSH 설정 ====="
check "sshd_config Port=20022" 'sudo sshd -T 2>/dev/null | grep -q "^port 20022$"'
check "sshd_config PermitRootLogin no" 'sudo sshd -T 2>/dev/null | grep -q "^permitrootlogin no$"'
check "포트 20022 LISTEN" 'sudo ss -tulnp | grep -q ":20022 "'

echo ""
echo "===== [2] 방화벽 ====="
check "ufw 활성" 'sudo ufw status | grep -q "Status: active"'
check "20022/tcp 허용" 'sudo ufw status | grep -qE "20022/tcp.*ALLOW"'
check "15034/tcp 허용" 'sudo ufw status | grep -qE "15034/tcp.*ALLOW"'

echo ""
echo "===== [3] 계정·그룹 ====="
check "사용자 agent-admin 존재" 'id agent-admin'
check "사용자 agent-dev 존재" 'id agent-dev'
check "사용자 agent-test 존재" 'id agent-test'
check "그룹 agent-common 존재" 'getent group agent-common'
check "그룹 agent-core 존재" 'getent group agent-core'
check "agent-admin ∈ agent-common" 'id -nG agent-admin | grep -qw agent-common'
check "agent-admin ∈ agent-core" 'id -nG agent-admin | grep -qw agent-core'
check "agent-dev ∈ agent-common" 'id -nG agent-dev | grep -qw agent-common'
check "agent-dev ∈ agent-core" 'id -nG agent-dev | grep -qw agent-core'
check "agent-test ∈ agent-common" 'id -nG agent-test | grep -qw agent-common'
check "agent-test ∉ agent-core (기대 차단)" '! id -nG agent-test | grep -qw agent-core'

echo ""
echo "===== [4] 디렉토리·권한 ====="
AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"
check "$AGENT_HOME 존재" "[ -d \"$AGENT_HOME\" ]"
check "$AGENT_HOME/upload_files 존재" "[ -d \"$AGENT_HOME/upload_files\" ]"
check "$AGENT_HOME/api_keys 존재" "[ -d \"$AGENT_HOME/api_keys\" ]"
check "$LOG_DIR 존재" "[ -d \"$LOG_DIR\" ]"
check "$AGENT_HOME/bin 존재" "[ -d \"$AGENT_HOME/bin\" ]"
check "agent-test 가 api_keys 접근 차단 (EACCES)" '! sudo -u agent-test ls /home/agent-admin/agent-app/api_keys 2>/dev/null'

echo ""
echo "===== [5] 환경 변수·키 파일 ====="
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
check "키 파일 존재" "[ -f \"$KEY_FILE\" ]"
check "키 파일 내용 정확" "[ \"\$(sudo cat \"$KEY_FILE\")\" = 'agent_api_key_test' ]"
check "agent-admin의 .bash_profile 에 AGENT_HOME 정의" 'sudo grep -q "^export AGENT_HOME=" /home/agent-admin/.bash_profile'
check "AGENT_PORT=15034 정의" 'sudo grep -q "^export AGENT_PORT=.15034." /home/agent-admin/.bash_profile'

echo ""
echo "===== [6] monitor.sh 설치·권한 ====="
MONITOR="$AGENT_HOME/bin/monitor.sh"
check "monitor.sh 존재" "[ -f \"$MONITOR\" ]"
check "monitor.sh 실행 가능" "[ -x \"$MONITOR\" ]"
check "monitor.sh 소유자 agent-dev" "[ \"\$(stat -c %U \"$MONITOR\" 2>/dev/null)\" = 'agent-dev' ]"
check "monitor.sh 그룹 agent-core" "[ \"\$(stat -c %G \"$MONITOR\" 2>/dev/null)\" = 'agent-core' ]"
check "monitor.sh 권한 750" "[ \"\$(stat -c %a \"$MONITOR\" 2>/dev/null)\" = '750' ]"

echo ""
echo "===== [7] cron·logrotate ====="
check "agent-admin crontab에 monitor.sh" 'sudo -u agent-admin crontab -l 2>/dev/null | grep -q monitor.sh'
check "logrotate 설정 파일 존재" "[ -f /etc/logrotate.d/agent-app ]"
check "logrotate 문법 OK" 'sudo logrotate -d /etc/logrotate.d/agent-app 2>&1 | grep -q "rotating pattern"'

# 종합 결과
echo ""
echo "##############################################"
echo "# 결과: PASS=$PASS, FAIL=$FAIL"
echo "##############################################"
if [ $FAIL -gt 0 ]; then
    echo ""
    echo "실패 항목:"
    for item in "${FAILED_ITEMS[@]}"; do
        echo "  - $item"
    done
    exit 1
fi
echo ""
echo "✓ 모든 검증 통과"
exit 0
