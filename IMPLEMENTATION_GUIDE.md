# Slurm-Kubernetes 통합 시스템 구현 가이드

## 1. 개요

### 1.1 아키텍처 설계
```
[NAS 공유폴더] → [Job 검증] → [Slurm Queue] → [스케줄링] → [K8s Pod 생성] → [실행] → [결과 수집]
     ↓              ↓              ↓               ↓              ↓            ↓          ↓
  Job 제출      Validator      slurmctld      Backfill+    Prolog Script   Pod 실행    Epilog
                              우선순위 큐     Multifactor    (kubectl)                  (정리)
```

### 1.2 핵심 컴포넌트
1. **Slurm**: Job 스케줄링 정책 엔진 (Backfill + Multifactor)
2. **Kubernetes**: 실제 워크로드 실행 플랫폼
3. **NAS**: 데이터 공유 및 결과 저장소
4. **로컬 레지스트리**: 컨테이너 이미지 저장 (nas-hub.local:5407)

### 1.3 주요 특징
- Slurm의 강력한 스케줄링 정책 활용
- K8s의 컨테이너 오케스트레이션 활용
- NAS 기반 데이터 공유로 워커 노드 독립성 확보

---

## 2. 시스템 요구사항

### 2.1 사전 설치 완료 항목
- ✅ K8s 클러스터 (containerd)
- ✅ Slurm, slurmctld
- ✅ NAS 마운트 및 로컬 레지스트리 (nas-hub.local:5407)

### 2.2 추가 설치 필요 항목
```bash
# inotify-tools (Job 감시용)
sudo apt-get install inotify-tools

# jq (JSON 파싱용)
sudo apt-get install jq

# munge (Slurm 인증)
sudo apt-get install munge libmunge-dev

# slurm-wlm (이미 설치되어 있으나 확인)
dpkg -l | grep slurm
```

---

## 3. 구현 단계별 가이드

### 3.1 Slurm 설정 (김금동)

#### 3.1.1 slurm.conf 수정
```bash
sudo cp /etc/slurm/slurm.conf /etc/slurm/slurm.conf.backup
sudo nano /etc/slurm/slurm.conf
```

핵심 설정 내용:
```conf
# 스케줄러 설정
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

# Backfill 파라미터
SchedulerParameters=bf_max_job_test=100,bf_interval=30

# Multifactor 우선순위
PriorityType=priority/multifactor
PriorityWeightAge=1000
PriorityWeightFairshare=10000
PriorityWeightJobSize=1000

# Prolog/Epilog 스크립트
Prolog=/usr/local/bin/slurm_k8s_prolog.sh
Epilog=/usr/local/bin/slurm_k8s_epilog.sh
PrologEpilogTimeout=600
```

#### 3.1.2 스크립트 설치
```bash
# Prolog/Epilog 스크립트 복사
sudo cp slurm_k8s_prolog.sh /usr/local/bin/
sudo cp slurm_k8s_epilog.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/slurm_k8s_*.sh

# 로그 디렉토리 생성
sudo mkdir -p /var/log/slurm-k8s
sudo chown slurm:slurm /var/log/slurm-k8s
```

#### 3.1.3 Slurm 재시작
```bash
sudo systemctl restart slurmctld
sudo systemctl status slurmctld
```

### 3.2 Job 검증 시스템 (최윤서)

#### 3.2.1 Job 파일 형식 정의
```bash
#!/bin/bash
#SBATCH --job-name=작업이름
#SBATCH --partition=gpu|cpu
#SBATCH --cpus-per-task=N
#SBATCH --mem=XG
#SBATCH --gres=gpu:N  # GPU 필요시
#SBATCH --time=HH:MM:SS
#SBATCH --output=/mnt/nas/results/%j.out
#SBATCH --error=/mnt/nas/results/%j.err

# K8s 메타데이터 (선택)
#K8S_IMAGE=nas-hub.local:5407/이미지:태그
#K8S_WORKDIR=/workspace
#K8S_SCRIPT=/mnt/nas/scripts/작업.py

# 실제 실행 명령어
python /mnt/nas/scripts/train.py
```

#### 3.2.2 검증 스크립트 설치
```bash
sudo cp job_validator.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/job_validator.sh
```

#### 3.2.3 NAS 감시 데몬 설정
```bash
# 감시 디렉토리 생성
mkdir -p /mnt/nas/slurm-jobs/{submit,processed,failed}

# 감시 스크립트 설치
sudo cp job_watcher.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/job_watcher.sh

# systemd 서비스 생성
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
```

### 3.3 컨테이너 이미지 준비 (김금동)

#### 3.3.1 테스트 이미지 빌드
```bash
# Dockerfile 예시
cat > Dockerfile.pytorch <<EOF
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install torch torchvision torchaudio

WORKDIR /workspace
EOF

# 이미지 빌드 (nerdctl-safe 사용)
nerdctl-safe build -t pytorch:2.0-cuda11.8 -f Dockerfile.pytorch .

# 로컬 레지스트리에 푸시
nerdctl-safe tag pytorch:2.0-cuda11.8 nas-hub.local:5407/pytorch:2.0-cuda11.8
nerdctl-safe push nas-hub.local:5407/pytorch:2.0-cuda11.8
```

#### 3.3.2 이미지 확인
```bash
nerdctl-safe images | grep nas-hub.local:5407
```

### 3.4 K8s 리소스 생성 (최윤서)

#### 3.4.1 mkyaml/mkinst 통합
Prolog 스크립트에서 자동으로 호출되도록 이미 구현되어 있습니다.

필요한 경우 수동 테스트:
```bash
# 예시: GPU 1개, 학번 2019123456로 인스턴스 생성
/path/to/mkinst gpu1 std 2019123456 \
  --job-id 12345 \
  --image nas-hub.local:5407/pytorch:latest \
  --cpu 4 \
  --memory 8G
```

#### 3.4.2 NFS StorageClass 설정 (필요시)
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
provisioner: nfs-client  # 또는 사용 중인 프로비저너
parameters:
  archiveOnDelete: "false"
```

### 3.5 결과 수집 시스템 (박세현)

#### 3.5.1 결과 디렉토리 구조
```
/mnt/nas/results/
├── {JOB_ID}/
│   ├── stdout.log          # 표준 출력
│   ├── stderr.log          # 표준 에러  
│   ├── job_summary.txt     # Job 요약
│   ├── checksums.txt       # 무결성 검증
│   └── outputs/            # 생성된 파일들
```

#### 3.5.2 Epilog 스크립트 커스터마이징
필요에 따라 `/usr/local/bin/slurm_k8s_epilog.sh` 수정:
- 추가 메트릭 수집
- 알림 전송
- 데이터 아카이빙

---

## 4. 운영 가이드

### 4.1 Job 제출 방법

#### 방법 1: NAS 폴더에 파일 업로드
```bash
# Job 파일을 감시 디렉토리에 복사
cp my_job.sh /mnt/nas/slurm-jobs/submit/
```

#### 방법 2: 직접 sbatch 명령
```bash
sbatch my_job.sh
```

### 4.2 Job 상태 확인
```bash
# 전체 Job 목록
squeue

# 특정 사용자 Job
squeue -u $USER

# 상세 정보
scontrol show job JOB_ID

# K8s Pod 상태
kubectl get pods -l app=slurm-job
```

### 4.3 리소스 사용률 모니터링
```bash
# K8s 노드 리소스 상태
kubectl top nodes

# 특정 Pod 리소스 사용량
kubectl top pod slurm-job-12345

# Slurm 자원 상태
sinfo
```

### 4.4 Job 취소
```bash
# Slurm에서 취소
scancel JOB_ID

# K8s Pod도 자동으로 정리됨 (Epilog에서 처리)
```

---

## 5. 트러블슈팅

### 5.1 자주 발생하는 문제

#### Pod가 생성되지 않음
```bash
# Prolog 로그 확인
tail -f /var/log/slurm-k8s/prolog_*.log

# K8s 이벤트 확인
kubectl get events --sort-by='.lastTimestamp'

# 이미지 존재 확인
nerdctl-safe images | grep IMAGE_NAME
```

#### Job이 큐에서 대기만 함
```bash
# 스케줄링 정보 확인
scontrol show job JOB_ID | grep Reason

# 우선순위 확인
sprio -j JOB_ID

# 리소스 가용성 확인
kubectl get nodes -o json | jq '.items[].status.allocatable'
```

#### 결과 파일이 생성되지 않음
```bash
# Epilog 로그 확인
tail -f /var/log/slurm-k8s/epilog_*.log

# Pod 로그 확인
kubectl logs slurm-job-JOB_ID

# NAS 마운트 확인
mountpoint /mnt/nas
```

### 5.2 로그 위치
- Slurm 로그: `/var/log/slurm/slurmctld.log`
- Prolog/Epilog 로그: `/var/log/slurm-k8s/`
- Job Watcher 로그: `/var/log/slurm-k8s/job_watcher.log`
- K8s Pod 로그: `kubectl logs POD_NAME`

---

## 6. 테스트

### 6.1 통합 테스트 실행
```bash
# 전체 테스트 스위트 실행
bash test_suite.sh
```

### 6.2 수동 E2E 테스트
```bash
# 1. 테스트 Job 작성
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/mnt/nas/results/test-%j.out
#K8S_IMAGE=nas-hub.local:5407/alpine:latest

echo "Test started at $(date)"
sleep 30
echo "Test completed at $(date)"
EOF

# 2. Job 제출
JOB_ID=$(sbatch test_job.sh | grep -oP '\d+')
echo "Submitted job: $JOB_ID"

# 3. 상태 모니터링
watch -n 2 "squeue -j $JOB_ID; echo '---'; kubectl get pods -l job-id=$JOB_ID"

# 4. 결과 확인
cat /mnt/nas/results/test-${JOB_ID}.out
```

---

## 7. 성능 최적화

### 7.1 스케줄링 최적화
```conf
# /etc/slurm/slurm.conf
SchedulerParameters=bf_max_job_test=200,bf_interval=15,bf_window=2880
```

### 7.2 K8s 리소스 예약
```yaml
# Pod에 우선순위 클래스 추가
priorityClassName: high-priority
```

### 7.3 이미지 캐싱
```bash
# 자주 사용하는 이미지 미리 pull
for node in $(kubectl get nodes -o name); do
  kubectl debug $node -it --image=nas-hub.local:5407/pytorch:latest -- /bin/true
done
```

---

## 8. 보안 고려사항

### 8.1 네임스페이스 격리
```bash
# 사용자별 네임스페이스 생성
kubectl create namespace user-${USER_ID}

# Prolog에서 네임스페이스 사용
kubectl apply -f pod.yaml -n user-${USER_ID}
```

### 8.2 리소스 쿼터
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: user-quota
spec:
  hard:
    requests.cpu: "32"
    requests.memory: 128Gi
    nvidia.com/gpu: "4"
```

---

## 9. 참고 자료

- Slurm 문서: https://slurm.schedmd.com/
- Kubernetes 문서: https://kubernetes.io/docs/
- Prolog/Epilog 가이드: https://slurm.schedmd.com/prolog_epilog.html

---

## 10. 체크리스트

### 설치 완료 확인
- [ ] Slurm Prolog/Epilog 스크립트 설치
- [ ] Job Validator 설치
- [ ] Job Watcher 서비스 실행
- [ ] 로그 디렉토리 권한 설정
- [ ] NAS 디렉토리 구조 생성
- [ ] 테스트 이미지 빌드 및 레지스트리 푸시

### 기능 검증
- [ ] Job 제출 → 검증 → 큐 진입
- [ ] Slurm 스케줄링 → K8s Pod 생성
- [ ] Pod 실행 → 결과 수집
- [ ] 리소스 자동 정리
- [ ] 에러 핸들링

### 문서화
- [ ] 운영 매뉴얼 작성
- [ ] 트러블슈팅 가이드
- [ ] 아키텍처 다이어그램
- [ ] API 인터페이스 문서
