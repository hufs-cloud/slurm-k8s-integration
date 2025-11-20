#!/bin/bash
# install.sh - Slurm-K8s 통합 시스템 자동 설치 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Slurm-K8s Integration System Installer${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}" 
   echo "Please run: sudo ./install.sh"
   exit 1
fi

# 1. 사전 요구사항 확인
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"

# Slurm 설치 확인
if ! command -v scontrol &> /dev/null; then
    echo -e "${RED}Error: Slurm is not installed${NC}"
    exit 1
fi
echo "✓ Slurm installed"

# K8s 설치 확인
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi
echo "✓ kubectl installed"

# Python packages 확인 및 설치
echo "Installing Python packages..."
pip install --user inotify pyyaml
echo "✓ Python packages installed"

# jq 확인 및 설치
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    apt-get install -y jq
fi
echo "✓ jq installed"

# 2. 스크립트 설치
echo ""
echo -e "${YELLOW}[2/6] Installing scripts...${NC}"

# 현재 디렉토리 확인
if [[ ! -f "slurm_k8s_prolog.sh" ]]; then
    echo -e "${RED}Error: Script files not found in current directory${NC}"
    echo "Please run this script from the cloned repository directory"
    exit 1
fi

# Shell 스크립트들
cp slurm_k8s_prolog.sh /usr/local/bin/
cp slurm_k8s_epilog.sh /usr/local/bin/

# Python 스크립트들
cp job_validator.py /usr/local/bin/
cp job_watcher.py /usr/local/bin/
cp run_watcher.py /usr/local/bin/

# 실행 권한 부여
chmod +x /usr/local/bin/slurm_k8s_prolog.sh
chmod +x /usr/local/bin/slurm_k8s_epilog.sh
chmod +x /usr/local/bin/job_validator.py
chmod +x /usr/local/bin/job_watcher.py
chmod +x /usr/local/bin/run_watcher.py

echo "✓ Scripts installed to /usr/local/bin/"

# 3. 로그 디렉토리 생성
echo ""
echo -e "${YELLOW}[3/6] Creating log directories...${NC}"

mkdir -p /var/log/slurm-k8s
chown slurm:slurm /var/log/slurm-k8s
chmod 755 /var/log/slurm-k8s

echo "✓ Log directory created: /var/log/slurm-k8s"

# 4. NAS 디렉토리 생성
echo ""
echo -e "${YELLOW}[4/6] Setting up NAS directories...${NC}"

# NAS 마운트 확인
if ! mountpoint -q /mnt/test-k8s 2>/dev/null; then
    echo -e "${YELLOW}Warning: /mnt/test-k8s is not mounted${NC}"
    echo "Please ensure NAS is mounted before running jobs"
else
    mkdir -p /mnt/test-k8s/slurm-jobs/submit
    mkdir -p /mnt/test-k8s/slurm-jobs/processed
    mkdir -p /mnt/test-k8s/slurm-jobs/failed
    mkdir -p /mnt/test-k8s/results
    mkdir -p /mnt/test-k8s/scripts
    
    chmod 755 /mnt/test-k8s/slurm-jobs/*
    chmod 755 /mnt/test-k8s/results
    
    echo "✓ NAS directories created"
fi

# 5. Job Watcher 서비스 설정
echo ""
echo -e "${YELLOW}[5/6] Setting up job-watcher service...${NC}"

cat > /etc/systemd/system/slurm-job-watcher.service <<EOF
[Unit]
Description=Slurm Job Watcher
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/run_watcher.py
Restart=always
User=slurm
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slurm-job-watcher

echo "✓ Job watcher service configured"

# 6. Slurm 설정 확인
echo ""
echo -e "${YELLOW}[6/6] Checking Slurm configuration...${NC}"

if ! grep -q "Prolog=/usr/local/bin/slurm_k8s_prolog.sh" /etc/slurm/slurm.conf 2>/dev/null; then
    echo -e "${YELLOW}Warning: Prolog not configured in /etc/slurm/slurm.conf${NC}"
    echo "Please add the following lines to /etc/slurm/slurm.conf:"
    echo ""
    echo "  Prolog=/usr/local/bin/slurm_k8s_prolog.sh"
    echo "  Epilog=/usr/local/bin/slurm_k8s_epilog.sh"
    echo "  PrologEpilogTimeout=600"
    echo ""
    echo "See slurm.conf.example for full configuration"
    SLURM_CONFIG_NEEDED=true
else
    echo "✓ Slurm Prolog/Epilog configured"
    SLURM_CONFIG_NEEDED=false
fi

# 설치 완료
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 다음 단계 안내
echo -e "${YELLOW}Next Steps:${NC}"
echo ""

if [[ "$SLURM_CONFIG_NEEDED" == "true" ]]; then
    echo "1. Update Slurm configuration:"
    echo "   sudo nano /etc/slurm/slurm.conf"
    echo "   (See slurm.conf.example for reference)"
    echo ""
    echo "2. Restart Slurm controller:"
    echo "   sudo systemctl restart slurmctld"
    echo ""
    echo "3. Start job watcher:"
    echo "   sudo systemctl start slurm-job-watcher"
    echo ""
else
    echo "1. Restart Slurm controller:"
    echo "   sudo systemctl restart slurmctld"
    echo ""
    echo "2. Start job watcher:"
    echo "   sudo systemctl start slurm-job-watcher"
    echo ""
fi

echo "4. Test the installation:"
echo "   sbatch example-job.sh"
echo ""
echo "5. Check status:"
echo "   squeue"
echo "   kubectl get pods -l app=slurm-job"
echo ""

echo -e "${GREEN}For detailed usage, see QUICK_START.md${NC}"
echo ""

# 설치 요약 로그 저장
cat > /var/log/slurm-k8s/installation.log <<EOF
Installation Date: $(date)
Installation User: $(whoami)
Scripts Installed:
  - /usr/local/bin/slurm_k8s_prolog.sh
  - /usr/local/bin/slurm_k8s_epilog.sh
  - /usr/local/bin/job_validator.py
  - /usr/local/bin/job_watcher.py
  - /usr/local/bin/run_watcher.py

Directories Created:
  - /var/log/slurm-k8s/
  - /mnt/test-k8s/slurm-jobs/submit/
  - /mnt/test-k8s/slurm-jobs/processed/
  - /mnt/test-k8s/slurm-jobs/failed/
  - /mnt/test-k8s/results/

Service Configured:
  - slurm-job-watcher.service

Slurm Configuration: $(if [[ "$SLURM_CONFIG_NEEDED" == "true" ]]; then echo "Manual update required"; else echo "Already configured"; fi)
EOF

echo -e "${GREEN}Installation log saved to /var/log/slurm-k8s/installation.log${NC}"
