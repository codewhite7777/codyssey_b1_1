# Scripts Walkthrough — 줄별·문법 풀이

> 각 `.sh` 파일의 모든 줄·옵션·정규식을 처음 보는 사람도 이해할 수 있게 분해한 학습 자료. 옵션 표·Mermaid 다이어그램·회사 비유·FAQ 포함.

## 파일 목록

| 워크쓰루 | 코드 | 핵심 내용 |
|---|---|---|
| [01-ssh.md](./01-ssh.md) | [setup/01-ssh.sh](../../setup/01-ssh.sh) | sed 정규식 `^#\?`, sshd -t, /run/sshd 함정 |
| [02-firewall.md](./02-firewall.md) | [setup/02-firewall.sh](../../setup/02-firewall.sh) | ufw 화이트리스트, command -v, --force |
| [03-users-groups.md](./03-users-groups.md) | [setup/03-users-groups.sh](../../setup/03-users-groups.sh) | getent / id 검사, usermod -aG 의 -a 위험 |
| [04-directories.md](./04-directories.md) | [setup/04-directories.sh](../../setup/04-directories.sh) | chmod 8진수, setgid 2 비트, EACCES 검증 |
| [05-environment.md](./05-environment.md) | [setup/05-environment.sh](../../setup/05-environment.sh) | heredoc `<<'EOF'`, sed 범위 삭제, tee 패턴 |
| [06-cron.md](./06-cron.md) | [setup/06-cron.sh](../../setup/06-cron.sh) | logrotate 옵션, mktemp+trap, cron 형식 |
| [setup-all.md](./setup-all.md) | [setup/setup-all.sh](../../setup/setup-all.sh) | BASH_SOURCE, 절대 경로 확정, install 배포 |
| [verify.md](./verify.md) | [setup/verify.sh](../../setup/verify.sh) | check 함수 + eval, SIGPIPE × pipefail 함정 |
| [monitor.md](./monitor.md) | [bin/monitor.sh](../../bin/monitor.sh) | 9단계 흐름, cron 환경 회피, awk 자원 측정 |
| [report.md](./report.md) | [bin/report.sh](../../bin/report.sh) | awk BEGIN/본문/END, 동적 정규식, 통계 |

## 공통 구조

각 워크쓰루는 다음 구조를 따른다:

1. **한 줄 요약** + 코드·관련 학습 노트 링크
2. **전체 흐름 Mermaid** 다이어그램
3. **줄·블록별 옵션 분해** — 표 형식으로 명령·옵션·정규식 한눈에
4. **회사 비유** — 추상 개념을 일상 언어로
5. **자주 만나는 함정 (FAQ)** — 운영에서 만나는 실제 사고
6. **한 줄 정리**

## 활용 가이드

| 상황 | 추천 진입 |
|---|---|
| 평가자: 코드 빠르게 검토 | 코드 파일의 헤더 박스만 |
| 학습자: 처음 따라가며 이해 | 워크쓰루 → 코드 (양쪽 함께) |
| 자기평가 답변 작성 | 워크쓰루의 함정·이유 인용 |
| 회고 작성 | 워크쓰루의 미묘한 함정 → 회고 노트로 연계 |

## 다른 자료와의 관계

| 자료 | 깊이 | 차이 |
|---|---|---|
| `docs/spec.md` | 명세 원본 | Codyssey 원문 |
| `docs/spec-overview.md` | 명세 풀이 (의도) | 6 영역 무엇·왜·어떻게 |
| **`docs/scripts-walkthrough/`** ★ | **코드 풀이 (줄·문법)** | 이 폴더 |
| `codyssey_notes/codyssey_b1_1_study/` | 개념 풀이 | 21개 학습 노트 |
| `codyssey_notes/retrospectives/` | 트러블슈팅 | 6개 함정 |
