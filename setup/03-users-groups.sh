#!/usr/bin/env bash
# setup/03-users-groups.sh — 계정·그룹 생성·할당
# 멱등: 존재 여부 확인 후 생성, 그룹 가입은 -aG로 누적

set -euo pipefail

echo "===== [03/06] 계정·그룹 ====="

# 1. 그룹 생성
for group in agent-common agent-core; do
    if getent group "$group" >/dev/null 2>&1; then
        echo "[SKIP] group $group 이미 존재"
    else
        sudo groupadd "$group"
        echo "[OK] group $group 생성"
    fi
done

# 2. 사용자 생성 (홈 디렉토리 + bash 셸)
for user in agent-admin agent-dev agent-test; do
    if id "$user" >/dev/null 2>&1; then
        echo "[SKIP] user $user 이미 존재"
    else
        sudo useradd -m -s /bin/bash "$user"
        echo "[OK] user $user 생성"
    fi
done

# 3. 그룹 멤버십 할당 (-aG로 멱등)
sudo usermod -aG agent-common,agent-core agent-admin
sudo usermod -aG agent-common,agent-core agent-dev
sudo usermod -aG agent-common agent-test

echo "[OK] 그룹 멤버십 할당 완료"
echo ""
echo "[검증] 각 사용자 id 출력"
for u in agent-admin agent-dev agent-test; do
    id "$u"
done

echo ""
echo "[검증] 그룹 멤버 목록"
for g in agent-common agent-core; do
    echo "  $g: $(getent group "$g" | cut -d: -f4)"
done
