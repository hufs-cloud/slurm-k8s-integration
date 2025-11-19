#!/bin/bash
set -e

LOG_DIR="/var/log/slurm-k8s"
LOG_FILE="$LOG_DIR/epilog_${SLURM_JOB_ID}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(date)] Epilog started for Job ${SLURM_JOB_ID}"

# 1. Prolog에서 저장한 Pod 이름 읽기
POD_INFO_FILE="/tmp/slurm_job_${SLURM_JOB_ID}_pod"
if [[ ! -f "$POD_INFO_FILE" ]]; then
    echo "Warning: Pod info file not found. Skipping cleanup."
    exit 0
fi

POD_NAME=$(cat "$POD_INFO_FILE")

# 2. Pod 상태 확인
POD_STATUS=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "[$(date)] Pod status: $POD_STATUS"

# 3. 로그 수집
RESULT_DIR="/mnt/test-k8s/results/${SLURM_JOB_ID}"
mkdir -p "$RESULT_DIR"

echo "[$(date)] Collecting logs..."
kubectl logs "$POD_NAME" > "$RESULT_DIR/stdout.log" 2>&1 || true
kubectl logs "$POD_NAME" --previous > "$RESULT_DIR/stdout_previous.log" 2>/dev/null || true

# 4. 실행 결과 파일 수집 (Pod의 PVC에서)
# PVC가 NAS 기반이므로 이미 NAS에 저장되어 있음
# 필요시 특정 경로 파일들을 결과 디렉토리로 복사

# 5. Pod 메타데이터 저장
kubectl get pod "$POD_NAME" -o yaml > "$RESULT_DIR/pod_manifest.yaml" 2>/dev/null || true

# 6. 실행 시간 및 리소스 사용량 기록
COMPLETION_TIME=$(date)
START_TIME=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.startTime}' 2>/dev/null || echo "Unknown")

cat > "$RESULT_DIR/job_summary.txt" <<EOF
Job ID: ${SLURM_JOB_ID}
User: ${SLURM_JOB_USER}
Pod Name: ${POD_NAME}
Start Time: ${START_TIME}
Completion Time: ${COMPLETION_TIME}
Final Status: ${POD_STATUS}
Exit Code: ${SLURM_JOB_EXIT_CODE:-0}
EOF

# 7. 무결성 검증
echo "[$(date)] Verifying result integrity..."
if [[ -f "$RESULT_DIR/stdout.log" ]]; then
    CHECKSUM=$(sha256sum "$RESULT_DIR/stdout.log" | cut -d' ' -f1)
    echo "stdout.log checksum: $CHECKSUM" >> "$RESULT_DIR/checksums.txt"
fi

# 8. 리소스 정리 (역순으로)
echo "[$(date)] Cleaning up K8s resources..."

# Pod 삭제
kubectl delete pod "$POD_NAME" --grace-period=30 2>/dev/null || true

# PVC 삭제 (사용자별로 재사용하는 경우 주석 처리)
# PVC_NAME="pvc-${SLURM_JOB_USER}-${SLURM_JOB_ID}"
# kubectl delete pvc "$PVC_NAME" --grace-period=30 2>/dev/null || true

# PV는 일반적으로 자동 삭제되므로 명시적 삭제 불필요

# 9. 임시 파일 정리
rm -f "$POD_INFO_FILE"

echo "[$(date)] Epilog completed successfully"

# 10. Slurm에 결과 상태 반영 (선택사항)
if [[ "$POD_STATUS" == "Failed" ]]; then
    echo "Pod failed, marking Slurm job as failed"
    exit 1
fi
