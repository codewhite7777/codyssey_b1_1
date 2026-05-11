#!/usr/bin/env bash
# monitor.sh — 시스템 관제 자동화 (B1-1 핵심 산출물)
#
# 동작:
#   1. agent_app.py 프로세스 health check (실패 시 exit 1)
#   2. TCP 15034 LISTEN 확인 (실패 시 exit 1)
#   3. 방화벽 활성 상태 (비활성이면 WARN만)
#   4. CPU·MEM·DISK 사용률 측정 + 임계값 경고
#   5. /var/log/agent-app/monitor.log 한 줄 추가

set -euo pipefail

# cron 환경 함정 회피
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C

# 환경 변수 default (cron에서 .bash_profile 안 읽혀서)
: "${AGENT_HOME:=/home/agent-admin/agent-app}"
: "${AGENT_PORT:=15034}"
: "${AGENT_LOG_DIR:=/var/log/agent-app}"

APP_NAME="agent_app.py"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"

# 임계값 (명세)
THRESH_CPU=20
THRESH_MEM=10
THRESH_DISK=80

# 헬퍼
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ============================================
echo "====== SYSTEM MONITOR RESULT ======"
echo ""
echo "[HEALTH CHECK]"

# 1. 프로세스 살아있는지 + 상태 검증 (zombie/D 식별)
PID=$(pgrep -f "$APP_NAME" | head -1 || true)
if [ -z "$PID" ]; then
    echo "Checking process '$APP_NAME'... [FAIL]"
    log_to_file "[ERROR] process '$APP_NAME' not running"
    exit 1
fi

STATE=$(ps -o state= -p "$PID" 2>/dev/null | tr -d ' ' || echo "?")
case "$STATE" in
    R|S)
        echo "Checking process '$APP_NAME'... [OK] (PID: $PID)"
        ;;
    D)
        echo "Checking process '$APP_NAME'... [WARN] (PID: $PID, state=D uninterruptible)"
        ;;
    Z)
        echo "Checking process '$APP_NAME'... [FAIL] (PID: $PID, state=Z zombie)"
        log_to_file "[ERROR] PID:$PID is zombie"
        exit 1
        ;;
    *)
        echo "Checking process '$APP_NAME'... [WARN] (PID: $PID, state=$STATE unexpected)"
        ;;
esac

# 2. 포트 LISTEN 확인
if ss -tulnp 2>/dev/null | grep -q ":${AGENT_PORT} "; then
    echo "Checking port $AGENT_PORT... [OK]"
else
    echo "Checking port $AGENT_PORT... [FAIL]"
    log_to_file "[ERROR] port $AGENT_PORT not LISTEN"
    exit 1
fi

# 3. 방화벽 상태 (경고만)
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

# 4. CPU 사용률 (top 2회 측정으로 안정화)
CPU_USED_RAW=$(top -b -n 2 -d 0.5 2>/dev/null | grep "Cpu(s)" | tail -1 \
    | awk -F'id,' '{ if ($1) print 100 - $1 }' \
    | awk '{print $NF}')
CPU_USED="${CPU_USED_RAW:-0}"
CPU_USED_INT="${CPU_USED%.*}"
[ -z "$CPU_USED_INT" ] && CPU_USED_INT=0
printf "CPU Usage : %s%%\n" "$CPU_USED"

# 5. 메모리 사용률 (free 기반)
MEM_USED=$(free 2>/dev/null | awk '/^Mem:/ {if ($2 > 0) printf "%.1f", $3/$2 * 100; else print "0"}')
MEM_USED_INT="${MEM_USED%.*}"
[ -z "$MEM_USED_INT" ] && MEM_USED_INT=0
printf "MEM Usage : %s%%\n" "$MEM_USED"

# 6. 디스크 사용률 (Root partition)
DISK_USED=$(df / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')
DISK_USED="${DISK_USED:-0}"
printf "DISK Used : %s%%\n" "$DISK_USED"

# 7. 임계값 경고
echo ""
WARN_COUNT=0
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

# 8. 로그 한 줄 누적 (명세 포맷)
log_to_file "PID:${PID} CPU:${CPU_USED}% MEM:${MEM_USED}% DISK_USED:${DISK_USED}%"

echo ""
echo "[INFO] Log appended: $LOG_FILE"

exit 0
