#!/bin/bash
# NAS 공유 폴더에 Job 파일이 추가되면 자동으로 검증 및 제출

set -e

WATCH_DIR="/mnt/nas/slurm-jobs/submit"
PROCESSED_DIR="/mnt/nas/slurm-jobs/processed"
FAILED_DIR="/mnt/nas/slurm-jobs/failed"

mkdir -p "$WATCH_DIR" "$PROCESSED_DIR" "$FAILED_DIR"

LOG_FILE="/var/log/slurm-k8s/job_watcher.log"

echo "[$(date)] Starting job watcher on $WATCH_DIR" | tee -a "$LOG_FILE"

# inotify 설치 확인
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait not installed. Run: sudo apt-get install inotify-tools"
    exit 1
fi

# 기존 대기중인 파일들 먼저 처리
for job_file in "$WATCH_DIR"/*.{sh,job,sbatch}; do
    if [[ -f "$job_file" ]]; then
        echo "[$(date)] Processing existing file: $job_file" | tee -a "$LOG_FILE"
        process_job "$job_file"
    fi
done

# Job 처리 함수
process_job() {
    local job_file="$1"
    local filename=$(basename "$job_file")
    
    echo "[$(date)] New job detected: $filename" | tee -a "$LOG_FILE"
    
    # 파일이 완전히 작성될 때까지 대기 (파일 크기 안정화)
    sleep 2
    
    # 검증 및 제출
    if /usr/local/bin/job_validator.sh "$job_file" >> "$LOG_FILE" 2>&1; then
        echo "[$(date)] Job $filename submitted successfully" | tee -a "$LOG_FILE"
        mv "$job_file" "$PROCESSED_DIR/"
        
        # 성공 알림 파일 생성
        echo "Job submitted at $(date)" > "$PROCESSED_DIR/${filename}.success"
    else
        echo "[$(date)] Job $filename validation failed" | tee -a "$LOG_FILE"
        mv "$job_file" "$FAILED_DIR/"
        
        # 실패 원인 기록
        tail -20 "$LOG_FILE" > "$FAILED_DIR/${filename}.error"
    fi
}

export -f process_job

# inotify로 새 파일 감시
inotifywait -m -e close_write -e moved_to "$WATCH_DIR" \
    --format '%w%f' \
    --include '\.(sh|job|sbatch)$' |
while read job_file; do
    process_job "$job_file"
done
