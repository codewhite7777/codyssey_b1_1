# codyssey_b1_1 — 시스템 관제 자동화 스크립트

> Codyssey B1-1 과제 산출물 레포. 학습 노트는 별도 레포 [codyssey_notes](https://github.com/codewhite7777/codyssey_notes/tree/main/codyssey_b1_1_study)에 보관.

**상태**: 🟡 학습 단계 — 구현 미시작

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
│   ├── monitor.sh           # 핵심 산출물 (구현 예정)
│   └── report.sh            # 보너스 (구현 예정)
├── setup/
│   ├── 01-ssh.sh            # SSH 포트·root 차단 (예정)
│   ├── 02-firewall.sh       # ufw 설정 (예정)
│   ├── 03-users-groups.sh   # 계정·그룹 생성 (예정)
│   ├── 04-directories.sh    # 디렉토리·ACL (예정)
│   ├── 05-environment.sh    # 환경 변수·키 파일 (예정)
│   ├── 06-cron.sh           # cron 등록 (예정)
│   ├── setup-all.sh         # 통합 실행 (예정)
│   └── verify.sh            # 명세 검증 자동화 (예정)
├── evidence/                # 스샷·명령 출력 증거
└── .gitignore
```

## 사용 방법 (구현 완료 후)

```bash
# 1. 클러스터 또는 평가 환경에서 클론
git clone https://github.com/codewhite7777/codyssey_b1_1.git
cd codyssey_b1_1

# 2. 시스템 설정 일괄 적용
sudo bash setup/setup-all.sh

# 3. 검증
bash setup/verify.sh

# 4. 모니터 스크립트 실행 (cron 또는 수동)
bash bin/monitor.sh
```

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
