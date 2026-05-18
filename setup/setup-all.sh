#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/setup-all.sh — 모든 setup 스크립트 + 배포 + 검증 통합 실행
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : 7개 setup 스크립트(01~07)를 순차 실행한 후
#          monitor.sh·report.sh 를 $AGENT_HOME/bin 에 배포하고
#          verify.sh 로 자동 검증.
#  왜    : 평가자가 한 줄(setup-all.sh)로 전체 환경을 재현·검증할 수 있게.
#  멱등  : 각 sub 스크립트가 모두 idempotent → 여러 번 실행 안전.
#  사용  : sudo bash setup/setup-all.sh
#
#  학습 노트: 각 sub 스크립트의 학습 노트 참조.
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/setup-all.md
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    $(cmd)                     ─ 명령 치환 (cmd 의 stdout 을 문자열로)
#    $(dirname "$X")            ─ X 의 디렉토리 부분 (예: /a/b/c → /a/b)
#    $(cd DIR && pwd)           ─ 절대 경로 확정 (상대 경로 → 절대)
#    "${BASH_SOURCE[0]}"        ─ 현재 스크립트 파일 경로 ($0 보다 안전)
#    for x in A B C; do ...     ─ 리스트 순회
#    install -m M -o U -g G S D ─ cp + chmod + chown 한 번에
#                                  -m 권한, -o 소유자, -g 그룹, S source, D dest
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

# 스크립트 자신의 위치를 절대 경로로 확정 → 어디서 호출해도 동작
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "##############################################"
echo "# codyssey_b1_1 setup-all"
echo "# repo: $REPO_ROOT"
echo "##############################################"
echo ""


# ─── 0) gawk 보장 (bin/report.sh 의 match() 3번째 인자 의존성) ────
# Ubuntu default awk 는 mawk — match() 3번째 인자 미지원.
# report.sh 가 gawk 명시 호출하므로 gawk 패키지 필수.
if ! command -v gawk >/dev/null 2>&1; then
    echo ">>> gawk 설치 (report.sh 의존성)"
    sudo apt-get update -qq
    sudo apt-get install -y gawk
fi


# ─── 1) 7개 setup 스크립트 순차 실행 ──────────────────────────────
# 하나라도 실패하면 set -e 가 즉시 중단 → 부분 적용 상태 회피
# 07-sudoers : monitor.sh 의 ufw 점검을 위한 agent-admin NOPASSWD 룰
for script in 01-ssh.sh 02-firewall.sh 03-users-groups.sh \
              04-directories.sh 05-environment.sh 06-cron.sh \
              07-sudoers.sh; do
    echo ""
    echo ">>> 실행: setup/$script"
    bash "$SCRIPT_DIR/$script"
done


# ─── 2) monitor.sh·report.sh 배포 ─────────────────────────────────
# install 한 줄로 cp + chmod + chown 동시 처리
# 750 = rwxr-x---  : 소유자 모두, 그룹 read·execute, others 차단
echo ""
echo ">>> monitor.sh, report.sh 배포"
AGENT_BIN="/home/agent-admin/agent-app/bin"

sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/monitor.sh" "$AGENT_BIN/monitor.sh"
sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/report.sh"  "$AGENT_BIN/report.sh"
# log-rotate.sh — 보너스 2 시간 기반 보존 정책 (root 가 /etc/cron.d 로 호출)
sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/log-rotate.sh" "$AGENT_BIN/log-rotate.sh"

echo "[OK] $AGENT_BIN/monitor.sh, report.sh, log-rotate.sh 배포 완료"
ls -l "$AGENT_BIN/"


# ─── 3) 종합 검증 (verify.sh) ─────────────────────────────────────
echo ""
echo ">>> 전체 검증 (verify.sh)"
bash "$SCRIPT_DIR/verify.sh"


# ─── 4) 다음 단계 안내 ────────────────────────────────────────────
echo ""
echo "##############################################"
echo "# setup-all 완료"
echo "##############################################"
echo ""
echo "다음 단계 (수동):"
echo "  1. 제공 agent-app 바이너리를 \$AGENT_HOME/agent-app 에 배치 (chmod +x)"
echo "  2. 백그라운드 실행:"
echo "     sudo -u agent-admin -i bash -c 'nohup \$AGENT_HOME/agent-app > /dev/null 2>&1 &'"
echo "  3. 1-2분 대기 후 monitor.log 누적 확인:"
echo "     sudo tail /var/log/agent-app/monitor.log"
