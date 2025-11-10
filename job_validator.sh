#!/bin/bash
# Job 파일 검증 및 Slurm 큐 제출 스크립트

set -e

JOB_FILE="$1"
LOG_FILE="/var/log/slurm-k8s/job_validator.log"

echo "[$(date)] Validating job file: $JOB_FILE" | tee -a "$LOG_FILE"

# 1. 기본 형식 검증
if [[ ! -f "$JOB_FILE" ]]; then
    echo "Error: Job file not found" | tee -a "$LOG_FILE"
    exit 1
fi

# 2. 필수 SBATCH 지시어 확인
REQUIRED_DIRECTIVES=(
    "--job-name"
    "--output"
)

for directive in "${REQUIRED_DIRECTIVES[@]}"; do
    if ! grep -q "^#SBATCH ${directive}" "$JOB_FILE"; then
        echo "Error: Missing required directive: ${directive}" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# 3. K8s 이미지 존재 확인
K8S_IMAGE=$(grep -oP '#K8S_IMAGE=\K.*' "$JOB_FILE" || echo "")
if [[ -n "$K8S_IMAGE" ]]; then
    echo "Validating K8s image: $K8S_IMAGE"
    
    # containerd로 이미지 존재 확인
    if ! nerdctl-safe images | grep -q "${K8S_IMAGE#nas-hub.local:5407/}"; then
        echo "Warning: Image $K8S_IMAGE not found in local registry"
        echo "Please ensure the image exists or will be pulled"
    fi
fi

# 4. 리소스 요청 검증
CPU_REQUEST=$(grep -oP '#SBATCH --cpus-per-task=\K\d+' "$JOB_FILE" || echo "1")
MEM_REQUEST=$(grep -oP '#SBATCH --mem=\K\d+G?' "$JOB_FILE" || echo "1G")
GPU_REQUEST=$(grep -oP '#SBATCH --gres=gpu:\K\d+' "$JOB_FILE" || echo "0")

echo "Resource requests: CPU=$CPU_REQUEST, Memory=$MEM_REQUEST, GPU=$GPU_REQUEST"

# K8s 클러스터의 전체 가용 리소스 확인
TOTAL_AVAILABLE=$(kubectl get nodes -o json | jq -r '
  .items | 
  map(select(.spec.taints == null or (.spec.taints | length == 0))) |
  {
    cpu: ([.[].status.allocatable.cpu | tonumber] | add),
    memory_gb: ([.[].status.allocatable.memory | sub("Ki$"; "") | tonumber] | add / 1024 / 1024),
    gpu: ([.[].status.allocatable."nvidia.com/gpu" // "0" | tonumber] | add)
  }
')

echo "Total K8s capacity: $TOTAL_AVAILABLE"

# 5. 타임아웃 검증
TIME_LIMIT=$(grep -oP '#SBATCH --time=\K.*' "$JOB_FILE" || echo "")
if [[ -z "$TIME_LIMIT" ]]; then
    echo "Warning: No time limit specified, using default (1 hour)"
fi

# 6. 출력 경로 검증
OUTPUT_PATH=$(grep -oP '#SBATCH --output=\K.*' "$JOB_FILE" || echo "")
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")

if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# 7. NAS 경로 접근 검증
if grep -q '/mnt/nas' "$JOB_FILE"; then
    if [[ ! -d "/mnt/nas" ]]; then
        echo "Error: NAS mount point /mnt/nas not found" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 8. 스크립트 구문 검증 (셸 스크립트인 경우)
if file "$JOB_FILE" | grep -q "shell script"; then
    bash -n "$JOB_FILE" 2>&1 | tee -a "$LOG_FILE"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Error: Syntax error in job script" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 9. 검증 통과 - Slurm 큐에 제출
echo "[$(date)] Validation passed, submitting to Slurm..." | tee -a "$LOG_FILE"

JOB_ID=$(sbatch "$JOB_FILE" | grep -oP '\d+')

echo "Job submitted successfully with ID: $JOB_ID" | tee -a "$LOG_FILE"

# 10. Job 메타데이터 저장
JOB_META_DIR="/var/spool/slurm-k8s/jobs"
mkdir -p "$JOB_META_DIR"

cat > "$JOB_META_DIR/${JOB_ID}.json" <<EOF
{
  "job_id": "$JOB_ID",
  "submit_time": "$(date -Iseconds)",
  "job_file": "$JOB_FILE",
  "k8s_image": "$K8S_IMAGE",
  "resources": {
    "cpu": $CPU_REQUEST,
    "memory": "$MEM_REQUEST",
    "gpu": $GPU_REQUEST
  }
}
EOF

echo "[$(date)] Job metadata saved to $JOB_META_DIR/${JOB_ID}.json" | tee -a "$LOG_FILE"
