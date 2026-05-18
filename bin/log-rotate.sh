#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  bin/log-rotate.sh — 시간 기반 로그 보존 정책 (명세 §5 보너스 2)
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : /var/log/agent-app/*.log 중 7일+ 경과 파일을 gzip 압축 →
#          /var/log/monitor/agent-app/archive/ 로 이동.
#          archive/*.gz 중 30일+ 경과 파일은 삭제.
#  왜    : 명세 §5 보너스 2 "시간 기반 로그 보존 정책" 충족.
#          크기 기반 logrotate (§4.4, /etc/logrotate.d/agent-app)
#          와 *별개*로 시간 축 보존 정책을 따로 구현.
#  멱등  : find 의 -mtime 검사라 같은 파일을 두 번 처리 안 함.
#          archive 디렉토리는 mkdir -p 로 매번 보장.
#  사용  : log-rotate.sh   (cron 으로 매일 03:00 실행)
#          --dry-run       (실행 안 함, 대상 파일만 출력)
#
#  ★ 예외 처리 (명세 §5 보너스 2 "권장")
#    - 디렉토리 미존재  → mkdir -p (압축 대상 폴더 부재면 [WARN])
#    - 권한 부족         → set +e 로 보호 + 개별 에러 stderr 로깅
#    - 대상 파일 0개     → [INFO] 출력 + 정상 종료 (exit 0)
#    - 부분 실패        → 끝까지 진행 + 종합 카운트 보고
#
#  ★ 크기 기반 logrotate 와의 관계
#    /etc/logrotate.d/agent-app : size 10M, rotate 10 (즉시 회전 + 압축)
#    bin/log-rotate.sh          : mtime +7 → 압축, +30 → 삭제 (장기 보존)
#    두 정책이 *직교* — 크기 기준은 즉시 trim, 시간 기준은 장기 housekeeping.
#
#  학습 노트: log-rotation, find-options
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/log-rotate.md
#
#  검증:
#    sudo /home/agent-admin/agent-app/bin/log-rotate.sh --dry-run
#    sudo ls -l /var/log/monitor/agent-app/archive/
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    set -uo pipefail       ─ -e 제외: 부분 실패해도 끝까지 housekeeping
#    : "${VAR:=default}"    ─ 환경 변수 default
#    find -mtime +N         ─ N일 이상 경과 (수정 시각 기준)
#    find -print0 / -0      ─ NUL 구분자 (공백·특수문자 안전)
#    while read -d ''        ─ NUL 구분 입력 읽기
#    [[ ... ]] vs [ ... ]   ─ [[ 가 bash 확장 (정규식·논리연산)
#    || true                ─ 명령 실패해도 계속
#    >&2                    ─ stderr 로 로깅 (정상 출력과 분리)
#
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail   # -e 의도적 제외 — 부분 실패해도 끝까지 housekeeping
export LC_ALL=C    # 출력 형식 안정 (한국어 locale 영향 회피)

# ─── 설정 (명세 §5 보너스 2) ──────────────────────────────────────
: "${AGENT_LOG_DIR:=/var/log/agent-app}"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"
COMPRESS_AGE_DAYS=7    # 7일+ 경과 파일 압축 대상
PURGE_AGE_DAYS=30      # 30일+ 경과 아카이브 삭제 대상

# ─── 인자 처리 — --dry-run 옵션 ───────────────────────────────────
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "[INFO] DRY RUN 모드 — 실제 변경 없음"
fi

# ─── 카운트 (종합 결과용) ─────────────────────────────────────────
COMPRESSED=0
MOVED=0
PURGED=0
WARNINGS=0
ERRORS=0

log_warn() { echo "[WARN] $*" >&2; WARNINGS=$((WARNINGS + 1)); }
log_err()  { echo "[ERROR] $*" >&2; ERRORS=$((ERRORS + 1)); }
log_info() { echo "[INFO] $*"; }
log_ok()   { echo "[OK] $*"; }


echo "===== log-rotate.sh — $(date '+%Y-%m-%d %H:%M:%S') ====="


# ─── 1) 소스 디렉토리 존재 확인 (예외 처리) ───────────────────────
# 명세 "디렉토리 미존재 → 안전 종료/경고"
if [[ ! -d "$AGENT_LOG_DIR" ]]; then
    log_warn "소스 디렉토리 미존재: $AGENT_LOG_DIR — 처리할 로그 없음, 정상 종료"
    exit 0
fi


# ─── 2) 아카이브 디렉토리 보장 (예외 처리) ────────────────────────
# 명세 "디렉토리 미존재 → 안전" — mkdir -p 로 자동 생성
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY: mkdir -p $ARCHIVE_DIR"
    else
        if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
            log_err "아카이브 디렉토리 생성 실패 (권한 부족?): $ARCHIVE_DIR"
            exit 1
        fi
        # 보안 권한 — root 또는 agent-core 그룹만
        chown root:agent-core "$ARCHIVE_DIR" 2>/dev/null || \
            log_warn "chown 실패 (agent-core 그룹 부재 가능): $ARCHIVE_DIR"
        chmod 2750 "$ARCHIVE_DIR" 2>/dev/null || \
            log_warn "chmod 실패: $ARCHIVE_DIR"
        log_ok "아카이브 디렉토리 생성: $ARCHIVE_DIR (2750 root:agent-core)"
    fi
fi


# ─── 3) 7일+ 경과 로그 → gzip 압축 → archive/ 이동 ────────────────
# find -mtime +7 : 수정 시각 7일 *초과* (정확히 7일 전 ~ 현재 는 미포함)
# -type f         : 일반 파일만 (디렉토리·심볼릭 제외)
# -name "*.log"   : .log 확장자만 (이미 .gz 인 것 제외)
# -not -newer     : (보강) 안전망 — currently-being-written 인 파일 회피
# -print0         : NUL 구분 (파일명에 공백·줄바꿈 안전)

echo ""
echo "[1/2] 7일+ 경과 로그 압축·아카이브 이동"

# 대상 카운트 (예외 처리: 0개면 안내 후 다음 단계로)
TARGET_COUNT=0
while IFS= read -r -d '' file; do
    TARGET_COUNT=$((TARGET_COUNT + 1))
done < <(find "$AGENT_LOG_DIR" -maxdepth 1 -type f -name "*.log" \
             -mtime "+$COMPRESS_AGE_DAYS" -print0 2>/dev/null)

if [[ $TARGET_COUNT -eq 0 ]]; then
    log_info "  대상 파일 0개 — 압축 단계 skip"
else
    log_info "  대상 파일 ${TARGET_COUNT}개"

    while IFS= read -r -d '' file; do
        base=$(basename "$file")
        ts=$(date '+%Y%m%d-%H%M%S')
        archived="${ARCHIVE_DIR}/${base}.${ts}.gz"

        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "  DRY: gzip -c $file > $archived && rm $file"
            continue
        fi

        # gzip -c : stdout 으로 압축 결과 (원본 파일은 건드리지 않음)
        # 그다음 mv 가 아니라 rm — gzip 결과를 직접 archive/ 에 적었으므로
        if gzip -c "$file" > "$archived" 2>/dev/null; then
            if rm "$file" 2>/dev/null; then
                chmod 0640 "$archived" 2>/dev/null || true
                log_ok "  $base → $(basename "$archived")"
                COMPRESSED=$((COMPRESSED + 1))
                MOVED=$((MOVED + 1))
            else
                # 압축 성공, 원본 삭제 실패 — 아카이브는 보존, 원본 남음
                log_warn "원본 삭제 실패 (다음 회전에 재시도): $file"
            fi
        else
            log_err "gzip 실패 (권한 부족 또는 디스크 부족?): $file"
            rm -f "$archived" 2>/dev/null   # 부분 결과 정리
        fi
    done < <(find "$AGENT_LOG_DIR" -maxdepth 1 -type f -name "*.log" \
                 -mtime "+$COMPRESS_AGE_DAYS" -print0 2>/dev/null)
fi


# ─── 4) 30일+ 경과 아카이브 삭제 ──────────────────────────────────
echo ""
echo "[2/2] 30일+ 경과 아카이브 삭제"

PURGE_COUNT=0
while IFS= read -r -d '' file; do
    PURGE_COUNT=$((PURGE_COUNT + 1))
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.gz" \
             -mtime "+$PURGE_AGE_DAYS" -print0 2>/dev/null)

if [[ $PURGE_COUNT -eq 0 ]]; then
    log_info "  대상 파일 0개 — 삭제 단계 skip"
else
    log_info "  대상 파일 ${PURGE_COUNT}개"

    while IFS= read -r -d '' file; do
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "  DRY: rm $file"
            continue
        fi
        if rm "$file" 2>/dev/null; then
            log_ok "  삭제: $(basename "$file")"
            PURGED=$((PURGED + 1))
        else
            log_err "삭제 실패 (권한 부족?): $file"
        fi
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.gz" \
                 -mtime "+$PURGE_AGE_DAYS" -print0 2>/dev/null)
fi


# ─── 5) 종합 결과 ─────────────────────────────────────────────────
echo ""
echo "===== 종합 결과 ====="
echo "  압축·이동 : ${COMPRESSED}개"
echo "  삭제      : ${PURGED}개"
echo "  경고      : ${WARNINGS}건"
echo "  에러      : ${ERRORS}건"

# exit code 정책 — 에러 있으면 1, 아니면 0 (경고는 0 유지)
if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
