#!/usr/bin/env bash
# report.sh — monitor.log 분석·통계 리포트 (보너스 산출물)
#
# 사용법:
#   report.sh                              # 전체 로그 분석
#   report.sh "2026-05-11 00:00" "2026-05-11 23:59"   # 시간 범위
#
# 출력: CPU·MEM·DISK 각각 평균/최대/최소 + 최대값 시점 + 샘플 수

set -euo pipefail
export LC_ALL=C

: "${AGENT_LOG_DIR:=/var/log/agent-app}"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] log 파일이 없습니다: $LOG_FILE" >&2
    exit 1
fi

START="${1:-}"
END="${2:-}"

# 시간 범위 필터링
if [ -n "$START" ] || [ -n "$END" ]; then
    FILTERED=$(awk -v s="$START" -v e="$END" '
        {
            # 로그 라인 형식: [YYYY-MM-DD HH:MM:SS] ...
            match($0, /\[([0-9-]+ [0-9:]+)\]/, m)
            ts = m[1]
            if (ts == "") next
            if (s != "" && ts < s) next
            if (e != "" && ts > e) next
            print
        }
    ' "$LOG_FILE")
else
    FILTERED=$(cat "$LOG_FILE")
fi

if [ -z "$FILTERED" ]; then
    echo "[WARN] 해당 범위에 데이터 없음" >&2
    exit 0
fi

SAMPLES=$(echo "$FILTERED" | wc -l)

# 메트릭별 통계 계산 함수
compute_stats() {
    local metric="$1"
    local label="$2"
    echo "$FILTERED" | awk -v m="$metric" -v label="$label" '
        BEGIN { min_v=999999; max_v=-1; sum=0; count=0; max_ts=""; min_ts="" }
        {
            # 타임스탬프 추출
            match($0, /\[([0-9-]+ [0-9:]+)\]/, t)
            ts = t[1]
            # 메트릭 값 추출
            if (match($0, m ":([0-9.]+)", v)) {
                val = v[1] + 0
                sum += val; count++
                if (val > max_v) { max_v = val; max_ts = ts }
                if (val < min_v) { min_v = val; min_ts = ts }
            }
        }
        END {
            if (count > 0) {
                printf "  [%s]\n", label
                printf "    Average : %.1f%%\n", sum/count
                printf "    Maximum : %s%% at %s\n", max_v, max_ts
                printf "    Minimum : %s%% at %s\n", min_v, min_ts
            } else {
                printf "  [%s] (데이터 없음)\n", label
            }
        }
    '
}

echo "====== STATISTICS REPORT ======"
[ -n "$START" ] && echo "  Range: $START ~ ${END:-now}"
echo ""

compute_stats "CPU"        "CPU"
compute_stats "MEM"        "Memory"
compute_stats "DISK_USED"  "Disk"

echo "  [Samples]"
echo "    Data Points: $SAMPLES samples"
