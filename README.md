# Slurm-Kubernetes 통합 시스템

Slurm의 강력한 스케줄링 정책과 Kubernetes의 컨테이너 오케스트레이션을 결합한 GPU 클러스터 관리 시스템입니다.

## 📋 목차
- [개요](#개요)
- [아키텍처](#아키텍처)
- [빠른 시작](#빠른-시작)
- [파일 구조](#파일-구조)
- [담당자별 가이드](#담당자별-가이드)
- [문서](#문서)

---

## 개요

### 핵심 기능
- ✅ **Slurm 스케줄링**: Backfill + Multifactor 우선순위 정책
- ✅ **K8s 실행**: 실제 워크로드는 Kubernetes Pod로 실행
- ✅ **NAS 통합**: 데이터 공유 및 결과 저장
- ✅ **자동화**: Job 파일 감지 → 검증 → 제출 → 실행 → 결과 수집

### 왜 이 아키텍처인가?
1. **Slurm**: 학술/연구 환경에 최적화된 스케줄링 (공정성, 우선순위, 백필)
2. **Kubernetes**: 컨테이너 기반 격리, 확장성, 자원 관리
3. **하이브리드**: 두 시스템의 장점을 모두 활용

---

## 아키텍처

```
┌─────────────────┐
│  NAS 공유폴더   │
│  Job 파일 업로드 │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Job Validator  │◄─── inotify 감시
│  파일 검증      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Slurm Queue    │
│  - Backfill     │
│  - Multifactor  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Prolog Script   │
│ K8s YAML 생성   │
│ kubectl apply   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  K8s Pod 실행   │
│  - GPU 할당     │
│  - NAS 마운트   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Epilog Script   │
│ 결과 수집       │
│ 리소스 정리     │
└─────────────────┘
```

---

## 빠른 시작

### 1. 사전 요구사항
- ✅ Slurm 설치 완료
- ✅ Kubernetes 클러스터 구성 완료
- ✅ NAS 마운트 (`/mnt/test-k8s`)
- ✅ 로컬 레지스트리 (`nas-hub.local:5407`)

### 2. GitHub에서 Clone (추천)

```bash
# 서버에서
git clone https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
cd slurm-k8s-integration/

# 자동 설치
sudo bash install.sh

# Slurm 설정 업데이트
sudo nano /etc/slurm/slurm.conf
# (slurm.conf.example 참고)

# 서비스 시작
sudo systemctl restart slurmctld
sudo systemctl start slurm-job-watcher

# 테스트
sbatch example-job.sh
```

**GitHub 설정 방법**: [GITHUB_QUICK_GUIDE.md](GITHUB_QUICK_GUIDE.md) 참고

### 3. 수동 설치 (30분)
상세한 설치 가이드는 **[QUICK_START.md](QUICK_START.md)** 참고

### 3. 첫 Job 실행
```bash
cat > hello.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=hello
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --output=/mnt/test-k8s/results/%j.out
#K8S_IMAGE=nas-hub.local:5407/alpine:latest

echo "Hello from Slurm-K8s!"
EOF

# 제출 방법 1: NAS 폴더에 복사
cp hello.sh /mnt/test-k8s/slurm-jobs/submit/

# 제출 방법 2: 직접 제출
sbatch hello.sh
```

---

## 파일 구조

### 핵심 스크립트
| 파일 | 설명 |
|------|------|
| `slurm_k8s_prolog.sh` | Job 실행 전 K8s Pod 생성 |
| `slurm_k8s_epilog.sh` | Job 완료 후 결과 수집 및 정리 |
| `job_validator.sh` | Job 파일 검증 |
| `job_watcher.sh` | NAS 폴더 감시 및 자동 제출 |
| `test_suite.sh` | 통합 테스트 스크립트 |

### 설정 파일
| 파일 | 설명 |
|------|------|
| `install.sh` |  자동 설치 스크립트 (추천) |
| `slurm.conf.example` | Slurm 설정 예시 |
| `pod-template.yaml` | K8s Pod YAML 템플릿 |
| `example-job.sh` | 샘플 Job 파일 |

### 문서
| 파일 | 내용 |
|------|------|
| **README.md** | 이 파일 - 프로젝트 개요 |
| **GITHUB_QUICK_GUIDE.md** |  GitHub로 5분 만에 시작하기 |
| **QUICK_START.md** | 30분 만에 설치하기 |
| **IMPLEMENTATION_GUIDE.md** | 상세 구현 가이드 |
| **GITHUB_SETUP.md** | GitHub 상세 설정 가이드 |
---

#### 테스트 방법
```bash
# 스케줄링 정책 확인
scontrol show config | grep -i schedule
scontrol show config | grep -i priority

# 이미지 관리
nerdctl-safe build -t test:latest .
nerdctl-safe tag test:latest nas-hub.local:5407/test:latest
nerdctl-safe push nas-hub.local:5407/test:latest

# 리소스 상태 확인
kubectl get nodes -o json | jq '.items[].status.allocatable'
```
---

**테스트 방법**:
```bash
# 전체 통합 테스트
./test_suite.sh
./test_suite.sh --verbose --component epilog

# 특정 항목 테스트
./test_suite.sh --test infrastructure
./test_suite.sh --test epilog
```

## 주요 기능 상세

### 1. Job 제출 프로세스
```
사용자 Job 파일 작성
    ↓
NAS 공유폴더에 업로드 (/mnt/test-k8s/slurm-jobs/submit/)
    ↓
Job Watcher가 inotify로 감지
    ↓
job_validator.sh로 검증
    ↓ (통과)
sbatch로 Slurm 큐에 제출
    ↓ (실패)
/mnt/test-k8s/slurm-jobs/failed/로 이동 + 에러 로그
```

### 2. 스케줄링 정책
- **Backfill**: 대기 중인 작은 Job을 우선 실행하여 자원 활용도 극대화
- **Multifactor 우선순위**:
  - `PriorityWeightAge`: 대기 시간이 길수록 우선순위 증가
  - `PriorityWeightFairshare`: 자원을 덜 사용한 사용자 우대
  - `PriorityWeightJobSize`: Job 크기 고려

### 3. K8s 통합
```
Slurm Prolog 실행
    ↓
Job 정보 파싱 (CPU, Memory, GPU)
    ↓
K8s 리소스 가용성 확인
    ↓
mkyaml/mkinst로 YAML 생성
    ↓
kubectl apply로 Pod/PVC/PV 생성
    ↓
Pod Ready 대기
    ↓
Slurm에 상태 저장
```

---

## 트러블슈팅

### 자주 발생하는 문제

#### 1. Job이 큐에서 대기만 함
```bash
# 원인 확인
scontrol show job JOB_ID | grep Reason

# 가능한 원인:
# - Resources: 리소스 부족
# - Priority: 우선순위가 낮음
# - Dependency: 의존성 미충족
```

#### 2. Pod가 생성되지 않음
```bash
# Prolog 로그 확인
tail -f /var/log/slurm-k8s/prolog_*.log

# K8s 이벤트 확인
kubectl get events --sort-by='.lastTimestamp' | tail -20

# 일반적인 원인:
# - 이미지 없음
# - 노드 리소스 부족
# - StorageClass 설정 오류
```

#### 3. 결과 파일이 없음
```bash
# Epilog 로그 확인
tail -f /var/log/slurm-k8s/epilog_*.log

# NAS 마운트 확인
mountpoint /mnt/test-k8s

# 권한 확인
ls -ld /mnt/test-k8s/results/
```
