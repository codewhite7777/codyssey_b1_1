# `setup/setup-all.sh` — 줄별·문법 풀이

> **한 줄로** · 6개 setup 스크립트(01~06) 순차 실행 + monitor.sh·report.sh 배포 + verify.sh 검증 통합 실행. 평가자가 한 줄로 전체 환경 재현.
>
> **코드**: [setup/setup-all.sh](../../setup/setup-all.sh)

## 🌳 전체 흐름

```mermaid
flowchart LR
    A(["01~06 순차 실행"]) --> B(["monitor.sh·report.sh 배포"])
    B --> C(["verify.sh 35개 검증"])
    C --> D(["다음 단계 안내"])

    style A fill:#dbe9ff,stroke:#5a8fc0,stroke-width:2px
    style B fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style C fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
```

---

## 스크립트 위치 자동 감지

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
```

### `"${BASH_SOURCE[0]}"` — 현재 스크립트 경로

| 표현 | 의미 |
|---|---|
| `BASH_SOURCE` | bash 의 특수 배열 — 현재 실행 중인 파일 경로 스택 |
| `[0]` | 첫 번째 (가장 위, 즉 현재 스크립트) |

`$0` 와 비슷하지만 더 안전:
- `source X` 로 실행 시 `$0` 은 호출자 이름, `BASH_SOURCE[0]` 은 X
- 함수 안에서도 정확

### `dirname FILE` — 디렉토리 부분

```
dirname /home/user/setup/setup-all.sh
→ /home/user/setup
```

### `$(cd DIR && pwd)` — 절대 경로 확정

```bash
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

해석 (안쪽부터):
1. `dirname "${BASH_SOURCE[0]}"` → 스크립트의 디렉토리 (상대일 수도)
2. `cd "..."` → 그 디렉토리로 이동
3. `&& pwd` → 현재 디렉토리의 **절대 경로** 출력
4. `$( ... )` → 그 결과를 문자열로

→ **호출 방법(상대 경로·심볼릭 링크 등)에 무관하게 절대 경로 확정**.

회사 비유: "**자기 위치를 GPS 좌표로 확정**" — 어디서 호출되든 동일하게 동작.

### `REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`

setup 폴더의 부모 = 레포 루트. 같은 패턴.

---

## 6개 setup 순차 실행

```bash
for script in 01-ssh.sh 02-firewall.sh 03-users-groups.sh \
              04-directories.sh 05-environment.sh 06-cron.sh; do
    echo ""
    echo ">>> 실행: setup/$script"
    bash "$SCRIPT_DIR/$script"
done
```

### `for x in A B C \` 다중 라인

`\` 가 줄 끝에 있으면 다음 줄로 명령 이어짐 (가독성).

### `set -e` 와의 상호작용

`bash "$SCRIPT_DIR/$script"` 가 실패 (exit ≠ 0) 하면:
- `set -e` 가 발동 → setup-all.sh 즉시 종료
- **부분 적용 상태로 끝나지 않음** (다음 스크립트 안 돌음)
- 어느 단계 실패인지 마지막 출력으로 즉시 보임

→ 안전한 패턴. 04 까지 통과 후 05 가 실패하면 06·배포·verify 모두 안 돌음 → 일관성 보장.

---

## monitor.sh·report.sh 배포

```bash
AGENT_BIN="/home/agent-admin/agent-app/bin"

sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/monitor.sh" "$AGENT_BIN/monitor.sh"
sudo install -m 750 -o agent-dev -g agent-core \
    "$REPO_ROOT/bin/report.sh"  "$AGENT_BIN/report.sh"
```

### `install` 명령 — cp + chmod + chown 한 번에

| 옵션 | 의미 |
|---|---|
| `-m 750` | 권한 모드 (rwxr-x---) |
| `-o agent-dev` | 소유자 |
| `-g agent-core` | 그룹 |

(자세한 분해는 README "agent-app install" 부분 참조.)

### 왜 `setup-` 폴더 가 아닌 `bin/` 으로 배포?

| 위치 | 의미 |
|---|---|
| 레포 `bin/monitor.sh` | 소스 (git 추적) |
| VM `$AGENT_HOME/bin/monitor.sh` | **실행 위치** (cron 이 호출) |

명세는 `$AGENT_HOME` 안 구조를 요구 → 배포 단계가 그 위치로 복사 + 권한 설정.

### 소유자가 agent-dev 인 이유

| 디렉토리·파일 | 소유자 | 이유 |
|---|---|---|
| AGENT_HOME 자체 | agent-admin | 앱 운영 책임 |
| AGENT_HOME/bin | **agent-dev** | **스크립트 관리 책임** |
| monitor.sh | **agent-dev** | dev 가 코드 변경 권한 |

명세의 역할 분리 — 운영(admin)과 개발(dev) 분리.

---

## verify.sh 자동 실행

```bash
echo ">>> 전체 검증 (verify.sh)"
bash "$SCRIPT_DIR/verify.sh"
```

setup 끝에 verify 를 **자동 실행** — 평가자가 별도 호출 불필요. setup-all.sh 한 줄로 전체 검증까지 완료.

`set -e` 활성 → verify.sh 가 실패하면 setup-all.sh 도 실패 종료 → 마지막 PASS=N 출력 후 종료 코드 1.

---

## 다음 단계 안내 (echo 만)

```bash
echo "다음 단계 (수동):"
echo "  1. 제공 agent-app 바이너리를 \$AGENT_HOME/agent-app 에 배치"
echo "  2. 백그라운드 실행:"
echo "     sudo -u agent-admin -i bash -c 'nohup \$AGENT_HOME/agent-app > /dev/null 2>&1 &'"
echo "  3. 1-2분 대기 후 monitor.log 누적 확인:"
```

### `echo "\$AGENT_HOME"` 의 `\$`

| 문자열 | 출력 |
|---|---|
| `"$VAR"` | $VAR 의 값으로 expand |
| `"\$VAR"` | **`$VAR` 글자 그대로** (escape) |
| `'$VAR'` | `$VAR` 글자 그대로 (작은따옴표) |

여기선 사용자에게 보여주는 안내문 — `$AGENT_HOME` 글자 그대로 보여야 (사용자가 그 명령을 복붙해 실행할 때 자기 셸에서 expand).

---

## 🏢 종합 회사 비유

| 단계 | 비유 |
|---|---|
| 위치 확정 | "**자기 GPS 좌표 확인**" — 어디서 호출되든 일관 |
| 6개 순차 실행 | **6단계 신설 프로세스** 순차 진행 — 중간 실패 시 즉시 중단 |
| 배포 | **운영 도구를 정식 위치로 이전** + 권한 도장 |
| 검증 | **35개 항목 자체 점검** — 평가자 시점 미리 |
| 안내 | "**다음 사람이 할 일**" 메모 남기기 |

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| 일부 단계만 실행 후 종료 | set -e 발동 — 어디서 실패했는지 마지막 출력 확인 |
| `bash setup-all.sh` 가 다른 경로 실패 | `SCRIPT_DIR` 자동 감지로 회피 |
| install 권한 부족 | sudo 누락 — 우리 명령에 포함됨 |
| verify.sh 가 통과하다 일부 FAIL | setup 중 어디서 누락 — 멱등이라 재실행 안전 |
| 안내문에 `$AGENT_HOME` 이 expand 됨 | `\$` escape 누락 |

---

## 🎯 한 줄 정리

> **6 스크립트 순차 + 2 바이너리 배포 + 35 검증 + 안내 = 평가자가 한 줄로 전체 환경 재현하는 통합 진입점.**
