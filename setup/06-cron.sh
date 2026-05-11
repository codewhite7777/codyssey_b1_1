#!/usr/bin/env bash
# setup/06-cron.sh — cron 등록 + logrotate 정책
# 멱등: crontab 기존 monitor.sh 줄 제거 후 재추가

set -euo pipefail

echo "===== [06/06] cron·logrotate ====="

# 1. logrotate 정책 — 10MB / 10파일 보존
sudo tee /etc/logrotate.d/agent-app >/dev/null <<'EOF'
/var/log/agent-app/monitor.log {
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

# logrotate 문법 검증 (dry-run)
sudo logrotate -d /etc/logrotate.d/agent-app >/dev/null 2>&1 \
    && echo "[OK] logrotate 문법 검증 통과" \
    || echo "[WARN] logrotate dry-run 경고 — 직접 실행해 확인"

# 2. agent-admin 의 crontab에 monitor.sh 매분 등록 (멱등)
# mktemp 기본 권한이 0600이라 agent-admin 이 못 읽음 → 0644 로 완화
# (lifespan 짧고 trap 으로 즉시 삭제되므로 안전)
TMPCRON=$(mktemp)
chmod 0644 "$TMPCRON"
trap "rm -f $TMPCRON" EXIT

# 기존 crontab에서 monitor.sh 줄과 환경 변수 라인 제거
sudo -u agent-admin crontab -l 2>/dev/null \
    | grep -v 'monitor\.sh' \
    | grep -v '^SHELL=' \
    | grep -v '^PATH=' \
    | grep -v '^MAILTO=' \
    > "$TMPCRON" || true

# 새 항목 추가
cat >> "$TMPCRON" <<'EOC'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
EOC

sudo -u agent-admin crontab "$TMPCRON"

echo "[OK] cron 등록 완료"
echo ""
echo "[검증] agent-admin 의 crontab"
sudo -u agent-admin crontab -l
