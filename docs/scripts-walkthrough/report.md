# `bin/report.sh` — 줄별·문법 풀이

> **한 줄로** · monitor.log 의 라인을 파싱해 CPU·MEM·DISK 평균·최대·최소 + 최대 시점 통계 출력. awk 한 패스로 처리. 선택적 시간 범위 필터.
>
> **코드**: [bin/report.sh](../../bin/report.sh)
> **관련 학습 노트**: [cron-fundamentals](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/cron-fundamentals.md), [log-rotation](https://github.com/codewhite7777/codyssey_notes/blob/main/codyssey_b1_1_study/log-rotation.md)

## 🌳 전체 흐름

```mermaid
flowchart LR
    A([파일 존재 확인]) --> B([시간 범위 필터])
    B --> C([샘플 수 카운트])
    C --> D([CPU/MEM/DISK 각각 통계])
    D --> E([출력])

    style A fill:#dbe9ff,stroke:#5a8fc0,stroke-width:2px
    style D fill:#ffe6cc,stroke:#c08f5a,stroke-width:2px
    style E fill:#ccffcc,stroke:#5ac08f,stroke-width:2px
```

---

## 사용 패턴

```bash
report.sh                                   # 전체 로그
report.sh "2026-05-11 00:00" "..."          # 시작 시각만
report.sh "..." "2026-05-11 23:59"          # 종료 시각만
report.sh "2026-05-11 00:00" "2026-05-11 23:59"   # 범위
```

---

## 환경 setup

```bash
set -euo pipefail
export LC_ALL=C

: "${AGENT_LOG_DIR:=/var/log/agent-app}"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"
```

`LC_ALL=C` — date·awk 출력 안정화 (monitor.sh 와 동일).

`AGENT_LOG_DIR:= default` — cron 또는 직접 호출 모두 대응.

---

## 파일 존재 확인

```bash
if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] log 파일이 없습니다: $LOG_FILE" >&2
    exit 1
fi
```

### `[ ! -f FILE ]`

`!` 부정 + `-f` 일반 파일 → "파일이 **없으면**".

### `>&2` — stderr 로

| 표기 | 의미 |
|---|---|
| `>&2` | stdout → stderr 로 redirect |
| `1>&2` | 동일 |
| `2>&1` | 역방향 |

에러 메시지는 **stderr 로** — 정상 출력(stdout)과 분리 → pipe·redirect 시 에러만 따로 처리 가능.

---

## 시간 범위 인자

```bash
START="${1:-}"
END="${2:-}"
```

### `"${1:-}"` — 위치 인자 + default 빈 문자열

| 표기 | 의미 |
|---|---|
| `$1` | 첫 번째 위치 인자 |
| `${1:-}` | `$1` 이 없거나 빈 문자열 → 빈 문자열 (set -u 회피) |
| `${1:-default}` | `$1` 이 없으면 default |

`set -u` 활성 시 `$1` 이 없으면 에러 → `${1:-}` 가 회피.

---

## 시간 범위 필터링 (awk)

```bash
if [ -n "$START" ] || [ -n "$END" ]; then
    FILTERED=$(awk -v s="$START" -v e="$END" '
        {
            match($0, /\[([0-9-]+ [0-9:]+)\]/, m)
            ts = m[1]
            if (ts == "") next
            if (s != "" && ts < s) next
            if (e != "" && ts > e) next
            print
        }
    ' "$LOG_FILE")
else
    FILTERED=$(cat "$LOG_FILE")
fi
```

### `[ -n "$X" ] || [ -n "$Y" ]` — OR 조건

| 부분 | 의미 |
|---|---|
| `-n` | 비어있지 않음 |
| `\|\|` | 또는 (OR) |

→ START 또는 END 중 하나라도 있으면 필터링.

### `awk -v VAR="value"` — awk 변수 전달

bash 변수를 awk 안으로 가져옴. 쌍따옴표 안의 `$X` 가 expand 되어 awk 에게 전달.

### awk 흐름 — `BEGIN / 본문 / END`

```awk
BEGIN { 초기화; 한 번만 }
{ 매 라인마다 실행 }
END { 마지막에 한 번만 }
```

여기선 `{ ... }` (본문) 만 사용 — 매 라인 처리.

### `match($0, /REGEX/, ARR)` — 정규식 매칭 + 캡처

| 부분 | 의미 |
|---|---|
| `$0` | 현재 라인 전체 |
| `/...../` | 정규식 |
| `ARR` (gawk 확장) | 캡처 그룹을 ARR 배열에 |

정규식 `\[([0-9-]+ [0-9:]+)\]` 분해:
- `\[` 글자 그대로 `[`
- `(` 캡처 시작
- `[0-9-]+` 숫자·`-` 하나 이상
- ` ` 공백
- `[0-9:]+` 숫자·`:` 하나 이상
- `)` 캡처 끝
- `\]` 글자 그대로 `]`

→ `[2026-05-14 15:30:00]` 같은 타임스탬프 캡처.

`m[1]` = 첫 번째 캡처 그룹 (= `2026-05-14 15:30:00`).

### `if (조건) next`

awk 의 `next` = "**다음 라인으로**" (현재 라인 처리 중단).

```awk
if (ts == "") next       # 타임스탬프 없으면 skip
if (s != "" && ts < s) next   # 시작 이전이면 skip
if (e != "" && ts > e) next   # 종료 이후면 skip
print
```

→ 시간 범위 안의 라인만 출력.

### 왜 `ts < s` 가 문자열 비교로 작동?

타임스탬프 형식 `YYYY-MM-DD HH:MM:SS` 는 **사전식(lexical) 정렬이 시간 정렬과 일치**:
- `2026-05-13` < `2026-05-14` (사전식 정렬) = 시간 순
- 자릿수 고정 (`05`, `13` 같이 0 패딩)

→ awk 의 일반 문자열 비교(`<`, `>`)로 시간 비교 가능. 별도 date 파싱 불필요. 이 형식 선택이 의도된 설계.

### `$(cat "$LOG_FILE")` — 파일 전체 읽기

bash 명령 치환. 결과를 변수에 담음. 작은 로그는 OK, 큰 로그는 메모리 부담.

---

## 샘플 수

```bash
SAMPLES=$(echo "$FILTERED" | wc -l)
```

### `echo "$FILTERED" | wc -l` — 줄 수

| 부분 | 의미 |
|---|---|
| `echo "$X"` | X 를 stdout 으로 |
| `wc -l` | **w**ord **c**ount, **l**ines (줄 수) |

---

## 통계 함수 — `compute_stats`

```bash
compute_stats() {
    local metric="$1"
    local label="$2"
    echo "$FILTERED" | awk -v m="$metric" -v label="$label" '
        BEGIN { min_v=999999; max_v=-1; sum=0; count=0; max_ts=""; min_ts="" }
        {
            match($0, /\[([0-9-]+ [0-9:]+)\]/, t)
            ts = t[1]
            if (match($0, m ":([0-9.]+)", v)) {
                val = v[1] + 0
                sum += val; count++
                if (val > max_v) { max_v = val; max_ts = ts }
                if (val < min_v) { min_v = val; min_ts = ts }
            }
        }
        END {
            if (count > 0) {
                printf "  [%s]\n", label
                printf "    Average : %.1f%%\n", sum/count
                printf "    Maximum : %s%% at %s\n", max_v, max_ts
                printf "    Minimum : %s%% at %s\n", min_v, min_ts
            } else {
                printf "  [%s] (데이터 없음)\n", label
            }
        }
    '
}
```

### 함수 + awk 결합 패턴

bash 함수 안에서 awk 호출. metric/label 을 함수 인자로 → awk 변수로 전달 → awk 가 다르게 동작.

### `BEGIN` 블록 — 초기화

```awk
BEGIN { min_v=999999; max_v=-1; sum=0; count=0; max_ts=""; min_ts="" }
```

| 변수 | 초기값 | 이유 |
|---|---|---|
| `min_v=999999` | 매우 큰 값 | 실제 값보다 항상 커야 첫 비교에서 갱신됨 |
| `max_v=-1` | 음수 | 실제 값보다 항상 작아야 첫 비교에서 갱신됨 |
| `sum=0`, `count=0` | 누적용 | 평균 계산 |

### `m ":([0-9.]+)"` — 동적 정규식

| 부분 | 의미 |
|---|---|
| `m` | awk 변수 (CPU / MEM / DISK_USED) |
| `m ":"` | 변수 + 글자 (문자열 연결) |
| `([0-9.]+)` | 숫자·점 하나 이상 (캡처) |

```
m="CPU" → 정규식 "CPU:([0-9.]+)" → "CPU:25.3%" 에서 "25.3" 캡처
```

### `val = v[1] + 0` — 문자열을 숫자로

awk 에서 `+ 0` 은 **타입 변환** — 문자열 `"25.3"` → 숫자 `25.3`. 비교·계산에 필요.

### `printf "%.1f%%"` — 출력 형식

| 토큰 | 의미 |
|---|---|
| `%.1f` | 소수점 1자리 float |
| `%s` | 문자열 |
| `%%` | 글자 그대로 `%` (이스케이프) |

### END 블록 — 종합 결과 출력

```awk
END {
    if (count > 0) {
        printf "  [%s]\n", label
        printf "    Average : %.1f%%\n", sum/count
        printf "    Maximum : %s%% at %s\n", max_v, max_ts
        printf "    Minimum : %s%% at %s\n", min_v, min_ts
    }
}
```

모든 라인 처리 후 한 번만 실행. 평균·최대·최소 + 최대·최소 시점 출력.

---

## 함수 호출 + 출력

```bash
echo "====== STATISTICS REPORT ======"
[ -n "$START" ] && echo "  Range: $START ~ ${END:-now}"
echo ""

compute_stats "CPU"        "CPU"
compute_stats "MEM"        "Memory"
compute_stats "DISK_USED"  "Disk"

echo "  [Samples]"
echo "    Data Points: $SAMPLES samples"
```

### `[ -n "$START" ] && echo ...` — 조건부 출력

START 가 있으면 Range 라인 출력. 없으면 skip.

### `${END:-now}` — default "now"

END 가 없으면 "now" 출력. 사용자에게 의미 전달.

---

## 출력 예시

```
====== STATISTICS REPORT ======
  Range: 2026-05-14 00:00 ~ now

  [CPU]
    Average : 75.3%
    Maximum : 100% at 2026-05-14 15:30:01
    Minimum : 20% at 2026-05-14 00:01:01
  [Memory]
    Average : 6.5%
    Maximum : 12.3% at 2026-05-14 14:20:01
    Minimum : 4.1% at 2026-05-14 00:05:01
  [Disk]
    Average : 1%
    Maximum : 1% at 2026-05-14 00:01:01
    Minimum : 1% at 2026-05-14 00:01:01
  [Samples]
    Data Points: 850 samples
```

---

## 🏢 종합 회사 비유

| 단계 | 비유 |
|---|---|
| 파일 확인 | **보고서 파일 있는지** |
| 시간 필터 | "**지난 주 데이터만**" 자르기 |
| compute_stats | **메트릭별 통계 표** 자동 작성 |
| 출력 | "**경영 대시보드**" 한 페이지 |

분 단위 로그가 누적되면 사람이 읽기 어려움 — report.sh 가 추세를 요약. 운영 대시보드의 기본.

---

## 🧪 자주 만나는 함정

| 함정 | 원인·해결 |
|---|---|
| `match(...,...,arr)` 안 됨 | gawk 확장 — mawk 에선 다른 문법 — `gawk` 명시 또는 awk 대안 |
| 시간 비교가 안 됨 | 타임스탬프 형식이 사전식 정렬 가능해야 (`YYYY-MM-DD HH:MM:SS`) |
| 빈 로그 파일 | `[ -z "$FILTERED" ]` 검사 후 안내 |
| 평균이 0 | count==0 — 메트릭 형식이 코드와 안 맞음 |
| 큰 로그에서 느림 | `cat "$LOG_FILE"` 전체 메모리 — 대용량은 stream 처리로 개선 |

---

## 🎯 한 줄 정리

> **awk 한 패스로 라인별 파싱 + 통계 계산**. 사전식 정렬 가능한 ISO 시간 형식이 awk 문자열 비교로 시간 필터링을 가능케 함.
