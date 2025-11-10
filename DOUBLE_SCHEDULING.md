# 이중 스케줄링 문제와 해결 방법

## 문제 정의

Slurm과 Kubernetes를 함께 사용할 때, 스케줄링이 2번 발생합니다:

```
사용자 Job 제출
    ↓
[1차] Slurm Scheduler
    - 언제 실행할지 결정
    - 우선순위, 공정성, Backfill
    ↓
Prolog → kubectl apply
    ↓
[2차] Kubernetes Scheduler  
    - 어느 노드에서 실행할지 결정
    - 실제 리소스 할당
    ↓
Pod 실행
```

### 발생 가능한 문제들

#### 1. 리소스 불일치
```
Slurm: "GPU 2개 가용, Job 실행!"
K8s:   "실제로는 GPU 1개만 남음, Pending..."
```

#### 2. 교착 상태 (Deadlock)
```
Slurm Job A: GPU 2개 요청 → Prolog 실행 → K8s Pending (리소스 부족)
Slurm Job B: GPU 1개 요청 → 대기 (Job A가 "실행중"이라고 생각)
실제 K8s: GPU 2개 모두 비어있음

→ Job A는 영원히 Pending, Job B는 영원히 대기
```

---

## 해결 방법 비교

### 방법 1: Dummy 노드 + Prolog 체크 (현재 구현)

**장점:**
- ✅ 구현 간단
- ✅ Slurm은 스케줄링 정책만 담당
- ✅ K8s는 실제 배치만 담당

**단점:**
- ❌ Slurm이 실제 클러스터 상태 모름
- ❌ 리소스 불일치 가능성

**적합한 경우:**
- 클러스터가 안정적 (리소스 변동 적음)
- Job 수가 많지 않음
- 스케줄링 정책이 중요

---

### 방법 2: Prolog에서 리소스 체크 + Requeue (개선된 구현)

**구현 예시:**
```bash
# slurm_k8s_prolog.sh
if [[ K8s 리소스 부족 ]]; then
    echo "K8s 리소스 부족, Job Requeue"
    exit 1  # Slurm이 자동으로 재큐잉
fi
```

**장점:**
- ✅ 리소스 부족 시 자동 재시도
- ✅ 교착 상태 방지
- ✅ Slurm 설정만으로 구현 가능

**단점:**
- ❌ Prolog 실행 오버헤드
- ❌ 재큐잉 반복 시 성능 저하
- ❌ 여전히 이중 스케줄링

**적합한 경우:**
- 현재 프로젝트처럼 **빠른 구현** 필요
- 중소규모 클러스터
- Slurm 스케줄링 정책 활용 필요

---

### 방법 3: Slurm이 K8s 상태를 실시간 동기화

**구현:**
1. K8s API를 주기적으로 polling
2. Slurm의 NodeFeatures 업데이트
3. Slurm이 정확한 리소스 상태로 스케줄링

**장점:**
- ✅ 정확한 리소스 상태 반영
- ✅ 이중 스케줄링이지만 충돌 최소화

**단점:**
- ❌ 복잡한 구현 (동기화 스크립트 필요)
- ❌ API 호출 오버헤드
- ❌ 동기화 지연 (eventual consistency)

**구현 예시:**
```bash
#!/bin/bash
# sync_k8s_state.sh (cron으로 매분 실행)

while true; do
    # K8s 상태 조회
    K8S_STATE=$(kubectl get nodes -o json | jq ...)
    
    # Slurm NodeFeatures 업데이트
    scontrol update NodeName=node1 Features="gpu_avail:${GPU_COUNT}"
    
    sleep 60
done
```

---

### 방법 4: K8s만 사용 + Slurm 스케줄링 정책 이식 ⭐

**개념:**
- K8s Custom Scheduler 또는 Scheduler Extender 개발
- Slurm의 Backfill, Multifactor 로직을 K8s에 구현

**장점:**
- ✅ 단일 스케줄러 (충돌 없음)
- ✅ K8s 생태계 활용
- ✅ 확장성 우수

**단점:**
- ❌ 개발 비용 매우 높음
- ❌ Slurm 로직 재구현 필요
- ❌ 유지보수 부담

**구현 예시:**
```go
// K8s Scheduler Plugin
type SlurmSchedulerPlugin struct {
    handle framework.Handle
}

func (p *SlurmSchedulerPlugin) Score(ctx context.Context, state *framework.CycleState, pod *v1.Pod, nodeName string) (int64, *framework.Status) {
    // Slurm Multifactor 로직
    age_factor := calculate_age_priority(pod)
    fairshare_factor := calculate_fairshare(pod.Labels["user"])
    
    score := age_factor*1000 + fairshare_factor*10000
    return score, nil
}
```

---

### 방법 5: Volcano Scheduler (K8s Batch Scheduler) 🚀

**Volcano**는 HPC/AI 워크로드를 위한 K8s 스케줄러예요:
- Slurm과 유사한 기능 제공
- Gang Scheduling, Fair-share, Backfill 지원

**구현:**
```yaml
# Volcano Job 예시
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: training-job
spec:
  schedulerName: volcano
  queue: default
  policies:
    - event: PodEvicted
      action: RestartJob
  tasks:
    - replicas: 1
      template:
        spec:
          containers:
          - name: trainer
            image: pytorch:latest
```

**장점:**
- ✅ HPC 특화 스케줄러
- ✅ Slurm과 유사한 기능
- ✅ K8s 네이티브
- ✅ 이중 스케줄링 없음

**단점:**
- ❌ Slurm 완전 대체 (기존 시스템 변경)
- ❌ 학습 곡선
- ❌ Slurm 특정 기능 없을 수 있음

---

## 권장 사항

### 현재 프로젝트에는 **방법 2** 추천 ⭐

**이유:**
1. ✅ 빠른 구현 (이미 90% 완성)
2. ✅ Slurm 스케줄링 정책 활용 가능
3. ✅ K8s 컨테이너 관리 활용
4. ✅ Prolog 체크 + Requeue로 충돌 방지
5. ✅ 중소규모 클러스터에 충분

**개선 사항 적용:**
```bash
# 1. Prolog에서 K8s 리소스 체크 (이미 추가됨)
# 2. Slurm 설정에 Requeue 정책 추가
Requeue=1

# 3. PrologFlags 설정
PrologFlags=Alloc,Serial
```

### 장기적으로는 **방법 5 (Volcano)** 고려

**전환 시점:**
- 클러스터 규모 증가 (100+ 노드)
- Job 수 급증 (1000+ jobs/day)
- 복잡한 스케줄링 요구사항 발생
- 이중 스케줄링으로 인한 실제 문제 발생

---

## 실전 팁

### 1. 모니터링 강화
```bash
# Slurm과 K8s 상태 동시 모니터링
watch -n 2 '
echo "=== Slurm Queue ==="
squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %R"
echo ""
echo "=== K8s Pods ==="
kubectl get pods -l app=slurm-job -o wide
echo ""
echo "=== K8s Resources ==="
kubectl top nodes
'
```

### 2. Timeout 설정
```conf
# slurm.conf
PrologEpilogTimeout=600  # Prolog가 10분 안에 완료 못하면 실패
```

### 3. Job 크기 제한
```conf
# 너무 큰 Job은 별도 파티션으로
PartitionName=large-gpu Nodes=... MaxCPUs=32 MaxGPUs=4
```

### 4. 우선순위 조정
```bash
# 긴급 Job은 높은 우선순위로
sbatch --priority=10000 urgent_job.sh
```

---

## 결론

**이중 스케줄링은 Trade-off입니다:**

| 장점 | 단점 |
|------|------|
| Slurm의 강력한 스케줄링 정책 활용 | 리소스 불일치 가능성 |
| K8s의 컨테이너 관리 활용 | 복잡도 증가 |
| 각 시스템의 장점만 활용 | 오버헤드 발생 |

**현재 구현 (방법 2)은 실용적이고 효과적입니다!**

나중에 문제가 생기면 Volcano 같은 단일 스케줄러로 전환을 고려하세요.
