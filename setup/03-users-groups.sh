#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  setup/03-users-groups.sh — 계정·그룹 생성 + 멤버십 할당
# ═══════════════════════════════════════════════════════════════════
#
#  무엇  : 사용자 3명(admin/dev/test) + 그룹 2개(common/core) 생성하고
#          멤버십을 정책에 맞게 할당.
#  왜    : 역할 분리(Separation of Duties) — 사용자별 접근 범위 차등.
#          admin/dev 는 민감 자원(core), test 는 공용 자원(common)만.
#  멱등  : id·getent 로 존재 확인 후 분기, usermod -aG 는 누적 추가.
#  의존  : 시스템 기본 도구(useradd, groupadd, usermod, id, getent).
#
#  학습 노트: users-and-groups, posix-acl
#  검증:
#    id agent-admin       → 그룹 목록에 common + core
#    id agent-test        → common 만, core 없음
# ═══════════════════════════════════════════════════════════════════
#
#  쓰인 셸 문법:
#    for x in A B C; do ... done    ─ 리스트 순회
#    getent group X >/dev/null 2>&1 ─ 그룹 X 존재 검사 (있으면 0)
#    id X >/dev/null 2>&1           ─ 사용자 X 존재 검사
#    useradd -m -s /bin/bash X      ─ -m: 홈 생성, -s: 로그인 셸 지정
#    usermod -aG g1,g2 X            ─ -a 누적 추가, -G 보조 그룹들
#    cut -d: -f4                    ─ ':' 구분자로 4번째 필드 추출
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

echo "===== [03/06] 계정·그룹 ====="


# ─── 1) 그룹 생성 (멱등) ──────────────────────────────────────────
# getent: /etc/group, NIS, LDAP 등 통합 조회 → 그룹 존재 여부 확인
for group in agent-common agent-core; do
    if getent group "$group" >/dev/null 2>&1; then
        echo "[SKIP] group $group 이미 존재"
    else
        sudo groupadd "$group"
        echo "[OK] group $group 생성"
    fi
done


# ─── 2) 사용자 생성 (홈 디렉토리 + bash 셸) ───────────────────────
# -m 없으면 /home/X 디렉토리 안 만들어짐 → SSH 로그인 시 cd 실패
for user in agent-admin agent-dev agent-test; do
    if id "$user" >/dev/null 2>&1; then
        echo "[SKIP] user $user 이미 존재"
    else
        sudo useradd -m -s /bin/bash "$user"
        echo "[OK] user $user 생성"
    fi
done


# ─── 3) 그룹 멤버십 할당 ──────────────────────────────────────────
# -a (append) 없이 -G 만 쓰면 기존 보조 그룹이 모두 사라짐 (위험)
# 즉 -aG 가 표준 멱등 패턴
sudo usermod -aG agent-common,agent-core agent-admin
sudo usermod -aG agent-common,agent-core agent-dev
sudo usermod -aG agent-common              agent-test
# ↑ test 에게는 core 부여 X — 민감 자원 접근 차단이 명세 요구


echo "[OK] 그룹 멤버십 할당 완료"
echo ""
echo "[검증] 각 사용자 id 출력"
for u in agent-admin agent-dev agent-test; do
    id "$u"
done

echo ""
echo "[검증] 그룹 멤버 목록"
# /etc/group 형식: <name>:<x>:<gid>:<member1,member2,...>
# 4번째 필드만 추출 → 멤버 목록 표시
for g in agent-common agent-core; do
    echo "  $g: $(getent group "$g" | cut -d: -f4)"
done
