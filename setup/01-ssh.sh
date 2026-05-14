#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/01-ssh.sh — SSH 보안 강화
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : sshd_config 를 수정해 SSH 포트를 22 → 20022 로 옮기고
#          root 의 직접 SSH 로그인을 차단한다.
#  왜    : 22 포트는 자동 brute-force 봇의 1순위 표적.
#          포트 이동으로 표면적을 줄이고, root 차단으로 깊이를 줄임.
#  멱등  : 여러 번 실행해도 동일 결과 (sed 가 idempotent).
#  의존  : openssh-server 설치 + /run/sshd 존재 (없으면 자동 생성).
#
#  학습 노트:
#    - ssh-deep-dive  : 명세 의도·SSH 동작 원리
#    - sshd-config    : 설정 파일 옵션 자세히
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/01-ssh.md
#  검증:
#    sudo sshd -T | grep -E '^(port|permitrootlogin)'
#    sudo ss -tulnp | grep ':20022 '
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    sed -i 's/OLD/NEW/'   ─ 파일 in-place 치환
#    정규식 ^#\?           ─ 줄 시작 + '#' 0개 또는 1개 (활성·주석 둘 다)
#    sshd -t               ─ sshd_config 문법만 검증 (실제 적용 X)
#    if ! cmd ; then       ─ cmd 실패 시(exit ≠ 0) 분기
#    systemctl enable X    ─ 재부팅 후 자동 시작 등록
#    systemctl restart X   ─ 데몬 재시작 (정지 후 시작)
#    cmd1 || cmd2          ─ cmd1 실패 시 cmd2 실행 (대체)
#    cmd >/dev/null 2>&1   ─ stdout·stderr 모두 버림 (silent)
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"

echo "===== [01/06] SSH 설정 ====="


# ─── 1) Port 20022 로 변경 ─────────────────────────────────────────
# 정규식 ^#\?Port 는 '활성된 Port' 와 '주석된 #Port' 둘 다 매칭
# → 어떤 초기 상태에서도 동일하게 'Port 20022' 로 만듦 (멱등)
sudo sed -i 's/^#\?Port .*/Port 20022/' "$SSHD_CONFIG"


# ─── 2) root 직접 SSH 로그인 차단 ──────────────────────────────────
# root 권한이 필요하면 일반 계정 → sudo 경로로 — 감사 로그·정책 통제 ↑
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"


# ─── 3) /run/sshd 보장 (Ubuntu 24.04 함정 대응) ────────────────────
# 24.04 갓 설치 환경에서 openssh-server 가 막 설치되었을 때
# sshd 데몬이 한 번도 안 뜨면 /run/sshd 디렉토리가 없음.
# 다음 단계의 'sshd -t' 가 "Missing privilege separation directory" 로
# 실패하는 함정 → mkdir 한 줄로 회피.
sudo mkdir -p /run/sshd


# ─── 4) sshd_config 문법 검증 ──────────────────────────────────────
# 'sshd -t' 는 실제 적용 없이 문법만 검사.
# 검증 안 하고 재시작하면 SSH 데몬이 깨져 원격 접속 끊김 위험.
if ! sudo sshd -t; then
    echo "[ERROR] sshd_config 문법 오류"
    exit 1
fi


# ─── 5) 데몬 시작·재시작 ───────────────────────────────────────────
# - enable : 재부팅 후 자동 시작
# - restart: 24.04 신규 환경은 sshd 가 안 떠 있어 reload 불가, restart 안전
# - || sshd: 패키지명이 ssh 아닌 sshd 인 배포판 호환
sudo systemctl enable ssh 2>/dev/null || true
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd


echo "[OK] SSH 설정 적용 완료"
echo ""
echo "[검증] sshd -T 효과적 설정"
sudo sshd -T | grep -E '^(port|permitrootlogin)'

echo ""
echo "[검증] LISTEN 포트"
sudo ss -tulnp | grep ':20022' || echo "  (sshd 재시작 필요할 수 있음)"
