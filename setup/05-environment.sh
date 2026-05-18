#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/05-environment.sh — 환경 변수 + API 키 파일
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : agent-admin 의 .bash_profile 에 AGENT_* 환경 변수 5개를
#          정의하고, api_keys/t_secret.key 키 파일을 생성·권한 설정.
#  왜    : 환경 변수로 실행 환경 고정 — 경로 하드코딩 회피, 유지보수 ↑.
#          SSH 로그인 시 .bash_profile 자동 source → 즉시 사용 가능.
#          키 파일은 0440 — agent-core 그룹만 read, 수정 차단.
#  멱등  : 기존 AGENT_ 라인·마커 블록 sed 로 제거 후 재추가.
#          키 파일은 if not exists 가드.
#  의존  : 영역 3·4 먼저 (agent-admin, api_keys 디렉토리 존재).
#
#  학습 노트: shell-environment, cron-environment-gotchas
#  ★ 줄별·문법 풀이: docs/scripts-walkthrough/05-environment.md
#  검증:
#    sudo -u agent-admin bash -lc 'env | grep ^AGENT_'   → 5개 변수
#    ls -l $AGENT_HOME/api_keys/t_secret.key             → 0440
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    tee FILE             ─ stdin 을 FILE 과 stdout 에 동시 출력
#    sudo tee -a FILE     ─ -a append (덮어쓰지 않고 끝에 추가)
#    >/dev/null           ─ stdout 버림 (tee 출력 안 보이게)
#    <<'EOF' ... EOF      ─ heredoc, 'EOF' (따옴표) = 변수 expand X
#    sed -i '/PAT/d'      ─ PAT 매칭 줄 삭제 (in-place)
#    sed -i '/A/,/B/d'    ─ A 매칭 줄부터 B 매칭 줄까지 블록 삭제
#    bash -lc 'CMD'       ─ -l: login 셸 (.bash_profile source),
#                           -c: 명령 실행
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

AGENT_HOME="/home/agent-admin/agent-app"
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
BASH_PROFILE="/home/agent-admin/.bash_profile"

echo "===== [05/06] 환경 변수·키 파일 ====="


# ─── 1) API 키 파일 생성 (멱등) ───────────────────────────────────
# 이미 있으면 그대로 두고 권한만 재설정 (덮어쓰지 않음)
if [ ! -f "$KEY_FILE" ]; then
    echo "agent_api_key_test" | sudo tee "$KEY_FILE" >/dev/null
    echo "[OK] 키 파일 생성: $KEY_FILE"
else
    echo "[SKIP] 키 파일 이미 존재: $KEY_FILE"
fi

# 0440 = r--r----- : 소유자·그룹 read 만, write 도 차단 (실수 보호)
sudo chown agent-admin:agent-core "$KEY_FILE"
sudo chmod 440 "$KEY_FILE"


# ─── 2) .bash_profile 정화 (기존 AGENT_ 라인·마커 제거) ───────────
# touch  ─ 파일이 없으면 빈 파일 생성, 있으면 mtime 갱신
sudo touch "$BASH_PROFILE"

# 기존 'export AGENT_...' 라인 모두 삭제
sudo sed -i '/^export AGENT_/d' "$BASH_PROFILE"

# 마커 블록 ('# --- agent-app env ---' ~ '# --- end ... ---') 삭제
# → 여러 번 실행해도 중복 X (멱등)
sudo sed -i '/^# --- agent-app env ---/,/^# --- end agent-app env ---/d' "$BASH_PROFILE"


# ─── 3) .bash_profile 에 환경 변수 영구 등록 ──────────────────────
# heredoc <<'EOF' : 작은따옴표 EOF → $VAR 전혀 expand 안 됨 (그대로 기록)
# $AGENT_HOME 같은 변수는 사용자가 SSH 접속 시 셸이 expand 함
sudo tee -a "$BASH_PROFILE" >/dev/null <<'EOF'

# --- agent-app env ---
export AGENT_HOME="/home/agent-admin/agent-app"
export AGENT_PORT="15034"
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
export AGENT_LOG_DIR="/var/log/agent-app"
[ -f ~/.bashrc ] && . ~/.bashrc
# --- end agent-app env ---
EOF

# 권한 0640 — owner read/write + group read + others 차단
# 이유: AGENT_KEY_PATH (.../api_keys/t_secret.key) 경로가 이 파일에 노출.
#       0644 (others read) 면 agent-test 등 다른 사용자가 키 위치를 알 수 있음
#       → 정보 누출 (CWE-200). 키 자체는 0440 agent-core 라 탈취 불가지만,
#       경로 노출만으로도 *공격 표면 확대*. 0640 으로 others 차단.
sudo chown agent-admin:agent-admin "$BASH_PROFILE"
sudo chmod 0640 "$BASH_PROFILE"


echo "[OK] 환경 변수 등록 완료"
echo ""
echo "[검증] 새 login 셸에서 AGENT_ 변수 확인"
# bash -lc : login 셸 흉내내 .bash_profile 자동 source
sudo -u agent-admin bash -lc 'env | grep ^AGENT_'

echo ""
echo "[검증] 키 파일 내용·권한"
sudo -u agent-admin cat "$KEY_FILE"
ls -l "$KEY_FILE"
