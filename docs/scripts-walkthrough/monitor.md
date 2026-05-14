# `bin/monitor.sh` — 줄별·문법 풀이

> **한 줄로** · cron 이 매분 호출. health check 3단(프로세스·상태·포트) → 자원 측정 3종(CPU·MEM·DISK) → 임계값 경고 → monitor.log 한 줄 누적.
>
> **코드**: [bin/monitor.sh](../../bin/monitor.sh)
> **관련 학습 노트**: [process-and-signals](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/process-and-signals.md), [cpu-measurement](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/cpu-measurement.md), [memory-measurement](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/memory-measurement.md), [disk-usage-df-vs-du](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/disk-usage-df-vs-du.md)

## 🌳 전체 흐름

```mermaid
flowchart LR
    A(["1.프로세스"]) --> B(["2.상태"])
    B --> C(["3.포트 LISTEN"])
    C --> D(["4.방화벽"])
    D --> E(["5·6·7.자원"])
    E --> F(["8.임계값 경고"])
    F --> G(["9.로그 누적"])

    style A fill:#dbe9ff,stroke:#5a8fc0,stroke-width:2px
    style E fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style G fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
```

---

## cron 환경 함정 회피 (★ 운영 핵심)

```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C

: "${AGENT_HOME:=/home/agent-admin/agent-app}"
: "${AGENT_PORT:=15034}"
: "${AGENT_LOG_DIR:=/var/log/agent-app}"
```

### `export PATH=...` — PATH 명시

cron 은 `.bash_profile` 안 읽음. PATH 가 매우 빈약 (`/usr/bin:/bin` 만). awk·top 같은 도구를 못 찾을 수도 있음 → 명시.

### `export LC_ALL=C` — locale 고정

`LC_ALL=C` = "POSIX C locale 사용" = 영어 출력 강제.

```bash
# 한국어 locale 환경
$ date
2026년 5월 14일 화요일 15:30:00 KST

# LC_ALL=C
$ LC_ALL=C date
Tue May 14 15:30:00 KST 2026
```

awk·grep 등이 한국어 출력 파싱하려면 깨짐. 영어 강제로 **출력 형식 안정화**.

### `: "${VAR:=default}"` — 멱등 default

| 부분 | 의미 |
|---|---|
| `:` | bash 의 **no-op 명령** (아무것도 안 함, exit 0) |
| `"${VAR:=default}"` | VAR 가 unset/empty 면 default 할당 |

```bash
: "${AGENT_HOME:=/home/agent-admin/agent-app}"
# AGENT_HOME 가 unset → /home/agent-admin/agent-app 할당
# AGENT_HOME 가 set → 그대로 (덮어쓰지 않음)
```

### `${VAR:=}` vs `${VAR:-}`

| 형식 | 차이 |
|---|---|
| `${VAR:-default}` | VAR 없으면 default **사용** (변수에 할당 X) |
| `${VAR:=default}` | VAR 없으면 default **할당** (변수에 set) |

우리는 `:=` — 이후 줄에서 `$VAR` 사용하니 할당이 필요.

### `:` 명령이 왜 필요?

```bash
"${AGENT_HOME:=/home/...}"
# 이건 명령처럼 실행되지만 — bash가 expand 후 그 결과를 명령으로 처리
# AGENT_HOME 값 (예: /home/agent-admin/agent-app) → "command not found"
```

`:` 가 **앞에 와서** 명령으로 동작 → expansion 만 활용. 안전.

---

## 헬퍼 함수

```bash
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}
```

### `$(date '+FORMAT')`

| 토큰 | 의미 |
|---|---|
| `%Y` | 4자리 년 (2026) |
| `%m` | 2자리 월 (05) |
| `%d` | 2자리 일 (14) |
| `%H` | 2자리 시 (15) |
| `%M` | 2자리 분 (30) |
| `%S` | 2자리 초 (00) |

### `$*` — 모든 인자를 한 문자열로

| 변수 | 의미 |
|---|---|
| `$@` | 모든 인자 (개별 단어) |
| `$*` | 모든 인자 (한 문자열, IFS 로 결합) |
| `$#` | 인자 개수 |
| `$1`, `$2` | 위치 인자 |

`echo "[...] $*"` 는 함수의 모든 인자를 한 문자열로 출력.

### `>> FILE` — append redirect

| 표기 | 의미 |
|---|---|
| `> FILE` | **덮어쓰기** (기존 내용 삭제) |
| `>> FILE` | **추가** (끝에 붙임) |

로그는 항상 `>>` — 기존 라인 보존하면서 새 라인 추가.

---

## 섹션 1·2 — 프로세스 + 상태 검사

```bash
PID=$(pgrep -f "$APP_NAME" | head -1 || true)
if [ -z "$PID" ]; then
    echo "Checking process '$APP_NAME'... [FAIL]"
    log_to_file "[ALERT] agent-app 미실행"
    exit 1
fi

STATE=$(ps -o state= -p "$PID" 2>/dev/null | tr -d ' ' || echo "?")
case "$STATE" in
    R|S) ... ;;
    D)   ... ;;
    Z)   ... ;;
esac
```

### `pgrep -f PATTERN`

| 옵션 | 의미 |
|---|---|
| `pgrep` | process grep — 프로세스 검색 |
| `-f` | **f**ull command line — 명령줄 전체 매칭 (이름만 아님) |

```
명령줄 예: /home/agent-admin/agent-app/agent-app
pgrep -f "agent-app" → 이 PID 매칭
```

### `| head -1` — 첫 줄만

여러 PID 매칭 시 첫 번째만. 1개 프로세스 가정.

### `|| true` — 매칭 없을 때 set -e 회피

`pgrep` 가 매칭 없으면 exit 1 → set -e 발동. `|| true` 가 안전망.

### `[ -z "$PID" ]` — 빈 문자열 검사

| 옵션 | 의미 |
|---|---|
| `-z` | 빈 문자열 |
| `-n` | 비어있지 않음 |

PID 가 빈 문자열 → 프로세스 없음 → ALERT.

### `ps -o state= -p PID`

| 옵션 | 의미 |
|---|---|
| `-o state=` | 출력 형식: state 컬럼만, 헤더 없음 (`=` 끝) |
| `-p PID` | 특정 PID 만 |

### 프로세스 상태 글자

| 상태 | 의미 |
|---|---|
| R | Running — 실행 중 (정상) |
| S | Sleeping — 이벤트 대기 (정상) |
| D | Uninterruptible — I/O 대기 (잠시면 OK) |
| Z | Zombie — 종료됐는데 부모가 reap 안 함 (★ 문제) |
| T | Stopped — 일시 정지 |

### `tr -d ' '` — 공백 제거

`ps` 출력에 공백이 섞일 수 있음 → 제거.

### `case "$STATE" in PAT) ... ;; esac`

bash 의 패턴 분기:
```bash
case "$X" in
    PAT1) cmd1 ;;        # ;; 가 끝 표시
    PAT2|PAT3) cmd2 ;;   # | 가 또는
    *) default ;;        # * 가 모두 매칭 (마지막)
esac
```

### `R|S)` — Running 또는 Sleeping 정상 분기
### `D)` — uninterruptible 경고만
### `Z)` — zombie 는 ALERT + exit
### `*)` — 그 외 예상 못 한 상태 경고

---

## 섹션 3 — 포트 LISTEN 확인

```bash
if ss -tulnp 2>/dev/null | grep -q ":${AGENT_PORT} "; then
    echo "Checking port $AGENT_PORT... [OK]"
else
    echo "Checking port $AGENT_PORT... [FAIL]"
    log_to_file "[ALERT] port $AGENT_PORT not LISTEN"
    exit 1
fi
```

### `ss -tulnp` (verify.sh 와 동일 — 그 워크쓰루 참조)

### `":${AGENT_PORT} "` 패턴

`":15034 "` (포트 뒤 공백) — ss 출력에서 LISTEN 컬럼이 `0.0.0.0:15034` 같이 출력되고 다음에 공백. 공백 포함 매칭으로 `15034` 가 `:150341` 같이 일부만 매칭하는 함정 회피.

---

## 섹션 4 — 방화벽 상태 (경고만)

```bash
FW_STATUS="unknown"
if command -v ufw >/dev/null 2>&1; then
    if sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
        FW_STATUS="active"
    else
        FW_STATUS="inactive"
        echo "[WARNING] firewall (ufw) is not active"
    fi
elif command -v firewall-cmd ...
fi
```

### `sudo -n` — non-interactive

| 옵션 | 의미 |
|---|---|
| `-n` | **n**on-interactive — 비밀번호 prompt 절대 X (필요하면 즉시 실패) |

cron 으로 agent-admin 권한에서 실행되는데, agent-admin 은 sudo NOPASSWD 없음. `-n` 이라 비밀번호 안 묻고 즉시 실패 → ufw 상태 못 봄 → "inactive" 로 잘못 판정.

### 이게 false negative — 명세는 "[WARNING] 만" 이라 통과

명세는 "방화벽 비활성이면 WARN 만" 출력하라 함. 우리 코드가 그대로 동작 — 단지 *실제로는* active 인데 inactive 로 보고하는 점만 정확성 문제. exit 1 안 함.

(개선 옵션 — agent-admin 에게 `ufw status` 만 NOPASSWD 부여. 우선순위 낮음.)

---

## 섹션 5 — CPU 측정

```bash
CPU_USED_RAW=$(top -b -n 2 -d 0.5 2>/dev/null | grep "Cpu(s)" | tail -1 \
    | awk -F'id,' '{ if ($1) print 100 - $1 }' \
    | awk '{print $NF}')
CPU_USED="${CPU_USED_RAW:-0}"
CPU_USED_INT="${CPU_USED%.*}"
[ -z "$CPU_USED_INT" ] && CPU_USED_INT=0
```

### `top -b -n 2 -d 0.5` 옵션

| 옵션 | 의미 |
|---|---|
| `-b` | **b**atch 모드 — 인터랙티브 X, stdout 으로 출력 |
| `-n 2` | **2번** 측정 (첫 회 부정확) |
| `-d 0.5` | **d**elay 0.5초 |

### 왜 2번 측정?

`top` 의 CPU 사용률은 **두 시점의 차이**:
- 1회만 측정 → 시작 후 누적 평균 (부정확)
- 2회 측정 → 두 시점 차이 → **현재 순간** 사용률

→ **두 번째 측정의 Cpu 라인**이 진짜 데이터.

### `grep "Cpu(s)" | tail -1`

top 출력에 `%Cpu(s):  2.3 us, 0.8 sy, ...  96.7 id, ...` 라인. 2회 출력 중 마지막(2번째) 만.

### `awk -F'id,' '{print 100 - $1}'`

| 부분 | 의미 |
|---|---|
| `-F'id,'` | field separator = `'id,'` (idle 컬럼 표시) |
| `$1` | 첫 번째 field — `'id,'` 앞 = idle 비율 |
| `100 - $1` | idle 빼면 = **사용률** |

### `awk '{print $NF}'` — 마지막 토큰

`$NF` = **N**umber of **F**ields (마지막 필드 번호) → 가장 끝 토큰. 숫자만 추출.

### `"${CPU_USED_RAW:-0}"` — default 0

측정 실패 시 빈 문자열 → default 0.

### `"${CPU_USED%.*}"` — 소수점 자르기

| 표기 | 의미 |
|---|---|
| `${VAR%PATTERN}` | VAR 의 **끝에서** PATTERN 매칭 부분 제거 (짧게) |
| `${VAR%%PATTERN}` | 위와 비슷, **길게** 매칭 |
| `${VAR#PATTERN}` | VAR 의 **앞에서** 제거 (짧게) |
| `${VAR##PATTERN}` | 앞에서 길게 |

```bash
CPU_USED="25.3"
CPU_USED%.*    # "25" — '.숫자' 부분 제거
```

bash 의 **정수 비교** `-gt` 등이 소수점 처리 X → 정수로 변환.

### `[ -z "$CPU_USED_INT" ] && CPU_USED_INT=0`

빈 문자열 보호. `&&` 가 "앞 조건 참이면 다음 실행".

---

## 섹션 6 — MEM 측정

```bash
MEM_USED=$(free 2>/dev/null | awk '/^Mem:/ {if ($2 > 0) printf "%.1f", $3/$2 * 100; else print "0"}')
```

### `free` 명령

```
$ free
              total        used        free      shared  buff/cache   available
Mem:        8047872     2456320     4521236      157432     1070316     5180488
Swap:       2097148           0     2097148
```

| 컬럼 | 의미 |
|---|---|
| total | 전체 메모리 |
| used | 사용 중 |
| free | 진짜 비어있음 (보통 작음) |
| available | 회수 가능 포함 실제 여유 |

### `awk '/^Mem:/ {...}'`

| 부분 | 의미 |
|---|---|
| `/^Mem:/` | "Mem:" 으로 시작하는 줄만 |
| `{...}` | 그 줄에서 실행할 액션 |

### `printf "%.1f", $3/$2 * 100`

| 부분 | 의미 |
|---|---|
| `printf "%.1f"` | 소수점 1자리 |
| `$3/$2 * 100` | used / total × 100 = 사용률 % |

### `if ($2 > 0) ... else print "0"`

division by zero 방어. total 이 0 이면 0 출력.

---

## 섹션 7 — DISK 측정

```bash
DISK_USED=$(df / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')
```

### `df /`

```
$ df /
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/sda1       62749304  12345678  47340932  21% /
```

### `awk 'NR==2 {...}'`

| 부분 | 의미 |
|---|---|
| `NR` | **N**umber of **R**ecord — 현재 줄 번호 |
| `NR==2` | 두 번째 줄 (헤더 다음, 데이터 줄) |

### `gsub("%", "", $5)`

| 부분 | 의미 |
|---|---|
| `gsub` | **g**lobal **sub**stitute — 모든 매칭 치환 |
| `("%", "")` | "%" 를 "" (빈 문자열) 로 |
| `$5` | 5번째 필드 (Use%) |

→ `"21%"` → `"21"` (숫자만).

---

## 섹션 8 — 임계값 경고

```bash
WARN_COUNT=0
if [ "$CPU_USED_INT" -gt "$THRESH_CPU" ]; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USED}% > ${THRESH_CPU}%)"
    ((WARN_COUNT++)) || true
fi
# ... MEM, DISK 동일 패턴
if [ "$WARN_COUNT" -eq 0 ]; then
    echo "[INFO] All metrics within threshold"
fi
```

### `[ A -gt B ]` 정수 비교

verify.sh 와 동일.

### 임계값 명세

| 메트릭 | 임계값 |
|---|---|
| CPU | > 20% |
| MEM | > 10% |
| DISK | > 80% |

### WARN_COUNT 0 일 때 INFO 출력

모든 임계값 통과 → 한 줄 INFO. 매분 출력이 적당히.

---

## 섹션 9 — monitor.log 누적

```bash
log_to_file "PID:${PID} CPU:${CPU_USED}% MEM:${MEM_USED}% DISK_USED:${DISK_USED}%"
```

### 명세 포맷

```
[YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%
```

`log_to_file` 함수가 `[$(date)] $*` 형태로 prefix → 명세 포맷 정확히 일치.

---

## 🏢 종합 회사 비유

| 단계 | 비유 |
|---|---|
| 1. pgrep | "**감시 대상 직원이 출근했나?**" 사번 검색 |
| 2. ps state | "**의식 있나?**" 상태 확인 (좀비 X) |
| 3. ss LISTEN | "**상담 창구 열려 있나?**" |
| 5·6·7. 자원 | "**얼마나 일하고 있나?**" CPU·MEM·DISK 측정 |
| 8. 임계값 | "**과로 중이면 경고**" |
| 9. log | "**보고서에 매분 한 줄**" |

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| cron 에서 monitor.sh 실행 안 됨 | PATH 빈약 — 우리 PATH= export 가 해결 |
| 한국어 출력 깨짐 | locale 미고정 — LC_ALL=C export |
| AGENT_HOME unset | `.bash_profile` 안 읽힘 — `:= default` 패턴 |
| top 첫 회 부정확 | `-n 2` 로 두 번 측정 |
| ufw 상태 inactive 로 잘못 봄 | sudo NOPASSWD 부재 — false negative (명세 통과는 OK) |
| 소수점이 `-gt` 안 됨 | `${VAR%.*}` 로 정수 변환 |
| 로그 형식 명세와 다름 | log_to_file 함수에서 `[date] PID:.. CPU:..` 정확히 매핑 |

---

## 🎯 한 줄 정리

> **9단계 (health 3 + 자원 3 + 경고 + 로그 + 환경 setup)** 가 한 파일에 모두. cron 환경 함정 회피(`PATH`, `LC_ALL`, `:=default`)가 운영 자동화의 핵심 기반.
