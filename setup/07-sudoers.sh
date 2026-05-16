#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/07-sudoers.sh — agent-admin 의 ufw status NOPASSWD 룰
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : /etc/sudoers.d/agent-admin-monitor 에 한 줄 룰을 작성.
#            agent-admin ALL=(ALL) NOPASSWD: /usr/sbin/ufw status
#          → agent-admin 이 비밀번호 없이 'sudo ufw status' 만 허용.
#  왜    : monitor.sh 가 명세 §"상태 점검" 요구대로 방화벽 활성 여부를
#          점검하려면 'sudo ufw status' 가 필요. agent-admin 은 기본
#          sudoer 가 아니라 sudo 호출이 실패하고 false WARNING 이 남.
#          → 운영 함정 (회고 노트: monitor.sh-sudo-n-false-warning).
#  멱등  : tee 로 파일을 덮어쓰고 visudo -c 로 문법 검증 후 권한 0440.
#  의존  : visudo (sudo 패키지에 포함).
#
#  ★ 보안 설계 (최소 권한 원칙):
#    - 명령 범위: /usr/sbin/ufw status 하나만 (enable/disable/delete 등 X)
#    - 사용자 범위: agent-admin 만
#    - 비밀번호: NOPASSWD — cron / non-tty 환경에서 prompt 차단 회피
#    - 파일 권한: 0440 (sudoers 표준, root 만 읽기·수정)
#
#  학습 노트: sudo-and-sudoers
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/07-sudoers.md
#  관련 카테고리: docs/scripts-walkthrough/sudo-policy.md §"방화벽 검사"
#
#  검증:
#    sudo -u agent-admin sudo -n ufw status   # 비밀번호 prompt 없이 통과
#    ls -l /etc/sudoers.d/agent-admin-monitor # -r--r----- root root
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    SUDOERS_FILE=...           ─ 상수 변수 (대문자 관례)
#    sudo tee FILE              ─ stdout 을 sudo 권한으로 파일에 기록
#    >/dev/null                 ─ tee 의 stdout 미러를 버려 화면 silent
#    sudo visudo -cf FILE       ─ -c check, -f 파일 지정 (문법 검증)
#                                  실패 시 비-0 반환 → set -e 가 중단
#    sudo chmod 0440 FILE       ─ sudoers.d 표준 권한 (r--r-----)
#    sudo chown root:root FILE  ─ root 소유 강제 (편집 권한 보호)
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

echo "===== [07/07] sudoers (agent-admin → ufw status NOPASSWD) ====="

SUDOERS_FILE="/etc/sudoers.d/agent-admin-monitor"
RULE='agent-admin ALL=(ALL) NOPASSWD: /usr/sbin/ufw status'


# ─── 1) 룰 작성 (멱등 — 매번 덮어씀) ──────────────────────────────
# sudoers.d 의 파일은 main /etc/sudoers 가 include 함.
# 별도 파일로 분리하면 → 추가/삭제가 main 파일 손상 위험 없이 가능.
sudo tee "$SUDOERS_FILE" >/dev/null <<EOF
# codyssey_b1_1 — monitor.sh 의 방화벽 점검 지원
# 명세: monitor.sh 가 'sudo ufw status' 로 ufw 활성 여부를 점검 (§상태 점검)
# 범위: agent-admin 사용자가 'ufw status' 명령만 비밀번호 없이 호출
$RULE
EOF


# ─── 2) 문법 검증 (★ 필수) ────────────────────────────────────────
# 잘못된 sudoers 는 시스템 sudo 사용 자체를 막을 수 있음 (락아웃 위험).
# visudo -cf 가 비-0 반환하면 set -e 가 즉시 중단 → 잘못된 파일이 활성 X.
if ! sudo visudo -cf "$SUDOERS_FILE"; then
    echo "[FAIL] sudoers 문법 오류 — 파일 제거 후 종료"
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi


# ─── 3) 권한 정리 (sudoers.d 표준 0440 + root 소유) ───────────────
# sudo 는 sudoers.d 의 파일 권한이 0440 이 아니면 무시 (보안 정책).
sudo chown root:root "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"


# ─── 4) 실작동 확인 (★ 통과해야 monitor.sh false WARNING 해결) ────
# agent-admin 으로 sudo -n ufw status 를 호출 → 종료 코드 0 이어야 정상.
# monitor.sh 가 정확히 이 방식으로 호출함 (bin/monitor.sh:136).
if sudo -u agent-admin sudo -n /usr/sbin/ufw status >/dev/null 2>&1; then
    echo "[OK] agent-admin 이 비밀번호 없이 'sudo ufw status' 호출 가능"
else
    echo "[FAIL] agent-admin 의 sudo -n ufw status 실패 — 룰이 활성화되지 않음"
    exit 1
fi


echo "[OK] sudoers 설정 완료 → $SUDOERS_FILE"
echo ""
echo "[검증]"
ls -l "$SUDOERS_FILE"
