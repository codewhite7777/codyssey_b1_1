# codyssey_b1_1 — 시스템 관제 자동화 스크립트

> Codyssey B1-1 과제 산출물 레포. 학습 노트는 별도 레포 [codyssey_notes](https://github.com/codewhite7777/codyssey_notes/tree/main/codyssey_b1_1_study)에 보관.

**상태**: 🟢 코드 작성 완료 — OrbStack 머신에서 테스트 대기

## 과제 개요

- **분야**: AI/SW 기초 · Linux와 OS
- **시간**: 40h
- **핵심**: 다중 사용자 Linux 환경에서 보안·권한·자원 관측을 자동화하는 운영 엔지니어링

자세한 명세는 [docs/spec.md](./docs/spec.md) 참조 (Codyssey 원본 verbatim 보존).

## 레포 구조

```
codyssey_b1_1/
├── README.md                # 이 파일
├── docs/
│   ├── spec.md              # Codyssey 원본 명세
│   └── 수행내역서.md         # 산출물 1 (구현 단계에서 작성)
├── bin/
│   ├── monitor.sh           # 핵심 산출물 ✓
│   └── report.sh            # 보너스 (로그 통계) ✓
├── setup/
│   ├── 01-ssh.sh            # SSH 포트·root 차단 ✓
│   ├── 02-firewall.sh       # ufw 설정 ✓
│   ├── 03-users-groups.sh   # 계정·그룹 생성 ✓
│   ├── 04-directories.sh    # 디렉토리·ACL ✓
│   ├── 05-environment.sh    # 환경 변수·키 파일 ✓
│   ├── 06-cron.sh           # cron + logrotate ✓
│   ├── setup-all.sh         # 통합 실행 + 배포 ✓
│   └── verify.sh            # 명세 검증 자동화 (35개 항목) ✓
├── evidence/                # 스샷·명령 출력 증거
└── .gitignore
```

## 사용 방법

### 평가 환경(클러스터 또는 OrbStack)에서

```bash
# 1. 레포 클론
git clone https://github.com/codewhite7777/codyssey_b1_1.git
cd codyssey_b1_1

# 2. 시스템 설정 일괄 적용 (sudo 필요)
sudo bash setup/setup-all.sh

# 3. agent-app 실행 (별도 터미널)
sudo -u agent-admin -i
python $AGENT_HOME/agent_app.py
# Ctrl+C로 종료

# 4. 1-2분 대기 후 cron 자동 실행 확인
sudo tail /var/log/agent-app/monitor.log

# 5. 종합 검증
bash setup/verify.sh
```

### 개별 단계 실행

```bash
sudo bash setup/01-ssh.sh         # SSH만
sudo bash setup/02-firewall.sh    # 방화벽만
# ... 등
```

### 보너스 — 로그 통계 리포트

```bash
bash bin/report.sh                                              # 전체 로그
bash bin/report.sh "2026-05-11 00:00" "2026-05-11 23:59"        # 시간 범위
```

## 설계 원칙

- **멱등성**: 모든 setup 스크립트는 여러 번 실행해도 동일 결과
- **`set -euo pipefail`**: 모든 스크립트가 안전 모드로 시작
- **명시적 sudo**: root 권한이 필요한 명령만 sudo
- **자동 검증**: setup-all.sh 끝에 verify.sh 자동 실행
- **cron 환경 함정 회피**: monitor.sh가 PATH·LC_ALL 명시

## 학습 노트 (별도 레포)

이 과제와 관련된 학습 자산은 [codyssey_notes/codyssey_b1_1_study/](https://github.com/codewhite7777/codyssey_notes/tree/main/codyssey_b1_1_study) 에 있다. Mermaid 다이어그램과 함께 다음 10개 주제 정리:

| Layer | 노트 |
|---|---|
| Linux Foundation | filesystem-tree, users-and-groups, file-permissions, shell-environment, process-and-signals |
| 보안 & 네트워킹 | ssh-deep-dive, sshd-config, ports-and-listening, firewall-ufw-vs-firewalld, posix-acl |

## 개발 환경

- Ubuntu 22.04 LTS (OrbStack Linux Machine 또는 동등)
- Bash (스크립트 작성 — Python 등 대체 금지)
- 일반 사용자 계정 (필요 시에만 sudo)

## 라이선스

학습 산출물 — 자유 참고.
