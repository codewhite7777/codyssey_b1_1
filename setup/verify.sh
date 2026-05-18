#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/verify.sh — 명세 47개 항목 자동 검증
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : 명세의 모든 영역(SSH·방화벽·사용자·디렉토리·환경·monitor·cron·sudoers·
#          .bash_profile 보안·보너스2 시간기반 로그 보존) 을 47개 check 로
#          자동 점검. 실패해도 끝까지 진행 후 종합 결과.
#  사용  : bash setup/verify.sh   (root 권한 자동 escalate — sudo 자동 호출)
#          또는 sudo bash setup/verify.sh (이미 root 면 즉시 진행)
#  왜    : 평가자·학생이 한 줄로 명세 충족 여부 즉시 확인 가능.
#          setup 직후 + 평가 시점 모두 활용.
#  의존  : setup-all.sh 가 먼저 실행되어 있어야 의미 있음.
#
#  ★ pipefail 의도적 비활성 :
#    cmd 안에서 'X | grep -q ...' 패턴이 많음. grep -q 가 첫 매칭에서
#    즉시 종료하면 앞 명령(X)이 SIGPIPE(141)로 끝남. pipefail 켜져 있으면
#    이 정상 동작을 pipe 실패로 잡아 false negative 발생.
#    → set -u 만 사용 (errexit 도 빼야 실패해도 끝까지 진행).
#
#  학습 노트: bash-set-safe, 회고 노트 함정 3
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/verify.md
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    set -u                ─ unset 변수 참조 시 에러
#    local X="..."         ─ 함수 내부 지역 변수
#    eval "$cmd"           ─ cmd 문자열을 셸 명령으로 평가·실행
#    if cmd >/dev/null 2>&1 ─ cmd 실행해 stdout·stderr 모두 버림,
#                             exit code 만으로 if 분기
#    ARR+=("X")            ─ 배열에 요소 추가
#    ((PASS++)) || true    ─ 산술 증가, PASS=0 일 때 0 반환되어 set -e
#                             걸리는 함정 회피 (|| true)
#    "${ARR[@]}"           ─ 배열 모든 요소를 개별 인자로 펼침
#    [ -d X ]              ─ X 가 디렉토리인지
#    [ -f X ]              ─ X 가 일반 파일인지
#    [ -x X ]              ─ X 가 실행 가능한지
#    $(stat -c %U X)       ─ 파일 X 의 소유자 이름
#    $(stat -c %a X)       ─ 파일 X 의 권한 (8진수)
#    id -nG USER           ─ USER 의 모든 그룹 이름 (보조 그룹 포함)
#    grep -qw WORD         ─ -q quiet (출력 X), -w 단어 단위 매칭
#    !cmd                  ─ cmd 의 exit code 반전 (실패해야 통과)
#
# ═══════════════════════════════════════════════════════════════════

set -u   # pipefail · errexit 의도적 비활성


# ─── self-elevation (★ 일관된 root 권한 보장) ─────────────────────
# 일부 check ([ -d ], [ -f ], stat) 가 /home/agent-admin/ 안의 자원에
# 접근. 디렉토리 권한 0750 (owner=agent-admin, group=agent-core) 이라
# 일반 사용자는 권한 부족 → false FAIL.
# → root 가 아니면 자동으로 sudo 로 자기 자신 재실행 (exec = 현재 프로세스 교체).
# 학습 노트: shell-sudo-and-sudoers, bash-set-safe
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi


PASS=0
FAIL=0
FAILED_ITEMS=()

# ─── check 함수 ──────────────────────────────────────────────────
# 인자: $1 = 설명, $2 = 검사 명령(문자열)
# - eval 로 명령 실행, exit code 만 본다
# - >/dev/null 2>&1 : 출력 모두 버림 (테이블 깨끗하게)
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


# ─── [1] SSH 설정 ─────────────────────────────────────────────────
echo ""
echo "===== [1] SSH 설정 ====="
# sshd -T : 실제 적용된 효과적 config 출력 (파일이 아닌 메모리)
check "sshd_config Port=20022"                'sudo sshd -T 2>/dev/null | grep -q "^port 20022$"'
check "sshd_config PermitRootLogin no"        'sudo sshd -T 2>/dev/null | grep -q "^permitrootlogin no$"'
check "포트 20022 LISTEN"                       'sudo ss -tulnp | grep -q ":20022 "'


# ─── [2] 방화벽 ───────────────────────────────────────────────────
echo ""
echo "===== [2] 방화벽 ====="
check "ufw 활성"                                 'sudo ufw status | grep -q "Status: active"'
check "20022/tcp 허용"                           'sudo ufw status | grep -qE "20022/tcp.*ALLOW"'
check "15034/tcp 허용"                           'sudo ufw status | grep -qE "15034/tcp.*ALLOW"'


# ─── [3] 계정·그룹 ────────────────────────────────────────────────
echo ""
echo "===== [3] 계정·그룹 ====="
check "사용자 agent-admin 존재"                  'id agent-admin'
check "사용자 agent-dev 존재"                    'id agent-dev'
check "사용자 agent-test 존재"                   'id agent-test'
check "그룹 agent-common 존재"                   'getent group agent-common'
check "그룹 agent-core 존재"                     'getent group agent-core'
check "agent-admin ∈ agent-common"               'id -nG agent-admin | grep -qw agent-common'
check "agent-admin ∈ agent-core"                 'id -nG agent-admin | grep -qw agent-core'
check "agent-dev ∈ agent-common"                 'id -nG agent-dev   | grep -qw agent-common'
check "agent-dev ∈ agent-core"                   'id -nG agent-dev   | grep -qw agent-core'
check "agent-test ∈ agent-common"                'id -nG agent-test  | grep -qw agent-common'
# ! 앞 = 반전 — agent-test 가 agent-core 에 *없어야* 통과 (명세 의도)
check "agent-test ∉ agent-core (기대 차단)"      '! id -nG agent-test | grep -qw agent-core'


# ─── [4] 디렉토리·권한 ────────────────────────────────────────────
echo ""
echo "===== [4] 디렉토리·권한 ====="
AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"
check "$AGENT_HOME 존재"                         "[ -d \"$AGENT_HOME\" ]"
check "$AGENT_HOME/upload_files 존재"            "[ -d \"$AGENT_HOME/upload_files\" ]"
check "$AGENT_HOME/api_keys 존재"                "[ -d \"$AGENT_HOME/api_keys\" ]"
check "$LOG_DIR 존재"                            "[ -d \"$LOG_DIR\" ]"
check "$AGENT_HOME/bin 존재"                     "[ -d \"$AGENT_HOME/bin\" ]"
# agent-test 가 api_keys 못 들어가야 통과 (! 반전)
check "agent-test 가 api_keys 접근 차단 (EACCES)" '! sudo -u agent-test ls /home/agent-admin/agent-app/api_keys 2>/dev/null'


# ─── [5] 환경 변수·키 파일 ────────────────────────────────────────
echo ""
echo "===== [5] 환경 변수·키 파일 ====="
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
check "키 파일 존재"                             "[ -f \"$KEY_FILE\" ]"
# sudo cat : agent-core 가 아닌 사용자도 root 권한으로 read
check "키 파일 내용 정확"                        "[ \"\$(sudo cat \"$KEY_FILE\")\" = 'agent_api_key_test' ]"
check "agent-admin의 .bash_profile 에 AGENT_HOME 정의"  'sudo grep -q "^export AGENT_HOME=" /home/agent-admin/.bash_profile'
# 15034 가 따옴표·공백 포함될 수 있어 . (any char) 로 유연 매칭
check "AGENT_PORT=15034 정의"                    'sudo grep -q "^export AGENT_PORT=.15034." /home/agent-admin/.bash_profile'


# ─── [6] monitor.sh 설치·권한 ─────────────────────────────────────
echo ""
echo "===== [6] monitor.sh 설치·권한 ====="
MONITOR="$AGENT_HOME/bin/monitor.sh"
check "monitor.sh 존재"                          "[ -f \"$MONITOR\" ]"
check "monitor.sh 실행 가능"                     "[ -x \"$MONITOR\" ]"
# stat -c %U/G/a : 소유자명/그룹명/8진수 권한 추출
check "monitor.sh 소유자 agent-dev"              "[ \"\$(stat -c %U \"$MONITOR\" 2>/dev/null)\" = 'agent-dev' ]"
check "monitor.sh 그룹 agent-core"               "[ \"\$(stat -c %G \"$MONITOR\" 2>/dev/null)\" = 'agent-core' ]"
check "monitor.sh 권한 750"                      "[ \"\$(stat -c %a \"$MONITOR\" 2>/dev/null)\" = '750' ]"


# ─── [7] cron·logrotate ───────────────────────────────────────────
echo ""
echo "===== [7] cron·logrotate ====="
check "agent-admin crontab에 monitor.sh"         'sudo -u agent-admin crontab -l 2>/dev/null | grep -q monitor.sh'
check "logrotate 설정 파일 존재"                 "[ -f /etc/logrotate.d/agent-app ]"
# logrotate -d : dry-run, "rotating pattern: ..." 출력이 정상 신호
check "logrotate 문법 OK"                        'sudo logrotate -d /etc/logrotate.d/agent-app 2>&1 | grep -q "rotating pattern"'


# ─── [8] sudoers (monitor.sh 의 ufw 점검 지원) ────────────────────
# monitor.sh §"상태 점검" 이 'sudo -n ufw status' 를 호출 → NOPASSWD 룰 필요.
# 룰이 없으면 ufw active 인데도 false WARNING ("not active") 이 출력됨.
echo ""
echo "===== [8] sudoers (monitor.sh 의 ufw 점검) ====="
SUDOERS_FILE="/etc/sudoers.d/agent-admin-monitor"
check "sudoers 파일 존재"                        "[ -f \"$SUDOERS_FILE\" ]"
check "sudoers 파일 권한 0440"                   "[ \"\$(sudo stat -c %a \"$SUDOERS_FILE\" 2>/dev/null)\" = '440' ]"
check "sudoers 파일 소유자 root"                 "[ \"\$(sudo stat -c %U \"$SUDOERS_FILE\" 2>/dev/null)\" = 'root' ]"
check "sudoers 문법 OK (visudo -cf)"             "sudo visudo -cf \"$SUDOERS_FILE\""
# ★ 실작동 검증 — agent-admin 이 sudo -n ufw status 가능해야 통과
check "agent-admin → sudo -n ufw status 동작"    'sudo -u agent-admin sudo -n /usr/sbin/ufw status'


# ─── [9] 보너스 2 — 시간 기반 로그 보존 (log-rotate.sh) ────────────
# 명세 §5 보너스 2: 7일+ 압축 → archive/ 이동, 30일+ archive 삭제, 예외 처리.
echo ""
echo "===== [9] 보너스 2 — 시간 기반 로그 보존 ====="
LOG_ROTATE="$AGENT_HOME/bin/log-rotate.sh"
CRON_D="/etc/cron.d/agent-log-rotate"
check "log-rotate.sh 존재"                       "[ -f \"$LOG_ROTATE\" ]"
check "log-rotate.sh 실행 가능"                  "[ -x \"$LOG_ROTATE\" ]"
check "log-rotate.sh 권한 750"                   "[ \"\$(stat -c %a \"$LOG_ROTATE\" 2>/dev/null)\" = '750' ]"
check "/etc/cron.d/agent-log-rotate 존재"        "[ -f \"$CRON_D\" ]"
check "cron.d 에 log-rotate.sh 호출 등록"        "sudo grep -q 'log-rotate.sh' \"$CRON_D\""
# dry-run 검증 — 실제 변경 없이 스크립트가 syntax·로직 통과하는지
check "log-rotate.sh --dry-run 정상"             "sudo \"$LOG_ROTATE\" --dry-run"


# ─── 5.5) C1 — .bash_profile 권한 0640 (정보 누출 방지) ────────────
# AGENT_KEY_PATH 가 노출되는 .bash_profile 은 0640 이어야 others 차단.
# [5] 환경 변수 영역에 추가하지 않고 별도 — sudoers 와 같은 보안 가드.
echo ""
echo "===== [5b] .bash_profile 보안 권한 ====="
BASH_PROFILE="/home/agent-admin/.bash_profile"
check ".bash_profile 권한 0640"                  "[ \"\$(sudo stat -c %a \"$BASH_PROFILE\" 2>/dev/null)\" = '640' ]"


# ─── 종합 결과 ────────────────────────────────────────────────────
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
