# `setup/verify.sh` — 줄별·문법 풀이

> **한 줄로** · 명세 7개 영역 35개 항목을 `check` 함수로 자동 점검. 실패해도 끝까지 진행 + 종합 결과.
>
> **코드**: [setup/verify.sh](../../setup/verify.sh)
> **관련**: 회고 노트 [함정 3 (SIGPIPE × pipefail)](https://github.com/codewhite7777/codyssey_notes/blob/main/retrospectives/2026-05-12-b1-1-troubleshooting.md#함정-3--최대-발견-verifysh--직접-실행-ok-스크립트-안-fail)

## 🌳 전체 구조

```mermaid
flowchart LR
    A([check 함수 정의]) --> B([7개 영역 × 5개 평균])
    B --> C([실패 카운트])
    C --> D([종합 결과 + exit])

    style A fill:#dbe9ff,stroke:#5a8fc0,stroke-width:2px
    style B fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style D fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
```

---

## 안전 모드 — `set -u` 만 (pipefail X)

```bash
set -u
# 주의: pipefail 의도적 비활성
# check 함수의 cmd 안에서 `... | grep -q ...` 패턴을 자주 쓰는데,
# grep -q 가 첫 매칭에서 즉시 종료하면 앞 명령이 SIGPIPE(141)로 끝남.
# pipefail 켜져 있으면 이를 pipe 실패로 잡아 false negative 발생.
```

### 왜 다른 스크립트들과 달리 `-euo pipefail` 아닌 `-u` 만?

| 옵션 | setup 스크립트 (변경용) | verify.sh (검증용) |
|---|---|---|
| `-e` | ✅ 실패 즉시 종료 | ❌ **모든 항목 끝까지 검사** 필요 |
| `-u` | ✅ unset 변수 잡기 | ✅ 동일 |
| `pipefail` | ✅ 안전 | ❌ **SIGPIPE 함정 회피** |

### SIGPIPE 함정 (회고 함정 3)

```bash
sudo sshd -T | grep -q "^port 20022$"
```

- `sshd -T` 가 수백 줄 출력
- `grep -q` 가 첫 매칭에서 즉시 종료 (효율)
- `sshd -T` 가 다음 줄 쓰려 함 → broken pipe → **SIGPIPE → exit 141**
- `set -o pipefail` 켜져 있으면 이를 "pipe 실패" 로 잡아 → check FAIL (실제는 매칭 성공)

→ verify 에서는 `pipefail` 끄는 게 정답.

이 함정 발견·해결 과정 자체가 자기평가의 핵심 답변 재료 (회고 노트 참조).

---

## check 함수 — 검증의 핵심

```bash
PASS=0
FAIL=0
FAILED_ITEMS=()

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  [OK]   $desc"
        ((PASS++)) || true
    else
        echo "  [FAIL] $desc"
        FAILED_ITEMS+=("$desc")
        ((FAIL++)) || true
    fi
}
```

### `local X="..."` — 함수 지역 변수

`local` 없으면 변수가 **전역**이 되어 다른 함수·메인 로직과 충돌. 함수 안 변수는 항상 `local` 권장.

### `eval "$cmd"` — 문자열을 명령으로 평가

```bash
cmd='sudo sshd -T | grep -q "^port 20022$"'
eval "$cmd"
```

- `eval` 이 `$cmd` 의 값을 **셸 명령으로 재해석**
- 파이프·redirect 등 셸 메타문자가 평가됨
- 일반 변수 expand 와 다름 (변수만 expand 는 `$cmd` 그대로 실행하면 됨)

### 왜 `eval` 사용?

각 check 호출의 두 번째 인자는 **복잡한 명령 문자열**:
```bash
check "포트 20022 LISTEN" 'sudo ss -tulnp | grep -q ":20022 "'
```

이걸 그냥 `"$cmd"` 만 하면:
```bash
"$cmd"
# 결과: 'sudo ss -tulnp | grep -q ":20022 "' 라는 단일 명령으로 인식 → "command not found"
```

`eval` 이 셸 파싱을 한 번 더 거치게 해서 파이프·grep 패턴 모두 작동.

> [!WARNING]
> `eval` 은 임의 코드 실행 위험 (사용자 입력 X). 우리는 **하드코딩된 검증 명령** 이라 안전.

### `cmd >/dev/null 2>&1`

검증 명령의 출력은 우리 관심 X — exit code 만 본다. stdout·stderr 모두 버림.

### `((PASS++)) || true`

`((expr))` 는 산술 평가. `PASS++` 는 PASS 값 1 증가.

#### 함정 — `((0++))` 결과는 0 (false)

```bash
PASS=0
((PASS++))     # PASS 가 0 → 산술 결과 0 → exit 1 (false)
# set -e 켜져 있으면 여기서 종료
```

`|| true` 가 이 함정 회피.

근데 우리는 `set -e` 없음 (`-u` 만). 그래도 안전 습관으로 `|| true`.

### `FAILED_ITEMS+=("$desc")` — 배열 append

```bash
FAILED_ITEMS=()              # 빈 배열 초기화
FAILED_ITEMS+=("$desc")      # 끝에 요소 추가
echo "${FAILED_ITEMS[@]}"    # 모든 요소 펼침
echo "${#FAILED_ITEMS[@]}"   # 요소 개수
```

bash 배열 표기 — 다른 셸(예: dash)에서는 안 됨. `#!/usr/bin/env bash` shebang 필수.

---

## 35개 check 호출 — 7개 영역

각 영역은 `echo "===== [N] 영역명 ====="` 헤더 + 여러 check 호출.

```bash
check "사용자 agent-admin 존재" 'id agent-admin'
```

### check 패턴 — 단일 명령

```bash
check "설명" 'cmd'
```

cmd 가 exit 0 (성공) → [OK], 아니면 [FAIL].

### check 패턴 — 부정 (반전)

```bash
check "agent-test ∉ agent-core (기대 차단)" '! id -nG agent-test | grep -qw agent-core'
```

`!` 가 명령 exit code 반전 → **실패해야 통과** (test 가 core 그룹원이 *아니어야* OK).

### check 패턴 — `[ ... ]` test 명령

```bash
check "$AGENT_HOME 존재" "[ -d \"$AGENT_HOME\" ]"
```

#### `[ -d "$AGENT_HOME" ]`

- `[` 가 test 명령 (bash 빌트인)
- `-d` 디렉토리 존재 검사
- `"$AGENT_HOME"` 큰따옴표로 공백·특수문자 안전

#### Escape 함정

```bash
"[ -d \"$AGENT_HOME\" ]"
   └─ 안쪽 큰따옴표를 \"...\" 로 escape
```

이유: 바깥 큰따옴표 `"` 가 문자열 시작·끝 → 안에 또 `"` 가 있으면 escape 필요. 단일 char `\` 가 다음 `"` 를 literal 로.

### check 패턴 — 값 비교

```bash
check "키 파일 내용 정확" "[ \"\$(sudo cat \"$KEY_FILE\")\" = 'agent_api_key_test' ]"
```

복잡해 보이지만 풀면:
1. `\$(sudo cat "$KEY_FILE")` → 키 파일 내용 (예: `agent_api_key_test`)
2. `\"...\"` 로 감싸 공백 안전
3. `= 'agent_api_key_test'` 로 비교

`\$` 가 `$` escape — `eval` 시점에 expand 되도록 (define 시점이 아님).

### check 패턴 — stat 출력

```bash
check "monitor.sh 권한 750" "[ \"\$(stat -c %a \"$MONITOR\" 2>/dev/null)\" = '750' ]"
```

| 부분 | 의미 |
|---|---|
| `stat -c FORMAT FILE` | 파일 메타데이터를 FORMAT 으로 |
| `%a` | 권한 8진수 (예: 750) |
| `%U` | 소유자 이름 |
| `%G` | 그룹 이름 |

---

## 종합 결과

```bash
echo "##############################################"
echo "# 결과: PASS=$PASS, FAIL=$FAIL"
echo "##############################################"
if [ $FAIL -gt 0 ]; then
    echo ""
    echo "실패 항목:"
    for item in "${FAILED_ITEMS[@]}"; do
        echo "  - $item"
    done
    exit 1
fi
exit 0
```

### `if [ $FAIL -gt 0 ]; then` — 정수 비교

| 연산자 | 의미 |
|---|---|
| `-eq` | equal (= ) |
| `-ne` | not equal |
| `-gt` | greater than (>) |
| `-lt` | less than (<) |
| `-ge` | >= |
| `-le` | <= |

### `for item in "${FAILED_ITEMS[@]}"` — 배열 순회

`"${ARR[@]}"` 가 배열의 모든 요소를 **개별 인자**로 펼침. 큰따옴표 안에서도 각 요소가 분리 유지 (공백 포함된 요소 안전).

### exit code 의 의미

| exit | 의미 |
|---|---|
| 0 | 모두 통과 |
| 1+ | 1개 이상 실패 |

→ setup-all.sh 가 verify.sh 를 호출 후 exit code 로 성공·실패 자동 감지.

---

## 🏢 종합 회사 비유

| 단계 | 비유 |
|---|---|
| check 함수 | **표준 점검 양식** — 모든 항목 동일 형식으로 |
| eval | 양식의 "**조건**" 칸을 실제로 평가 |
| PASS/FAIL 카운트 | **점검 카드 통계** |
| 종합 결과 | 점검 종료 + **실패 항목 리스트** |

검증의 본질은 "**일관된 양식 + 자동 평가 + 종합 통계**" — verify.sh 가 한 페이지로 그 구조를 보여줌.

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| 직접 명령 OK, verify FAIL | **SIGPIPE × pipefail** (회고 함정 3) — 해결됨 |
| `((PASS++))` 가 set -e 발동 | PASS=0 일 때 산술 결과 0 → false. `\|\| true` 필수 |
| escape 헷갈림 | check cmd 문자열은 **eval 시점에 expand** — `\$`, `\"` escape 필요 |
| 한 항목 실패 후 종료 | `set -e` 활성 시 — verify 는 `-u` 만 쓰는 이유 |
| 빈 배열 순회 에러 | `"${ARR[@]:-}"` 같은 default 패턴 (우리는 빈 배열도 안전) |

---

## 🎯 한 줄 정리

> **check 함수 1개 + eval + 7 영역 35 호출** — 평가의 자동화·일관성을 한 페이지로. **pipefail 끄기**가 SIGPIPE 함정 회피의 핵심.
