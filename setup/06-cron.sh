#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/06-cron.sh — cron 매분 등록 + logrotate 정책
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : agent-admin 의 crontab 에 monitor.sh 매분 실행 등록 +
#          logrotate 정책(10MB / 10파일) 설치.
#  왜    : 자동 관제 — 사람이 매분 직접 측정할 수 없으니 cron 이 호출.
#          로그가 무한 커지는 것을 logrotate 가 자동 회전·압축.
#  멱등  : crontab 기존 monitor.sh 라인 + 환경 라인 제거 후 재추가.
#          logrotate 설정 파일은 tee 로 덮어쓰기.
#  의존  : monitor.sh 가 $AGENT_HOME/bin/ 에 배포되어 있어야 cron 이 실행
#          가능 (배포는 setup-all.sh 에서 처리).
#
#  학습 노트: cron-fundamentals, log-rotation, cron-environment-gotchas
#  검증:
#    sudo -u agent-admin crontab -l           → monitor.sh 줄 보임
#    sudo logrotate -d /etc/logrotate.d/agent-app   → "rotating pattern"
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    mktemp                  ─ 안전한 임시 파일 생성 (랜덤 이름)
#    chmod 0644 X            ─ 임시 파일을 다른 사용자도 읽게 (함정 회피)
#    trap "rm -f X" EXIT     ─ 스크립트 종료 시 X 삭제 (정상·에러 모두)
#    crontab -l              ─ 현재 사용자의 crontab 내용 출력
#    crontab FILE            ─ FILE 의 내용을 새 crontab 으로 등록
#    sudo -u USER cmd        ─ USER 권한으로 cmd 실행
#    grep -v PAT             ─ PAT 와 매칭 안 하는 줄만 (역매칭)
#    pipeline | A | B        ─ A 의 stdout 을 B 의 stdin 으로
#    >> FILE 2>&1            ─ stdout + stderr 모두 FILE 에 append
#
#  crontab 형식:
#    * * * * * COMMAND     → 매분 실행
#    분 시 일 월 요일 COMMAND
#    환경 변수도 가능: SHELL=/bin/bash, PATH=..., MAILTO=""
#
#  logrotate 옵션:
#    size 10M       ─ 10MB 이상이면 회전
#    rotate 10      ─ 회전된 파일 10개까지 보존 (그 이상은 가장 오래된 것 삭제)
#    compress       ─ 회전된 파일 gzip 압축
#    delaycompress  ─ 가장 최근 회전 파일은 압축 안 함 (다음 회전 시 압축)
#    copytruncate   ─ 원본을 복사 후 truncate (앱 재시작 없이 가능)
#    su U G         ─ 회전 작업을 U 사용자·G 그룹 권한으로 (group-writable
#                     디렉토리 보안 거부 회피)
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

echo "===== [06/06] cron·logrotate ====="


# ─── 1) logrotate 정책 파일 설치 ──────────────────────────────────
# heredoc <<'EOF' (따옴표): 내부 $var, ${}, * 등 모두 그대로 기록
sudo tee /etc/logrotate.d/agent-app >/dev/null <<'EOF'
/var/log/agent-app/monitor.log {
    su agent-dev agent-core
    size 10M
    rotate 10
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 agent-dev agent-core
}
EOF
echo "[OK] logrotate 설정: /etc/logrotate.d/agent-app"

# logrotate 문법 검증 (dry-run, 실제 회전 X)
sudo logrotate -d /etc/logrotate.d/agent-app >/dev/null 2>&1 \
    && echo "[OK] logrotate 문법 검증 통과" \
    || echo "[WARN] logrotate dry-run 경고 — 직접 실행해 확인"


# ─── 2) agent-admin crontab 갱신 (멱등) ───────────────────────────
# mktemp 기본 권한이 0600 → sudo (root) 가 만든 파일을 agent-admin 이
# 못 읽는 함정 발생. 0644 로 완화 (lifespan 짧고 trap 으로 즉시 삭제됨).
TMPCRON=$(mktemp)
chmod 0644 "$TMPCRON"
trap "rm -f $TMPCRON" EXIT

# 기존 crontab 에서 monitor.sh 줄 + cron 환경 변수 라인 제거
# (멱등 — 여러 번 실행해도 중복 X)
sudo -u agent-admin crontab -l 2>/dev/null \
    | grep -v 'monitor\.sh' \
    | grep -v '^SHELL=' \
    | grep -v '^PATH=' \
    | grep -v '^MAILTO=' \
    > "$TMPCRON" || true
# || true : crontab 비어있어도 (exit 1) 멈추지 않음 (set -e 회피)


# ─── 3) 새 crontab 항목 추가 ──────────────────────────────────────
# heredoc <<'EOC' (따옴표) : 내부 그대로 (cron 형식 보존)
# cron 환경 변수 :
#   SHELL=/bin/bash  ─ 명시 안 하면 /bin/sh (bash 확장 문법 불가)
#   PATH=...         ─ cron 기본 PATH 매우 빈약 → 명시 필수
#   MAILTO=""        ─ cron 이 출력을 메일로 보내려고 시도 안 함
cat >> "$TMPCRON" <<'EOC'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
EOC


# crontab 으로 등록 (agent-admin 권한)
sudo -u agent-admin crontab "$TMPCRON"


echo "[OK] cron 등록 완료"
echo ""
echo "[검증] agent-admin 의 crontab"
sudo -u agent-admin crontab -l
