#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/04-directories.sh — 디렉토리 구조 + 권한·소유자
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : AGENT_HOME 아래 5개 디렉토리(앱 루트·upload·api_keys·bin·로그)
#          를 생성하고 명세에 맞는 소유자·그룹·권한 설정.
#  왜    : 민감 자원(api_keys, /var/log) 은 agent-core 만,
#          공용 자원(upload_files) 은 agent-common 모두. 역할 분리 강제.
#          setgid 비트로 신규 파일이 부모 그룹 자동 상속 → 협업 안전.
#  멱등  : mkdir -p · chown · chmod 모두 idempotent.
#  의존  : 영역 3 (사용자·그룹) 먼저 실행되어 있어야 함.
#
#  학습 노트: file-permissions, filesystem-tree
#  검증:
#    ls -ld /home/agent-admin/agent-app/*
#    sudo -u agent-test ls .../api_keys   → EACCES 기대
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    mkdir -p X            ─ 부모 디렉토리도 함께 생성, 이미 있어도 OK
#    chown user:group X    ─ 소유자·그룹 변경
#    chmod NNN X           ─ 권한 (8진수)
#    chmod 2NNN X          ─ 앞의 '2' 가 setgid 비트
#
#  권한 표기 (chmod 8진수):
#    4 = read,  2 = write,  1 = execute
#    예) 770 = rwxrwx---  (소유자·그룹 RWX, 그 외 X)
#    예) 2770 = setgid + rwxrwx---
#
#  setgid 의 효과 (디렉토리에 적용 시):
#    해당 디렉토리 안에서 새로 만들어지는 파일·디렉토리가
#    부모 디렉토리의 '그룹' 을 자동 상속.
#    → 협업 시 모든 파일이 같은 그룹으로 묶여 권한 일관성 ↑
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"

echo "===== [04/06] 디렉토리·권한 ====="


# ─── 1) AGENT_HOME — 앱 루트 ──────────────────────────────────────
# 소유: agent-admin, 그룹: agent-core, 권한: 750 (others X)
sudo mkdir -p "$AGENT_HOME"
sudo chown agent-admin:agent-core "$AGENT_HOME"
sudo chmod 750 "$AGENT_HOME"


# ─── 2) upload_files — 공유 (agent-common, setgid) ────────────────
# admin·dev·test 모두 RW. setgid 로 신규 파일도 agent-common 상속.
sudo mkdir -p "$AGENT_HOME/upload_files"
sudo chown agent-admin:agent-common "$AGENT_HOME/upload_files"
sudo chmod 2770 "$AGENT_HOME/upload_files"   # 2=setgid, 770=rwxrwx---


# ─── 3) api_keys — 민감 자원 (agent-core ONLY) ────────────────────
# admin·dev 만 접근. test 는 그룹 멤버가 아니라 접근 차단.
sudo mkdir -p "$AGENT_HOME/api_keys"
sudo chown agent-admin:agent-core "$AGENT_HOME/api_keys"
sudo chmod 770 "$AGENT_HOME/api_keys"


# ─── 4) /var/log/agent-app — 모니터링 로그 ────────────────────────
# 신규 로그 파일이 agent-core 그룹 자동 상속 → logrotate 정책과 일치
sudo mkdir -p "$LOG_DIR"
sudo chown agent-admin:agent-core "$LOG_DIR"
sudo chmod 2770 "$LOG_DIR"


# ─── 5) bin — monitor.sh 위치 ─────────────────────────────────────
# 소유: agent-dev (dev 가 스크립트 관리), 그룹: agent-core
sudo mkdir -p "$AGENT_HOME/bin"
sudo chown agent-dev:agent-core "$AGENT_HOME/bin"
sudo chmod 750 "$AGENT_HOME/bin"


echo "[OK] 디렉토리·권한 설정 완료"
echo ""
echo "[검증] ls -ld"
ls -ld "$AGENT_HOME" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" \
       "$AGENT_HOME/bin" "$LOG_DIR"

echo ""
echo "[검증] agent-test 가 api_keys 접근 차단 (EACCES 기대)"
# || echo : 실패가 정상 케이스 (차단 의도) — || 로 "실패해도 OK" 표시
sudo -u agent-test ls "$AGENT_HOME/api_keys" 2>&1 || echo "  ✓ 정상 차단됨"
