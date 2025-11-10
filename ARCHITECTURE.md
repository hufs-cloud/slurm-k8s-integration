# 개선된 아키텍처: 이중 스케줄링 처리

## 전체 흐름도

```
┌─────────────────────────────────────────────────────────────┐
│                     사용자 Job 제출                          │
│                    sbatch job.sh                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Job Validator (job_validator.sh)                │
│  - Job 파일 형식 검증                                         │
│  - 리소스 요청 검증                                           │
│  - 이미지 존재 확인                                           │
└────────────────────────┬────────────────────────────────────┘
                         │ (검증 통과)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Slurm Queue (대기열)                        │
│                                                              │
│  Job A (Priority: 100, Age: 2h, GPU: 2)                     │
│  Job B (Priority: 80,  Age: 1h, GPU: 1)                     │
│  Job C (Priority: 50,  Age: 3h, GPU: 4)                     │
│                                                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│         [1차 스케줄링] Slurm Scheduler (slurmctld)            │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Backfill Scheduler                                  │   │
│  │  - 대기 중인 Job 중 지금 실행 가능한 것 탐색         │   │
│  │  - 작은 Job을 먼저 실행해서 자원 활용도 최대화       │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Multifactor Priority                                │   │
│  │  - Age Factor (대기 시간)                            │   │
│  │  - Fairshare (공정성)                                │   │
│  │  - Job Size (작업 크기)                              │   │
│  │  → 우선순위 계산                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│                    결정: Job A 실행!                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            Prolog Script (slurm_k8s_prolog.sh)               │
│                                                              │
│  Step 1: Job 정보 파싱                                       │
│    - CPU: 8, Memory: 16G, GPU: 2                            │
│    - Image: nas-hub.local:5407/pytorch:latest               │
│    - User: user123                                           │
│                                                              │
│  Step 2: K8s 리소스 가용성 체크 ⭐ (신규 추가)                │
│    ┌──────────────────────────────────────────┐            │
│    │ kubectl get nodes -o json                │            │
│    │   ↓                                       │            │
│    │ Available?                                │            │
│    │   YES → 계속 진행                          │            │
│    │   NO  → exit 1 (Requeue)                 │            │
│    └──────────────────────────────────────────┘            │
│                                                              │
│  Step 3: K8s YAML 생성                                       │
│    - mkyaml/mkinst 호출                                      │
│    - Pod, PVC, PV 정의                                       │
│                                                              │
│  Step 4: kubectl apply                                       │
│    - K8s에 리소스 생성 요청                                   │
│                                                              │
│  Step 5: Pod Ready 대기                                      │
│    - kubectl wait --for=condition=Ready                      │
│    - Timeout: 5분                                            │
│                                                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│       [2차 스케줄링] Kubernetes Scheduler (kube-scheduler)    │
│                                                              │
│  Step 1: Pod 받음                                            │
│    - Name: slurm-job-12345                                   │
│    - Resources: CPU 8, Memory 16G, GPU 2                     │
│                                                              │
│  Step 2: 노드 필터링 (Filtering)                             │
│    ┌──────────────────────────────────────────┐            │
│    │ node1: GPU 2개 (✓), Memory 32G (✓)      │            │
│    │ node2: GPU 0개 (✗) → 제외                │            │
│    │ node3: GPU 1개 (✗) → 제외                │            │
│    └──────────────────────────────────────────┘            │
│                                                              │
│  Step 3: 노드 스코어링 (Scoring)                             │
│    ┌──────────────────────────────────────────┐            │
│    │ node1:                                    │            │
│    │   - Resource availability: 80점           │            │
│    │   - Spread priority: 60점                 │            │
│    │   - Affinity: 50점                        │            │
│    │   Total: 190점                            │            │
│    └──────────────────────────────────────────┘            │
│                                                              │
│  Step 4: 최적 노드 선택                                       │
│    → node1 선택!                                             │
│                                                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubelet (node1에서 실행)                         │
│                                                              │
│  Step 1: 이미지 Pull                                         │
│    - containerd pull nas-hub.local:5407/pytorch:latest       │
│                                                              │
│  Step 2: 컨테이너 생성                                        │
│    - GPU 할당 (nvidia-docker)                                │
│    - 볼륨 마운트 (NAS)                                        │
│    - 네트워크 설정                                            │
│                                                              │
│  Step 3: 컨테이너 실행                                        │
│    - python /mnt/scripts/train.py                            │
│                                                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                     [실행 중...]
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Pod 실행 완료 (Completed)                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│           Epilog Script (slurm_k8s_epilog.sh)                │
│                                                              │
│  Step 1: Pod 로그 수집                                        │
│    - kubectl logs slurm-job-12345 > stdout.log              │
│                                                              │
│  Step 2: 결과 파일 정리                                       │
│    - NAS에서 결과 디렉토리로 이동                             │
│    - 무결성 검증 (checksum)                                   │
│                                                              │
│  Step 3: K8s 리소스 정리 (역순)                               │
│    - kubectl delete pod slurm-job-12345                      │
│    - kubectl delete pvc pvc-user123-12345                    │
│    - (PV는 자동 삭제)                                         │
│                                                              │
│  Step 4: 결과 요약 저장                                       │
│    - Job ID, 실행 시간, 상태 등                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 리소스 부족 시 흐름 (Requeue)

```
Slurm: "Job A 실행!"
   ↓
Prolog: K8s 리소스 체크
   ↓
K8s: "GPU 2개 필요한데 1개만 있음"
   ↓
Prolog: exit 1 (실패)
   ↓
Slurm: Job A를 다시 Queue로 (Requeue)
   ↓
[대기...]
   ↓
다른 Job 완료로 GPU 확보됨
   ↓
Slurm: "Job A 다시 실행!"
   ↓
Prolog: K8s 리소스 체크 → OK!
   ↓
성공적으로 실행
```

---

## 핵심 포인트

### 1. 이중 스케줄링이지만 역할 분담
```
Slurm Scheduler:
  - 언제? (우선순위, 공정성)
  - 누구를? (어떤 Job을)

Kubernetes Scheduler:
  - 어디서? (어느 노드에)
  - 어떻게? (리소스 할당)
```

### 2. Prolog가 중재자 역할
```
Slurm: "이 Job 실행해!"
  ↓
Prolog: "잠깐, K8s에 자리 있나?"
  ↓ YES
K8s: "OK, 받았어"
  ↓ NO
Prolog: "Slurm, 다시 대기해"
```

### 3. 충돌 방지 메커니즘
- **체크**: Prolog에서 실제 가용 리소스 확인
- **재시도**: 리소스 부족 시 자동 Requeue
- **타임아웃**: 무한 대기 방지
- **모니터링**: 실시간 상태 추적

---

## 성능 최적화

### 1. Prolog 실행 시간 단축
```bash
# 병렬 처리
kubectl apply -f pod.yaml &
kubectl apply -f pvc.yaml &
wait
```

### 2. K8s 리소스 체크 캐싱
```bash
# 매번 kubectl 호출 대신
# 10초마다 상태를 캐시 파일에 저장
# Prolog는 캐시 파일 읽기
```

### 3. 우선순위 기반 스케줄링
```yaml
# K8s Pod에 Priority Class 추가
priorityClassName: high-priority
```

---

## 모니터링 대시보드

```bash
#!/bin/bash
# monitor_dashboard.sh

while true; do
    clear
    echo "=========================================="
    echo "Slurm-K8s Integration Dashboard"
    echo "=========================================="
    echo ""
    
    echo "=== Slurm Queue ==="
    squeue -o "%.8i %.9P %.30j %.8u %.2t %.10M %.4D %R"
    echo ""
    
    echo "=== K8s Pods ==="
    kubectl get pods -l app=slurm-job -o wide
    echo ""
    
    echo "=== K8s Node Resources ==="
    kubectl top nodes
    echo ""
    
    echo "=== Recent Prolog Errors ==="
    tail -5 /var/log/slurm-k8s/prolog_*.log 2>/dev/null | grep ERROR || echo "No errors"
    echo ""
    
    sleep 5
done
```

---

## 결론

**이중 스케줄링의 장점을 활용하면서 단점은 최소화했습니다:**

✅ **Slurm**: 강력한 스케줄링 정책 (Backfill, Multifactor)
✅ **K8s**: 효율적인 컨테이너 관리
✅ **Prolog**: 충돌 방지 (리소스 체크 + Requeue)
✅ **분리된 책임**: 각 시스템이 자기 역할에 집중

이 아키텍처는 **실용적이고 확장 가능**합니다! 🚀
