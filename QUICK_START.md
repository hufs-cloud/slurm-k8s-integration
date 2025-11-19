# Slurm-K8s 통합 시스템 빠른 시작 가이드

## 30분 만에 시작하기

### 1단계: 스크립트 설치 (5분)

```bash
# 작업 디렉토리 생성
mkdir -p ~/slurm-k8s-integration
cd ~/slurm-k8s-integration

# 모든 스크립트를 /usr/local/bin으로 복사
sudo cp slurm_k8s_prolog.sh /usr/local/bin/
sudo cp slurm_k8s_epilog.sh /usr/local/bin/
sudo cp job_validator.sh /usr/local/bin/
sudo cp job_watcher.sh /usr/local/bin/

# 실행 권한 부여
sudo chmod +x /usr/local/bin/slurm_k8s_*.sh
sudo chmod +x /usr/local/bin/job_*.sh

# 로그 디렉토리 생성
sudo mkdir -p /var/log/slurm-k8s
sudo chown slurm:slurm /var/log/slurm-k8s
```

### 2단계: Slurm 설정 수정 (10분)

```bash
# 기존 설정 백업
sudo cp /etc/slurm/slurm.conf /etc/slurm/slurm.conf.backup

# 설정 파일 편집
sudo nano /etc/slurm/slurm.conf
```

**추가할 내용:**
```conf
# 스케줄러 설정
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
SchedulerParameters=bf_max_job_test=100,bf_interval=30

# 우선순위 설정
PriorityType=priority/multifactor
PriorityWeightAge=1000
PriorityWeightFairshare=10000
PriorityWeightJobSize=1000

# Prolog/Epilog
Prolog=/usr/local/bin/slurm_k8s_prolog.sh
Epilog=/usr/local/bin/slurm_k8s_epilog.sh
PrologEpilogTimeout=600
```

**설정 적용:**
```bash
sudo systemctl restart slurmctld
sudo systemctl status slurmctld
```

### 3단계: NAS 디렉토리 준비 (2분)

```bash
# Job 제출/결과 디렉토리 생성
mkdir -p /mnt/test-k8s/slurm-jobs/{submit,processed,failed}
mkdir -p /mnt/test-k8s/results
mkdir -p /mnt/test-k8s/scripts

# 권한 설정
chmod 755 /mnt/test-k8s/slurm-jobs/*
chmod 755 /mnt/test-k8s/results
```

### 4단계: Job Watcher 서비스 시작 (3분)

```bash
# systemd 서비스 파일 생성
sudo tee /etc/systemd/system/slurm-job-watcher.service <<EOF
[Unit]
Description=Slurm Job Watcher
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/job_watcher.sh
Restart=always
User=slurm

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
sudo systemctl daemon-reload
sudo systemctl enable slurm-job-watcher
sudo systemctl start slurm-job-watcher
sudo systemctl status slurm-job-watcher
```

### 5단계: 테스트 이미지 준비 (5분)

```bash
# 간단한 Alpine 이미지 태깅 (이미 있다면 스킵)
nerdctl-safe pull alpine:latest
nerdctl-safe tag alpine:latest nas-hub.local:5407/alpine:latest
nerdctl-safe push nas-hub.local:5407/alpine:latest

# 확인
nerdctl-safe images | grep nas-hub.local:5407
```

### 6단계: 첫 Job 실행 (5분)

```bash
# 테스트 Job 파일 생성
cat > /mnt/test-k8s/slurm-jobs/submit/hello-world.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=hello-world
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:02:00
#SBATCH --output=/mnt/test-k8s/results/hello-%j.out
#SBATCH --error=/mnt/test-k8s/results/hello-%j.err
#K8S_IMAGE=nas-hub.local:5407/alpine:latest

echo "=========================================="
echo "Hello from Slurm-K8s Integration!"
echo "Job ID: $SLURM_JOB_ID"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "=========================================="

# 간단한 계산
for i in {1..10}; do
  echo "Iteration $i: $(date +%s)"
  sleep 1
done

echo "Job completed successfully!"
EOF
```

**Job 제출 확인:**
```bash
# Job Watcher가 자동으로 제출 (또는 직접 제출)
# sbatch /mnt/test-k8s/slurm-jobs/submit/hello-world.sh

# Job 상태 확인
watch -n 2 'squeue; echo "---"; kubectl get pods -l app=slurm-job'
```

---

## 검증 체크리스트

실행 후 다음을 확인하세요:

### ✅ 시스템 상태
```bash
# Slurm 서비스 실행 중
systemctl is-active slurmctld

# Job Watcher 실행 중
systemctl is-active slurm-job-watcher

# K8s 클러스터 접근 가능
kubectl cluster-info

# NAS 마운트 확인
mountpoint /mnt/test-k8s
```

### ✅ Job 워크플로우
```bash
# 1. Job이 큐에 들어갔는지 확인
squeue

# 2. K8s Pod가 생성되었는지 확인
kubectl get pods -l app=slurm-job

# 3. Job 완료 후 결과 확인
ls -lh /mnt/test-k8s/results/

# 4. 로그 확인
tail -f /var/log/slurm-k8s/prolog_*.log
tail -f /var/log/slurm-k8s/epilog_*.log
```

---

## 다음 단계

### 고급 기능 활용

**GPU Job 실행:**
```bash
cat > gpu_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=gpu-test
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=/mnt/test-k8s/results/gpu-%j.out
#K8S_IMAGE=nas-hub.local:5407/pytorch:2.0-cuda11.8

nvidia-smi
python /mnt/test-k8s/scripts/train.py
EOF

sbatch gpu_job.sh
```

**Python 스크립트 실행:**
```bash
# /mnt/test-k8s/scripts/example.py 생성
cat > /mnt/test-k8s/scripts/example.py <<'EOF'
import time
import os

print(f"Job ID: {os.environ.get('SLURM_JOB_ID')}")
print(f"Starting computation...")

for i in range(10):
    print(f"Step {i+1}/10")
    time.sleep(1)

print("Computation complete!")
EOF

# Job 파일 생성
cat > python_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=python-test
#SBATCH --cpus-per-task=2
#SBATCH --mem=2G
#SBATCH --output=/mnt/test-k8s/results/python-%j.out
#K8S_IMAGE=nas-hub.local:5407/python:3.11

python3 /mnt/test-k8s/scripts/example.py
EOF

sbatch python_job.sh
```

---

## 문제 발생 시

### 일반적인 문제 해결

**1. Job이 제출되지 않음**
```bash
# Job Watcher 로그 확인
sudo journalctl -u slurm-job-watcher -f

# 수동으로 검증 스크립트 실행
/usr/local/bin/job_validator.sh /path/to/job.sh
```

**2. Pod가 생성되지 않음**
```bash
# Prolog 로그 확인
tail -100 /var/log/slurm-k8s/prolog_*.log

# K8s 리소스 확인
kubectl get nodes
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

**3. 결과 파일이 없음**
```bash
# Epilog 로그 확인
tail -100 /var/log/slurm-k8s/epilog_*.log

# NAS 경로 확인
ls -lh /mnt/test-k8s/results/
```

---

## 도움말

**모든 스크립트 위치:**
- Prolog: `/usr/local/bin/slurm_k8s_prolog.sh`
- Epilog: `/usr/local/bin/slurm_k8s_epilog.sh`
- Validator: `/usr/local/bin/job_validator.sh`
- Watcher: `/usr/local/bin/job_watcher.sh`

**모든 로그 위치:**
- Slurm: `/var/log/slurm/slurmctld.log`
- 통합 시스템: `/var/log/slurm-k8s/*.log`
- Job Watcher: `journalctl -u slurm-job-watcher`

**유용한 명령어:**
```bash
# 전체 시스템 상태 한눈에 보기
echo "=== Slurm ===" && sinfo && \
echo "=== Jobs ===" && squeue && \
echo "=== K8s Pods ===" && kubectl get pods -l app=slurm-job && \
echo "=== Recent Results ===" && ls -lht /mnt/test-k8s/results/ | head -5
```

---

**설치 완료! 🎉**

이제 Slurm-K8s 통합 시스템이 준비되었습니다.
`/mnt/test-k8s/slurm-jobs/submit/`에 Job 파일을 복사하면 자동으로 처리됩니다!
