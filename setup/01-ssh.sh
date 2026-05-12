#!/usr/bin/env bash
# setup/01-ssh.sh — SSH 포트 변경(20022) + Root 원격 차단
# 멱등: 여러 번 실행해도 동일 결과

set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"

echo "===== [01/06] SSH 설정 ====="

# 1. 포트를 20022로 변경 (주석 처리된 줄도 처리)
sudo sed -i 's/^#\?Port .*/Port 20022/' "$SSHD_CONFIG"

# 2. Root 원격 접속 차단
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"

# 3. /run/sshd 보장 (Ubuntu 24.04 신규 설치 환경 대응)
#    openssh-server 갓 설치되어 sshd 데몬이 한 번도 안 떴으면
#    /run/sshd 가 없어 'sshd -t' 가 "Missing privilege separation directory" 로 실패.
sudo mkdir -p /run/sshd

# 4. 문법 검증
if ! sudo sshd -t; then
    echo "[ERROR] sshd_config 문법 오류"
    exit 1
fi

# 5. 데몬 시작·재시작 (24.04 신규 환경은 첫 시작 필요)
sudo systemctl enable ssh 2>/dev/null || true
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd

echo "[OK] SSH 설정 적용 완료"
echo ""
echo "[검증] sshd -T 효과적 설정"
sudo sshd -T | grep -E '^(port|permitrootlogin)'

echo ""
echo "[검증] LISTEN 포트"
sudo ss -tulnp | grep ':20022' || echo "  (sshd 재시작 필요할 수 있음)"
