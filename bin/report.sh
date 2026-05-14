#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  bin/report.sh — monitor.log 분석·통계 리포트 (보너스 산출물)
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : monitor.log 의 라인을 파싱해 CPU·MEM·DISK 각각의
#          평균·최대·최소 + 최대값 시점 + 샘플 수 출력.
#  왜    : 분 단위 로그가 누적되면 사람이 직접 읽기 어려움.
#          한눈에 추세를 볼 수 있는 요약 리포트가 운영에 유용.
#  사용법:
#    report.sh                                   # 전체 로그
#    report.sh "2026-05-11 00:00" "..."          # 시작 시각만
#    report.sh "..." "2026-05-11 23:59"          # 종료 시각만
#    report.sh "2026-05-11 00:00" "2026-05-11 23:59"   # 범위
#  의존  : awk (gawk 권장 — match 의 3번째 인자 사용).
#
#  학습 노트: cron-fundamentals, log-rotation
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/report.md
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    "${1:-}"             ─ 첫 인자, 없으면 빈 문자열
#    [ -f X ]             ─ X 가 일반 파일인지
#    [ -n "$X" ]          ─ X 가 비어있지 않은지
#    [ -z "$X" ]          ─ X 가 비어있는지
#    cmd >&2              ─ stdout 을 stderr 로 (에러 메시지용)
#    awk -v X="val" '...' ─ awk 변수 전달
#    match($0, /RE/, ARR) ─ 정규식 매칭, 캡처를 ARR 배열에
#    함수 정의 함수명() {} ─ 호출 시 인자: $1, $2, ...
#    local X              ─ 함수 지역 변수
#
#  awk 흐름 :
#    BEGIN { ... }    ─ 입력 읽기 전 1회
#    { ... }          ─ 매 라인마다 실행 (현재 라인 = $0)
#    END { ... }      ─ 모든 라인 처리 후 1회
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail
export LC_ALL=C   # 출력 형식 안정화

: "${AGENT_LOG_DIR:=/var/log/agent-app}"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"


# ─── 1) 로그 파일 존재 확인 ───────────────────────────────────────
if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] log 파일이 없습니다: $LOG_FILE" >&2
    exit 1
fi


# ─── 2) 시간 범위 인자 (둘 다 선택) ───────────────────────────────
START="${1:-}"
END="${2:-}"


# ─── 3) 범위 필터링 (있으면) ──────────────────────────────────────
# awk 로 라인의 타임스탬프를 추출해 START·END 사이만 통과
if [ -n "$START" ] || [ -n "$END" ]; then
    FILTERED=$(awk -v s="$START" -v e="$END" '
        {
            # 로그 형식: [YYYY-MM-DD HH:MM:SS] ...
            # match 3번째 인자 (gawk 확장) : 캡처를 m 배열에 저장
            match($0, /\[([0-9-]+ [0-9:]+)\]/, m)
            ts = m[1]
            if (ts == "") next        # 타임스탬프 못 찾으면 다음 라인
            if (s != "" && ts < s) next   # 시작 시각 이전이면 skip
            if (e != "" && ts > e) next   # 종료 시각 이후면 skip
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

# wc -l : 줄 수 (= 샘플 수)
SAMPLES=$(echo "$FILTERED" | wc -l)


# ─── 4) 메트릭 통계 함수 ──────────────────────────────────────────
# 한 메트릭(CPU/MEM/DISK_USED) 의 평균·최대·최소 + 최대 시점 계산.
# awk 한 패스로 모든 라인 처리.
compute_stats() {
    local metric="$1"   # 매칭할 메트릭 이름 (CPU/MEM/DISK_USED)
    local label="$2"    # 출력 시 표시할 한글·짧은 이름
    echo "$FILTERED" | awk -v m="$metric" -v label="$label" '
        BEGIN {
            min_v = 999999    # 비교용 초기값 (모든 실제 값보다 큼)
            max_v = -1        # 모든 실제 값보다 작음
            sum = 0
            count = 0
        }
        {
            # 타임스탬프 추출
            match($0, /\[([0-9-]+ [0-9:]+)\]/, t)
            ts = t[1]
            # 메트릭 값 추출 (예: "CPU:25.3%" → 25.3)
            if (match($0, m ":([0-9.]+)", v)) {
                val = v[1] + 0    # +0 으로 숫자 변환 (문자열 → number)
                sum += val
                count++
                if (val > max_v) { max_v = val; max_ts = ts }
                if (val < min_v) { min_v = val; min_ts = ts }
            }
        }
        END {
            if (count > 0) {
                printf "  [%s]\n", label
                printf "    Average : %.1f%%\n", sum / count
                printf "    Maximum : %s%% at %s\n", max_v, max_ts
                printf "    Minimum : %s%% at %s\n", min_v, min_ts
            } else {
                printf "  [%s] (데이터 없음)\n", label
            }
        }
    '
}


# ─── 5) 출력 ──────────────────────────────────────────────────────
echo "====== STATISTICS REPORT ======"
[ -n "$START" ] && echo "  Range: $START ~ ${END:-now}"
echo ""

compute_stats "CPU"        "CPU"
compute_stats "MEM"        "Memory"
compute_stats "DISK_USED"  "Disk"

echo "  [Samples]"
echo "    Data Points: $SAMPLES samples"
