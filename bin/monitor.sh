#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  bin/monitor.sh — 시스템 관제 자동화 (★ B1-1 핵심 산출물)
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : cron 이 매분 호출하는 관제 스크립트.
#          (1) agent-app health check 3단 → (2) 자원 측정 3종 →
#          (3) 임계값 경고 → (4) monitor.log 한 줄 누적.
#  왜    : "서비스가 살아있나?" + "자원 사용량이 적정한가?" 를 분 단위로
#          자동 기록. 사람이 직접 보고 있을 수 없으니 cron + 로그.
#  의존  : pgrep, ps, ss, top, free, df, awk (모두 표준 도구).
#  보안  : cron 환경 함정 회피 — PATH·LC_ALL·AGENT_* 환경 변수 명시.
#
#  학습 노트:
#    - process-and-signals : health check 3단의 의도
#    - cpu/memory/disk-measurement : 자원 측정 도구별 함정
#    - cron-environment-gotchas : PATH·env 명시 이유
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/monitor.md
#  검증:
#    수동 1회 실행 : sudo -u agent-admin $AGENT_HOME/bin/monitor.sh
#    cron 누적 확인 : sudo tail /var/log/agent-app/monitor.log
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    set -euo pipefail        ─ 안전 모드 3종 세트
#    export X=...             ─ 환경 변수로 등록 (자식 프로세스 상속)
#    : "${VAR:=default}"      ─ VAR 없으면 default 할당 (멱등 default)
#    함수 정의 : name() {...} ─ 호출은 함수명만
#    $(cmd)                   ─ 명령 치환 (cmd stdout 을 문자열로)
#    cmd | head -1            ─ 첫 줄만 추출
#    || true                  ─ 명령 실패해도 OK (set -e 회피)
#    [ -z "$X" ]              ─ X 가 빈 문자열인지
#    case "$X" in PAT) ... ;; esac  ─ 패턴 분기
#    if cmd ; then ... fi     ─ cmd exit code 로 분기
#    cmd >/dev/null 2>&1      ─ stdout·stderr 모두 버림
#    ${X%.*}                  ─ X 의 끝에서 '.' 이후 제거 (소수점 → 정수)
#    ${X:-default}            ─ X 비어있으면 default 사용
#    ((COUNT++)) || true      ─ 산술 증가 (0 일 때 set -e 회피)
#    printf "FORMAT" args     ─ echo 보다 정밀한 출력 (포맷 지정)
#    awk '...'                ─ 라인 단위 텍스트 처리·계산
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail


# ─── 0) cron 환경 함정 회피 ───────────────────────────────────────
# cron 은 .bash_profile 안 읽고 PATH 가 매우 빈약. 명시적 set 필수.
# LC_ALL=C 는 date·ps·free 등의 출력 형식을 영어 POSIX 로 고정
# (locale 따라 한국어 출력되면 awk 파싱이 깨짐).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C

# AGENT_* default — cron 셸은 .bash_profile 안 읽으니 안전망
# `: "${X:=Y}"` 는 X 가 unset/empty 면 Y 를 할당 (and assign)
: "${AGENT_HOME:=/home/agent-admin/agent-app}"
: "${AGENT_PORT:=15034}"
: "${AGENT_LOG_DIR:=/var/log/agent-app}"

APP_NAME="agent-app"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"

# 임계값 (명세)
THRESH_CPU=20
THRESH_MEM=10
THRESH_DISK=80


# ─── 헬퍼 함수 ────────────────────────────────────────────────────
# 한 줄을 타임스탬프 + 내용 형식으로 monitor.log 에 append
# $* = 함수의 모든 인자를 한 문자열로
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}


echo "====== SYSTEM MONITOR RESULT ======"
echo ""
echo "[HEALTH CHECK]"


# ─── 1) 프로세스 살아있나? ────────────────────────────────────────
# pgrep -f PATTERN : 명령줄 전체에서 PATTERN 매칭되는 프로세스의 PID
# - || true : 매칭 없으면 exit 1 → set -e 발동 회피
PID=$(pgrep -f "$APP_NAME" | head -1 || true)
if [ -z "$PID" ]; then
    echo "Checking process '$APP_NAME'... [FAIL]"
    log_to_file "[ALERT] agent-app 미실행"
    exit 1
fi


# ─── 2) 프로세스 상태가 정상인가? ─────────────────────────────────
# ps -o state= -p PID : 해당 PID 의 상태 한 글자 (R/S/D/T/Z)
#   R=Running, S=Sleeping(정상), D=I/O wait, T=Stopped, Z=Zombie
# tr -d ' ' : 공백 제거
STATE=$(ps -o state= -p "$PID" 2>/dev/null | tr -d ' ' || echo "?")
case "$STATE" in
    R|S)
        # 정상 상태 (Running 또는 Sleeping)
        echo "Checking process '$APP_NAME'... [OK] (PID: $PID)"
        ;;
    D)
        # I/O 대기 중 (디스크/네트워크) — 잠시면 OK, 길면 hang
        echo "Checking process '$APP_NAME'... [WARN] (PID: $PID, state=D uninterruptible)"
        ;;
    Z)
        # zombie — 종료됐는데 부모가 reap 안 함. 사망 상태.
        echo "Checking process '$APP_NAME'... [FAIL] (PID: $PID, state=Z zombie)"
        log_to_file "[ALERT] agent-app PID:$PID is zombie"
        exit 1
        ;;
    *)
        echo "Checking process '$APP_NAME'... [WARN] (PID: $PID, state=$STATE unexpected)"
        ;;
esac


# ─── 3) 포트 LISTEN 확인 ──────────────────────────────────────────
# ss -tulnp : TCP·UDP·LISTEN·numeric·process
# grep -q : 매칭 시 즉시 종료 (exit 0), 출력 X
if ss -tulnp 2>/dev/null | grep -q ":${AGENT_PORT} "; then
    echo "Checking port $AGENT_PORT... [OK]"
else
    echo "Checking port $AGENT_PORT... [FAIL]"
    log_to_file "[ALERT] port $AGENT_PORT not LISTEN"
    exit 1
fi


# ─── 4) 방화벽 상태 (경고만, exit X) ──────────────────────────────
# - ufw 또는 firewalld 자동 감지
# - sudo -n : 비밀번호 prompt 없이 (실패해도 silent)
FW_STATUS="unknown"
if command -v ufw >/dev/null 2>&1; then
    if sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
        FW_STATUS="active"
    else
        FW_STATUS="inactive"
        echo "[WARNING] firewall (ufw) is not active"
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    if sudo -n firewall-cmd --state 2>/dev/null | grep -q running; then
        FW_STATUS="active"
    else
        FW_STATUS="inactive"
        echo "[WARNING] firewall (firewalld) is not running"
    fi
fi


echo ""
echo "[RESOURCE MONITORING]"


# ─── 5) CPU 사용률 ───────────────────────────────────────────────
# top -b -n 2 -d 0.5 : batch 모드, 2회 측정 (첫 회는 누적, 2회만 정확),
#                       간격 0.5초
# grep "Cpu(s)" | tail -1 : 두 번째 측정의 Cpu 라인
# awk -F'id,' '{print 100 - $1}' : "id," 앞 = idle %, 100 에서 빼면 사용 %
# awk '{print $NF}' : 마지막 토큰 (숫자만)
CPU_USED_RAW=$(top -b -n 2 -d 0.5 2>/dev/null | grep "Cpu(s)" | tail -1 \
    | awk -F'id,' '{ if ($1) print 100 - $1 }' \
    | awk '{print $NF}')
CPU_USED="${CPU_USED_RAW:-0}"
CPU_USED_INT="${CPU_USED%.*}"          # 소수점 잘라 정수 (비교용)
[ -z "$CPU_USED_INT" ] && CPU_USED_INT=0
printf "CPU Usage : %s%%\n" "$CPU_USED"


# ─── 6) 메모리 사용률 ─────────────────────────────────────────────
# free 의 Mem 라인 : $1=label, $2=total, $3=used, ...
# used / total * 100 → 사용률 %
MEM_USED=$(free 2>/dev/null | awk '/^Mem:/ {if ($2 > 0) printf "%.1f", $3/$2 * 100; else print "0"}')
MEM_USED_INT="${MEM_USED%.*}"
[ -z "$MEM_USED_INT" ] && MEM_USED_INT=0
printf "MEM Usage : %s%%\n" "$MEM_USED"


# ─── 7) 디스크 사용률 (Root partition) ────────────────────────────
# df / : 루트 파티션 사용량
# NR==2 : 두 번째 줄 (헤더 다음, 데이터 줄)
# $5 = "23%" 형태 → gsub 로 '%' 제거 → 숫자만
DISK_USED=$(df / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')
DISK_USED="${DISK_USED:-0}"
printf "DISK Used : %s%%\n" "$DISK_USED"


# ─── 8) 임계값 경고 ──────────────────────────────────────────────
echo ""
WARN_COUNT=0
# -gt : 정수 비교 (>). 문자열 비교는 = / !=
if [ "$CPU_USED_INT" -gt "$THRESH_CPU" ]; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USED}% > ${THRESH_CPU}%)"
    ((WARN_COUNT++)) || true
fi
if [ "$MEM_USED_INT" -gt "$THRESH_MEM" ]; then
    echo "[WARNING] MEM threshold exceeded (${MEM_USED}% > ${THRESH_MEM}%)"
    ((WARN_COUNT++)) || true
fi
if [ "$DISK_USED" -gt "$THRESH_DISK" ]; then
    echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > ${THRESH_DISK}%)"
    ((WARN_COUNT++)) || true
fi
if [ "$WARN_COUNT" -eq 0 ]; then
    echo "[INFO] All metrics within threshold"
fi


# ─── 9) monitor.log 한 줄 누적 (명세 포맷) ───────────────────────
# 형식 : [YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%
log_to_file "PID:${PID} CPU:${CPU_USED}% MEM:${MEM_USED}% DISK_USED:${DISK_USED}%"

echo ""
echo "[INFO] Log appended: $LOG_FILE"

exit 0
