# `setup/04-directories.sh` — 줄별·문법 풀이

> **한 줄로** · 5개 디렉토리(AGENT_HOME·upload·api_keys·bin·로그) 생성 + 소유자·그룹·권한 설정. setgid 비트로 신규 파일이 부모 그룹 자동 상속.
>
> **코드**: [setup/04-directories.sh](../../setup/04-directories.sh)
> **관련 학습 노트**: [file-permissions](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/file-permissions.md), [filesystem-tree](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/filesystem-tree.md)

## 🌳 디렉토리 구조

```
AGENT_HOME = /home/agent-admin/agent-app
├── upload_files/   (2770, agent-common)  ← admin·dev·test 모두 RW
├── api_keys/       ( 770, agent-core)    ← admin·dev 만, test ❌
├── bin/            ( 750, agent-core)    ← monitor.sh 위치
└── (agent-app 바이너리)

/var/log/agent-app/  (2770, agent-core, setgid)  ← 로그 자동 상속
```

---

## 변수 정의

```bash
AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"
```

5번이나 반복되는 경로를 한 곳에 정의 → 변경 시 한 줄만 (DRY).

---

## 섹션 1·2·3·4·5 — 동일 패턴 (5개 디렉토리)

각 디렉토리마다 **3줄 패턴** 반복:

```bash
sudo mkdir -p "$AGENT_HOME"               # 1) 디렉토리 생성
sudo chown agent-admin:agent-core "$AGENT_HOME"   # 2) 소유자·그룹
sudo chmod 750 "$AGENT_HOME"              # 3) 권한
```

### 왜 3줄 분리? install 한 번에 안 했나?

`install` 명령은 **파일 복사용** — 디렉토리 생성에는 `install -d` 옵션이 있지만 권한 명시도 가능:
```bash
sudo install -d -m 750 -o agent-admin -g agent-core "$AGENT_HOME"
```

다만 가독성·디버깅 측면에서 **세 줄 분리가 명확**:
- 어느 단계가 실패했는지 즉시 보임
- mkdir 만 실행됐는지, chown 까지 됐는지 추적 쉬움

운영 표준 — 작업 분리(Separation of Concerns).

---

## `mkdir -p` — 멱등 디렉토리 생성

```bash
sudo mkdir -p "$AGENT_HOME"
```

| 옵션 | 의미 |
|---|---|
| `-p` | **p**arents — 부모도 자동 + 이미 있어도 에러 X |

### `-p` 가 멱등의 핵심

```bash
mkdir /home/agent-admin/agent-app       # /home/agent-admin 없으면: "No such file or directory"
                                         # 있으면: "File exists"
mkdir -p /home/agent-admin/agent-app    # 부모도 자동 생성, 있어도 OK
```

---

## `chown` — 소유자·그룹 변경

```bash
sudo chown agent-admin:agent-core "$AGENT_HOME"
```

| 부분 | 의미 |
|---|---|
| `chown` | **ch**ange **own**er |
| `agent-admin:agent-core` | `소유자:그룹` 형식 |
| `:` | 소유자와 그룹 구분 |

### 변형

```bash
chown USER FILE              # 소유자만 변경
chown :GROUP FILE            # 그룹만 변경
chown USER:GROUP FILE        # 둘 다
chown -R USER:GROUP DIR      # -R recursive (하위 모두)
```

### 왜 root 권한 필요?

- 소유자 변경은 **보안 민감** — 일반 사용자가 자기 파일을 다른 사용자에게 넘길 수 있으면 권한 우회 위험
- 모든 chown 명령은 **root 만 가능** → sudo 필수

---

## `chmod` — 권한 설정 (★ 핵심)

```bash
sudo chmod 750 "$AGENT_HOME"
sudo chmod 2770 "$AGENT_HOME/upload_files"
```

| 부분 | 의미 |
|---|---|
| `chmod` | **ch**ange **mod**e |
| `NNN` | 8진수 권한 (3 또는 4자리) |

### 8진수 권한 풀이

각 자리 = `r(4) + w(2) + x(1)` 합:

| 숫자 | 이진 | 의미 |
|---|---|---|
| 7 | rwx | 읽기·쓰기·실행 모두 |
| 6 | rw- | 읽기·쓰기 (실행 X) |
| 5 | r-x | 읽기·실행 (쓰기 X) |
| 4 | r-- | 읽기만 |
| 0 | --- | 없음 |

3자리 = 소유자 / 그룹 / 그 외:
```
   7        5        0
소유자    그룹     그 외
```

### `750` = `rwxr-x---`

| 누가 | 권한 |
|---|---|
| 소유자 (agent-admin) | rwx |
| 그룹 (agent-core) | r-x (읽기·실행, 수정 X) |
| 그 외 | 없음 |

### `2770` = setgid + `rwxrwx---`

```
2  7  7  0
│  │  │  └─ 그 외: 없음
│  │  └──── 그룹: rwx (수정 가능)
│  └─────── 소유자: rwx
└────────── ★ 4자리 모드: setuid/setgid/sticky bit
```

`2` 가 setgid (앞자리). 4자리 모드:
| 자리 | 비트 | 의미 |
|---|---|---|
| 4000 | setuid | (파일) 소유자 권한으로 실행 |
| 2000 | setgid | (디렉토리) **신규 파일 그룹 자동 상속** ★ |
| 1000 | sticky | (디렉토리) 자기 파일만 삭제 가능 (예: /tmp) |

---

## setgid 의 효과 (★ 명세 의도)

```mermaid
flowchart LR
    A([부모 디렉토리<br/>2770, agent-core]) -->|새 파일 생성| B([자동 그룹 상속<br/>agent-core])

    style A fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style B fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
```

### 왜 필요한가?

setgid 없으면:
```bash
# agent-admin 이 /var/log/agent-app/ 에 새 로그 생성
# 그 파일의 그룹 = agent-admin (agent-admin 의 1차 그룹)
# 결과: agent-core 그룹원(agent-dev)이 그 로그 접근 못 함 ← 협업 깨짐
```

setgid 있으면:
```bash
# 새 로그 그룹 = agent-core (부모 디렉토리 그룹 자동 상속)
# 결과: agent-dev 도 로그 접근 가능 ← 명세 의도 충족
```

### 회사 비유

"**이 폴더에 들어오는 새 문서는 자동으로 코어 부서 도장이 찍힘**" — setgid 디렉토리 효과. 직원(agent-admin)이 어디 소속이든, 그 폴더에 만든 문서는 코어 부서 자산.

---

## 5개 디렉토리 비교

| 디렉토리 | 소유자:그룹 | 권한 | 의미 |
|---|---|---|---|
| AGENT_HOME | agent-admin:agent-core | 750 | 앱 루트, others 차단 |
| upload_files | agent-admin:agent-common | 2770 | **공유** — 3명 모두 RW, setgid 상속 |
| api_keys | agent-admin:agent-core | 770 | 민감 자원, admin·dev 만 |
| /var/log/agent-app | agent-admin:agent-core | 2770 | **로그**, setgid 로 신규 파일 상속 |
| bin | agent-dev:agent-core | 750 | monitor.sh 위치, dev 가 관리 |

### 왜 디렉토리마다 다른 그룹?

| 디렉토리 | 그룹 선택 이유 |
|---|---|
| upload_files | **agent-common** — admin·dev·test 모두 RW 필요 (3명 공유) |
| api_keys | **agent-core** — admin·dev 만, test 차단 (민감) |
| /var/log | **agent-core** — 로그 무결성 위해 test 차단 |

→ 명세의 역할 분리(Separation of Duties) 가 디렉토리 그룹에 직접 반영.

---

## 검증 — `agent-test EACCES` (★ 명세 핵심)

```bash
sudo -u agent-test ls "$AGENT_HOME/api_keys" 2>&1 || echo "  ✓ 정상 차단됨"
```

### `sudo -u USER cmd` — 다른 사용자 권한으로 실행

| 부분 | 의미 |
|---|---|
| `sudo -u agent-test` | agent-test **권한으로** ls 실행 |
| `ls "$AGENT_HOME/api_keys"` | api_keys 디렉토리 보려고 시도 |
| `2>&1` | stderr 도 stdout 으로 합침 (에러 메시지도 보임) |
| `\|\| echo "✓ 정상 차단됨"` | **실패** 시 정상 메시지 |

### 왜 `|| echo` 가 정상?

이 검사는 **실패해야 통과**:
- agent-test 가 api_keys 접근 못 함 = 명세 의도 (test 는 agent-core 그룹원 X)
- ls 명령 실패 (`Permission denied`) → exit 1
- `||` 가 실패 시 메시지 출력
- 명령이 "성공"하면 오히려 명세 위반 (test 가 들어가버림)

기대 출력:
```
ls: cannot access '/home/agent-admin/agent-app/api_keys': Permission denied
  ✓ 정상 차단됨
```

→ **"실패"가 정답인 검사**.

---

## 🏢 종합 회사 비유

| 디렉토리 | 비유 |
|---|---|
| AGENT_HOME | 회사 본사 (루트) |
| upload_files | **공용 작업실** (모두 들어옴) |
| api_keys | **금고실** (코어 부서만) |
| /var/log | **기록 보관실 with 자동 도장** (setgid) |
| bin | **공구 보관실** (dev 가 관리) |

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| `chmod: invalid mode '2770'` | 매우 옛 chmod (POSIX 표준 안 따름) — 거의 없음 |
| setgid 적용 후 신규 파일에 미반영 | setgid 적용 **전에** 만든 파일은 그대로 — `chgrp -R` 로 일괄 변경 |
| `ls -ld` 에 `s` 보임 | `drwxrws---` 의 `s` 가 setgid 표시 (정상) |
| test 가 api_keys 들어감 | 03 단계에서 test 를 agent-core 에 잘못 추가 — 03 점검 |
| `-R` 없이 chmod 후 하위는 안 바뀜 | `chmod -R` 또는 `find ... -exec` 로 일괄 |

---

## 🎯 한 줄 정리

> **mkdir + chown + chmod 3종 세트**, 디렉토리별로 그룹·권한을 명세 의도(역할 분리)에 맞춤. **setgid 2 비트**가 신규 파일 그룹 자동 상속으로 협업 안전성 보장.
