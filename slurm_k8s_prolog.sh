#!/bin/bash
set -e

# Slurm 환경변수 로깅
LOG_DIR="/var/log/slurm-k8s"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/prolog_${SLURM_JOB_ID}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(date)] Prolog started for Job ${SLURM_JOB_ID}"

# 1. Job 파일에서 K8s 메타데이터 추출
JOB_SCRIPT="/var/spool/slurm/job${SLURM_JOB_ID}/slurm_script"

# K8S_IMAGE, K8S_WORKDIR 등 추출
K8S_IMAGE=$(grep -oP '#K8S_IMAGE=\K.*' "$JOB_SCRIPT" || echo "nas-hub.local:5407/default:latest")
K8S_WORKDIR=$(grep -oP '#K8S_WORKDIR=\K.*' "$JOB_SCRIPT" || echo "/workspace")

# 2. 리소스 요구사항 변환
CPU_REQUEST="${SLURM_CPUS_PER_TASK:-1}"
MEM_REQUEST="${SLURM_MEM_PER_NODE:-1024}Mi"

# GPU 요청 파싱
GPU_REQUEST=0
if [[ -n "$SLURM_JOB_GPUS" ]]; then
    GPU_REQUEST=$(echo "$SLURM_JOB_GPUS" | grep -oP '\d+' || echo "0")
fi

# 3. K8s 클러스터 리소스 확인
echo "[$(date)] Checking K8s resource availability..."

# 요청된 리소스
REQUESTED_CPU=$CPU_REQUEST
REQUESTED_MEM_MB=$(echo "$MEM_REQUEST" | sed 's/Mi$//' | sed 's/G$/*1024/' | bc 2>/dev/null || echo "1024")
REQUESTED_GPU=$GPU_REQUEST

# 사용 가능한 리소스 계산 (allocatable - requested)
AVAILABLE_CHECK=$(kubectl get nodes -o json | jq -r --arg cpu "$REQUESTED_CPU" --arg mem "$REQUESTED_MEM_MB" --arg gpu "$REQUESTED_GPU" '
  .items[] | 
  select(.spec.taints == null or (.spec.taints | length == 0)) |
  {
    name: .metadata.name,
    cpu_allocatable: (.status.allocatable.cpu | tonumber),
    cpu_requested: ([.status.allocatable.cpu | tonumber] | add),
    memory_allocatable_mb: (.status.allocatable.memory | sub("Ki$"; "") | tonumber / 1024),
    gpu_allocatable: ((.status.allocatable."nvidia.com/gpu" // "0") | tonumber),
    has_enough_resources: (
      (.status.allocatable.cpu | tonumber) >= ($cpu | tonumber) and
      ((.status.allocatable.memory | sub("Ki$"; "") | tonumber / 1024) >= ($mem | tonumber)) and
      (((.status.allocatable."nvidia.com/gpu" // "0") | tonumber) >= ($gpu | tonumber))
    )
  } | select(.has_enough_resources == true)
' | head -1)

if [[ -z "$AVAILABLE_CHECK" ]]; then
    echo "[$(date)] ERROR: No K8s node has enough resources!"
    echo "Requested: CPU=$REQUESTED_CPU, Memory=${REQUESTED_MEM_MB}MB, GPU=$REQUESTED_GPU"
    echo "Requeuing job to Slurm..."
    
    # Slurm Job을 다시 큐로 돌려보냄 (나중에 재시도)
    exit 1  # Prolog 실패 → Slurm이 Job을 Requeue
fi

echo "Available node found: $AVAILABLE_CHECK"

# 4. 학번/학수번호 추출 (PVC 이름 생성용)
USER_ID="${SLURM_JOB_USER}"

# 5. mkyaml 및 mkinst 호출
RESOURCE_TYPE="cpu"
if [[ $GPU_REQUEST -gt 0 ]]; then
    RESOURCE_TYPE="gpu"
fi

echo "[$(date)] Creating K8s resources using mkinst..."

# mkinst 호출 (실제 인터페이스에 맞게 수정 필요)
# mkinst cpuN|gpuN cls|std 학수번호|학번
/usr/local/bin/mkinst "${RESOURCE_TYPE}${GPU_REQUEST:-1}" std "$USER_ID" \
  --job-id "$SLURM_JOB_ID" \
  --image "$K8S_IMAGE" \
  --cpu "$CPU_REQUEST" \
  --memory "$MEM_REQUEST" \
  --workdir "$K8S_WORKDIR"

# 6. Pod YAML에 실제 실행 명령어 추가
POD_YAML="$HOME/yaml/${RESOURCE_TYPE}-node1/pod-${SLURM_JOB_ID}.yaml"

# Job 스크립트에서 실제 명령어 추출 (SBATCH 지시어 이후)
ACTUAL_COMMAND=$(sed -n '/^[^#]/,$p' "$JOB_SCRIPT")

# YAML 수정: command 섹션 추가
cat >> "$POD_YAML" <<EOF
    command: ["/bin/bash", "-c"]
    args:
      - |
        set -e
        cd $K8S_WORKDIR
        $ACTUAL_COMMAND
        echo "Job completed successfully"
EOF

# 7. Pod 생성 및 대기
echo "[$(date)] Applying Pod configuration..."
kubectl apply -f "$POD_YAML"

POD_NAME="slurm-job-${SLURM_JOB_ID}"

# Pod가 Running 상태가 될 때까지 대기
echo "[$(date)] Waiting for Pod to be ready..."
kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=300s

# 8. Slurm에 상태 저장 (Epilog에서 사용)
echo "$POD_NAME" > "/tmp/slurm_job_${SLURM_JOB_ID}_pod"

echo "[$(date)] Prolog completed successfully"
