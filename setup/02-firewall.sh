#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/02-firewall.sh — ufw 방화벽 설정
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : ufw 를 활성화하고 SSH(20022) + agent-app(15034) 만 허용,
#          나머지 인바운드는 거부.
#  왜    : "필요한 문만 열고 나머지는 다 닫는다" 원칙 — 표적 면적 최소화.
#  멱등  : --force reset 으로 모든 룰 제거 후 재구성.
#  의존  : ufw 패키지 (없으면 자동 설치).
#
#  학습 노트: firewall-ufw-vs-firewalld, ports-and-listening
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/02-firewall.md
#  검증:
#    sudo ufw status verbose
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    command -v X         ─ 명령 X 가 PATH 에 있는지 (있으면 0, 없으면 1)
#    >/dev/null 2>&1      ─ stdout·stderr 모두 버림 (출력 silent)
#    ufw --force          ─ Y/n confirm 프롬프트 자동 yes
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

echo "===== [02/06] 방화벽 설정 ====="


# ─── 1) ufw 패키지 보장 ───────────────────────────────────────────
# minimal 이미지(OrbStack Ubuntu 등)는 ufw 누락 가능 → 자동 설치
if ! command -v ufw >/dev/null 2>&1; then
    echo "[INFO] ufw 설치 중..."
    sudo apt-get update -qq
    sudo apt-get install -y ufw
fi


# ─── 2) 멱등 초기화 (기존 룰 모두 제거) ───────────────────────────
# --force = "Resetting all rules..." 같은 confirm 프롬프트 우회
sudo ufw --force reset


# ─── 3) 기본 정책 ─────────────────────────────────────────────────
# incoming deny  ─ 외부에서 들어오는 트래픽은 명시 허용된 포트만
# outgoing allow ─ 내부에서 나가는 트래픽은 자유롭게 (apt, dns 등)
sudo ufw default deny incoming
sudo ufw default allow outgoing


# ─── 4) 명시 허용 포트 (명세 요구) ────────────────────────────────
# comment 는 status 출력 시 함께 표시 → 가독성·감사 용도
sudo ufw allow 20022/tcp comment 'SSH'
sudo ufw allow 15034/tcp comment 'agent-app'


# ─── 5) 활성화 ────────────────────────────────────────────────────
sudo ufw --force enable


echo "[OK] 방화벽 설정 완료"
echo ""
echo "[검증] ufw status verbose"
sudo ufw status verbose
