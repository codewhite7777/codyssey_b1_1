# `bin/log-rotate.sh` — 줄별·문법 풀이

> **한 줄로** · 명세 §5 **보너스 2** "시간 기반 로그 보존 정책" 구현. `/var/log/agent-app/*.log` 중 **7일+ 경과** 파일을 gzip 압축해 `/var/log/monitor/agent-app/archive/` 로 이동, archive 의 **30일+ 경과** `.gz` 는 삭제. 디렉토리 미존재·권한 부족·0개 대상 모두 안전 처리.
>
> **코드**: [bin/log-rotate.sh](../../bin/log-rotate.sh)
> **관련 학습 노트**: [log-rotation](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/log-rotation.md), [find-options](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/find-options.md)
> **연관**: [06-cron.md](./06-cron.md) §4 (cron.d 등록), [sudo-policy.md](./sudo-policy.md) §1 (root 권한)

## 🌳 전체 흐름

```mermaid
flowchart LR
    A(["소스 디렉토리 존재?"]) -->|미존재| Z1(["WARN + exit 0"])
    A -->|존재| B(["archive/ 보장 mkdir -p"])
    B --> C(["find -mtime +7 → gzip → archive/"])
    C --> D(["find archive/ -mtime +30 → rm"])
    D --> E(["종합 카운트"])

    style A fill:#dbe9ff,stroke:#5a8fc0,stroke-width:2px
    style B fill:#fff3b0,stroke:#c0a35a,stroke-width:2px
    style C fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style D fill:#ffd6d6,stroke:#c05a5a,stroke-width:2px
    style E fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
    style Z1 fill:#f0f0f0,stroke:#888,stroke-width:1px
```

---

## 왜 logrotate 만으로는 부족했나

이미 `setup/06-cron.sh` 가 `/etc/logrotate.d/agent-app` 설정 (size 10M / rotate 10 / compress) 을 만들어. 그런데 **명세 §5 보너스 2** 의 요구는 다음 세 가지:

1. **7일 경과** 로그를 gzip 압축
2. 압축 결과를 **별도 디렉토리** (`/var/log/monitor/agent-app/archive/`) 로 이동
3. archive 의 **30일 경과** 파일 삭제

logrotate 한계:
- ✅ 시간 기반 회전: `daily` + `maxage 30` 가능
- ❌ 별도 디렉토리 이동: logrotate 는 같은 디렉토리에 `.gz` 만 둘 수 있음 (`olddir` 옵션 있지만 *고정 경로*, 시간 축 + 이동 조합 까다로움)
- ❌ 예외 처리 (디렉토리 미존재 → mkdir, 권한 부족 → 경고 후 계속): logrotate 는 missingok 외에 세밀한 fallback 없음

→ **별도 Bash 스크립트** + cron.d 일일 실행이 명세 의도에 가장 가까움.

> 두 정책의 직교: logrotate (크기 10M → 즉시 trim) ↔ log-rotate.sh (시간 7/30일 → 장기 housekeeping). **공존**하며 함께 동작.

---

## 섹션 1 — 안전 모드 + 환경 변수

```bash
set -uo pipefail   # -e 의도적 제외
export LC_ALL=C

: "${AGENT_LOG_DIR:=/var/log/agent-app}"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"
COMPRESS_AGE_DAYS=7
PURGE_AGE_DAYS=30
```

### 왜 `set -e` 제외?

| 옵션 | 의미 | 우리 선택 |
|---|---|---|
| `-u` | unset 변수 잡기 | ✅ |
| `-o pipefail` | pipe 안 실패도 잡기 | ✅ |
| `-e` | 명령 실패 시 즉시 종료 | ❌ — **부분 실패해도 housekeeping 계속** |

이유: 한 파일 gzip 실패 → 다음 파일은 처리해야 함. `-e` 켜면 첫 실패에서 전체 중단 → housekeeping 의 본질 위배. 대신 개별 명령마다 `|| log_err ...` 패턴으로 명시 처리.

### 환경 변수 default 패턴 `${X:=Y}`

| 표기 | 의미 |
|---|---|
| `${X}` | unset 이면 빈 문자열 (`-u` 켜져 있으면 에러) |
| `${X:-default}` | unset 이면 default 사용 (대입 X) |
| `${X:=default}` | unset 이면 default 사용 + **X 에도 대입** |
| `: "${X:=default}"` | `:` (no-op) + 위 + 결과 무시 → **default 보장 패턴** |

→ AGENT_LOG_DIR 이 cron 환경처럼 비어있어도 default 값으로 진행.

---

## 섹션 2 — 카운트 + 로깅 함수

```bash
COMPRESSED=0
MOVED=0
PURGED=0
WARNINGS=0
ERRORS=0

log_warn() { echo "[WARN] $*" >&2; WARNINGS=$((WARNINGS + 1)); }
log_err()  { echo "[ERROR] $*" >&2; ERRORS=$((ERRORS + 1)); }
log_info() { echo "[INFO] $*"; }
log_ok()   { echo "[OK] $*"; }
```

### `$((expr))` 산술 평가

| 표기 | 의미 |
|---|---|
| `$((a + b))` | a + b 결과 |
| `((var++))` | var 증가 (값 반환은 false 위험 → `$(())` 권장) |
| `X=$((X + 1))` | 명시적 대입 (가장 안전) |

여기선 `$((WARNINGS + 1))` 로 명시적 대입 — verify.sh 의 `((PASS++)) || true` 보다 명확.

### 로깅 분리 — stderr vs stdout

| 함수 | 출력 | 용도 |
|---|---|---|
| `log_info`, `log_ok` | stdout | 정상 흐름 — cron 의 redirect 로 log 파일에 기록 |
| `log_warn`, `log_err` | **stderr** (`>&2`) | 에러는 분리 — `2>&1` 없이 sterr 만 분리해 보고 가능 |

운영 관점: cron 의 `2>&1` 로 합쳐 한 파일에 들어가지만, 직접 호출 시 stderr 만 별도 redirect 가능.

---

## 섹션 3 — 소스 디렉토리 존재 확인

```bash
if [[ ! -d "$AGENT_LOG_DIR" ]]; then
    log_warn "소스 디렉토리 미존재: $AGENT_LOG_DIR — 처리할 로그 없음, 정상 종료"
    exit 0
fi
```

### `[[ ... ]]` vs `[ ... ]`

| 표기 | bash 지원 |
|---|---|
| `[ -d X ]` | POSIX 표준 (모든 sh) |
| `[[ -d X ]]` | bash 확장 — 정규식·논리 연산자 (`&&`, `\|\|`) 지원 |

여기선 단순 검사라 `[ ]` 도 OK 지만, 일관성 위해 `[[ ]]` 통일.

### exit 0 — 명세 "안전하게 종료"

명세 §5 보너스 2: *"디렉토리 미존재, 권한 부족, 대상 파일 0개 등에서 **안전하게 종료/경고**"*. → 실패가 아니라 *처리할 게 없음* 으로 봐서 exit 0. cron 이 fail mail 안 보냄.

---

## 섹션 4 — archive/ 디렉토리 보장

```bash
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    if mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
        chown root:agent-core "$ARCHIVE_DIR" 2>/dev/null || log_warn "chown 실패"
        chmod 2750 "$ARCHIVE_DIR" 2>/dev/null || log_warn "chmod 실패"
        log_ok "아카이브 디렉토리 생성"
    else
        log_err "아카이브 디렉토리 생성 실패 (권한 부족?)"
        exit 1
    fi
fi
```

### `mkdir -p` 멱등성

- `-p`: 상위 디렉토리도 함께 생성 + **이미 존재해도 에러 X** (멱등)
- `/var/log/monitor/` 가 없으면 함께 생성됨

### chmod 2750 — setgid + group access

| 비트 | 의미 |
|---|---|
| `2` (앞자리) | **setgid** — 디렉토리 안에 만들어지는 파일이 자동으로 agent-core 그룹 상속 |
| `7` | owner (root) rwx |
| `5` | group (agent-core) r-x |
| `0` | others 차단 |

→ archive 의 `.gz` 파일이 자동으로 `agent-core` 그룹 → agent-core 멤버 (agent-admin, agent-dev) 가 읽기 가능.

### 에러 시 단계별 분기

- `mkdir` 실패 → **Critical** (다음 단계 불가) → `exit 1`
- `chown`·`chmod` 실패 → **Warning** (그룹 부재 등) → 계속 진행

명세 *"권한 부족 → 안전하게 종료/경고"* 의 의미를 두 등급으로 분리 — 본질적 실패만 종료, 부속 작업 실패는 경고만.

---

## 섹션 5 — 7일+ 경과 압축·이동

```bash
TARGET_COUNT=0
while IFS= read -r -d '' file; do
    TARGET_COUNT=$((TARGET_COUNT + 1))
done < <(find "$AGENT_LOG_DIR" -maxdepth 1 -type f -name "*.log" \
             -mtime "+$COMPRESS_AGE_DAYS" -print0 2>/dev/null)

if [[ $TARGET_COUNT -eq 0 ]]; then
    log_info "  대상 파일 0개 — 압축 단계 skip"
else
    # 실제 처리 루프 ...
fi
```

### `find -mtime +N` 의 의미

| 표기 | 의미 |
|---|---|
| `-mtime +7` | 수정 시각 **7일 초과** (8일 전 이상) |
| `-mtime -7` | 7일 미만 (오늘 ~ 6일 전) |
| `-mtime 7` | 정확히 7일 전 |

명세는 *"7일 경과"* — 경계 모호하지만 안전한 해석 (`+7` 8일 전 이상). 너무 빠른 압축은 *currently-being-written* 위험.

### `-print0` + `while read -d ''` — 안전한 파일명 처리

```bash
# 위험 (공백·줄바꿈 있는 파일명에서 깨짐)
find ... | while read file; do ... done

# 안전 (NUL 구분자)
find ... -print0 | while IFS= read -r -d '' file; do ... done
```

| 옵션 | 의미 |
|---|---|
| `-print0` | NUL 문자 (`\0`) 로 파일명 구분 |
| `IFS=` | 단어 분리 비활성 |
| `read -r` | backslash escape 안 함 |
| `-d ''` | delimiter = NUL |

→ 파일명에 공백·줄바꿈·tab 있어도 안전.

### `< <(cmd)` Process Substitution

```bash
while ... done < <(find ...)
```

- `<(cmd)` 가 cmd 의 stdout 을 임시 파일처럼 만듦
- `< <(cmd)` 로 그걸 while 의 stdin 으로
- **subshell 회피** — `find ... | while ...` 은 while 이 subshell 이라 카운터가 부모에 안 보임

`TARGET_COUNT` 같은 변수를 루프 밖에서 쓰려면 이 패턴 필수.

### gzip + rm 직렬화

```bash
if gzip -c "$file" > "$archived" 2>/dev/null; then
    if rm "$file" 2>/dev/null; then
        chmod 0640 "$archived"
        COMPRESSED=$((COMPRESSED + 1))
    else
        log_warn "원본 삭제 실패 (다음 회전에 재시도): $file"
    fi
else
    log_err "gzip 실패: $file"
    rm -f "$archived" 2>/dev/null   # 부분 결과 정리
fi
```

처리 순서:
1. `gzip -c file > archived` — 압축 결과를 archive/ 에 *직접* 작성 (원본 그대로)
2. 성공 시 `rm file` — 원본 삭제
3. `chmod 0640` — others 차단

**원자성 보장**:
- gzip 성공 + rm 실패 → 원본 남음 (다음 회전 시 재시도) — *데이터 손실 X*
- gzip 실패 → archived 파일 제거 (부분 파일 청소)

→ "**압축본 보존 우선**" 정책. 어떤 실패에서도 데이터 손실 없음.

---

## 섹션 6 — 30일+ 경과 archive 삭제

```bash
while IFS= read -r -d '' file; do
    if rm "$file" 2>/dev/null; then
        log_ok "  삭제: $(basename "$file")"
        PURGED=$((PURGED + 1))
    else
        log_err "삭제 실패 (권한 부족?): $file"
    fi
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.gz" \
             -mtime "+$PURGE_AGE_DAYS" -print0 2>/dev/null)
```

### `-name "*.gz"` 만 — 안전 필터

archive/ 안에 다른 파일이 우연히 있어도 `.gz` 만 삭제. **실수로 다른 파일 날리는 사고 회피**.

### 30일+ 의미

법령·운영 정책에 따라 30일이 *최소 보존 기간* 인 경우 많음 (GDPR·SOX 등). 명세는 단순 housekeeping 이지만, 실무에선 이 기간이 *증거 자료 보존* 의무와 직결.

---

## 섹션 7 — 종합 결과 + exit code

```bash
echo "===== 종합 결과 ====="
echo "  압축·이동 : ${COMPRESSED}개"
echo "  삭제      : ${PURGED}개"
echo "  경고      : ${WARNINGS}건"
echo "  에러      : ${ERRORS}건"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
```

### exit code 정책

| 상황 | exit | cron 동작 |
|---|---|---|
| 모두 성공 | 0 | mail 안 보냄 |
| 경고만 (그룹 부재 등) | 0 | mail 안 보냄 (의도) |
| 에러 (gzip 실패·삭제 실패) | 1 | MAILTO 가 있으면 mail (우리는 ""로 차단) + journal 에 기록 |

명세 *"안전하게 종료/경고"* — 경고는 0, 에러는 1 로 차등 → 운영 모니터링에서 식별 가능.

---

## 🏢 종합 회사 비유

| 단계 | 비유 |
|---|---|
| 소스 디렉토리 확인 | "**보관 창고가 있나**" — 없으면 정상 종료 (할 일 없음) |
| archive 보장 | "**보관 캐비닛 준비**" — 없으면 자동 마련 |
| 7일+ 압축·이동 | "**오래된 서류 정리해서 캐비닛으로**" |
| 30일+ 삭제 | "**캐비닛도 너무 오래된 건 폐기**" |
| 종합 결과 | "**오늘 처리 일지**" — 몇 개 정리·삭제·경고·에러 |

운영의 housekeeping — 매일 03:00 새벽에 자동 실행. 사람이 하던 일을 cron 이 자동 수행.

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| `find -mtime` 와 *경과 일수* 의 미묘함 | `+N` 은 "N일 *초과*" — N일째 파일 포함 안 됨. 명세 "7일 경과" 의 경계 해석에 주의 |
| 파일명 공백·줄바꿈 | `-print0` + `read -d ''` 패턴 필수 |
| `while ... done < cmd` 의 subshell | 카운터 안 보임 — `< <(cmd)` process substitution 사용 |
| 부분 실패 시 데이터 손실 | gzip 성공 + rm 실패 → 원본 남기는 정책 (압축본 보존 우선) |
| logrotate 와 충돌 | size 기반 (logrotate) vs time 기반 (이 스크립트) 직교. 같은 파일을 둘이 동시에 만지지 않도록 회전 시점 분리 |
| `set -e` 켜면 housekeeping 중단 | `-uo pipefail` 만, `-e` 제외 — 부분 실패해도 끝까지 |
| cron.d 권한 0644 root:root 아님 | cron 데몬이 무시 — 우리는 `chmod 0644 + chown root:root` 명시 |

---

## 🔗 명세 매핑

| 명세 항목 (§5 보너스 2) | 이 스크립트의 구현 |
|---|---|
| "7일 경과 로그 압축" | `find -mtime +7 -name "*.log"` + `gzip -c` |
| 대상: `/var/log/agent-app/*.log` | `AGENT_LOG_DIR=/var/log/agent-app` |
| 아카이브 이동: `/var/log/monitor/agent-app/archive/` | `ARCHIVE_DIR=/var/log/monitor/agent-app/archive` |
| "30일 경과 아카이브 삭제" | `find -mtime +30 -name "*.gz"` + `rm` |
| "디렉토리 미존재 안전 종료" | 섹션 3 (exit 0) + 섹션 4 (mkdir -p) |
| "권한 부족 안전 처리" | 모든 명령에 `\|\| log_err`/`\|\| log_warn` + ERRORS 카운트 |
| "대상 파일 0개 안전" | `TARGET_COUNT == 0` 분기 → `log_info skip` + 다음 단계 |

---

## 🎯 한 줄 정리

> **find -mtime + gzip + 원자적 rm + 카운트 + 등급별 exit code** = 명세 보너스 2 의 *시간 기반 보존 정책* 을 logrotate 한계 없이 충실히 구현. 매일 03:00 cron.d 실행으로 무인 운영.
