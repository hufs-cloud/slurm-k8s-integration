#!/bin/bash
# monitor_and_submit.sh

WATCH_DIR="/mnt/test-k8s/workspaces"
LOG_FILE="/mnt/test-k8s/logs/job_monitor.log"

# yq 경로 명시
export PATH=$HOME/bin:$PATH

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

validate_and_process() {
    local SUBMIT_FILE=$1
    local USER_DIR=$2

    log "🔍 검증 시작: $SUBMIT_FILE"

    # YAML 파싱 가능 여부 확인
    YQ_OUTPUT=$(yq '.' "$SUBMIT_FILE" 2>&1)
    YQ_EXIT=$?
    if [ $YQ_EXIT -ne 0 ]; then
        log "❌ YAML 파싱 실패: $YQ_OUTPUT"
        return 1
    fi

    # 이미 제출된 작업인지 확인
    local SUBMITTED=$(yq '.submitted // false' "$SUBMIT_FILE")
    if [ "$SUBMITTED" = "true" ]; then
        log "⚠️  이미 제출된 작업입니다. 건너뜁니다: $SUBMIT_FILE"
        return 0
    fi

    # 필수 필드 검증
    local TYPE=$(yq '.type' "$SUBMIT_FILE")
    local ID=$(yq '.id' "$SUBMIT_FILE")
    local SCRIPT=$(yq '.script' "$SUBMIT_FILE")
    local TIME=$(yq '.time' "$SUBMIT_FILE")

    if [ "$TYPE" = "null" ] || [ -z "$TYPE" ]; then
        log "❌ type 필드 누락"
        return 1
    fi

    if [ "$ID" = "null" ] || [ -z "$ID" ]; then
        log "❌ id 필드 누락"
        return 1
    fi

    if [ "$SCRIPT" = "null" ] || [ -z "$SCRIPT" ]; then
        log "❌ script 필드 누락"
        return 1
    fi

    if [ "$TIME" = "null" ] || [ -z "$TIME" ]; then
        log "❌ time 필드 누락"
        return 1
    fi

    # type 값 검증
    if [[ ! "$TYPE" =~ ^(std|grad|prof|cls)$ ]]; then
        log "❌ 잘못된 type 값: $TYPE"
        return 1
    fi

    # cls 타입일 때 index 검증
    if [ "$TYPE" = "cls" ]; then
        local INDEX=$(yq '.index' "$SUBMIT_FILE")
        if [ "$INDEX" = "null" ] || [ -z "$INDEX" ]; then
            log "❌ cls 타입은 index 필드 필수"
            return 1
        fi
    fi

    # 스크립트 파일 존재 확인
    local SCRIPT_PATH="$USER_DIR/$SCRIPT"
    if [ ! -f "$SCRIPT_PATH" ]; then
        log "❌ 스크립트 파일 없음: $SCRIPT_PATH"
        return 1
    fi

    # 리소스 값 추출 (기본값 설정)
    local GPU=$(yq '.resource.gpu // 0' "$SUBMIT_FILE")
    local CPU=$(yq '.resource.cpu // 2' "$SUBMIT_FILE")
    local MEM=$(yq '.resource.mem // "10Gi"' "$SUBMIT_FILE")

    # 메모리 형식 변환 (Kubernetes -> Slurm)
    # 16Gi -> 16G, 10Mi -> 10M
    local MEM_SLURM=${MEM/Gi/G}
    MEM_SLURM=${MEM_SLURM/Mi/M}

    log "✅ 검증 완료"

    # Job YAML 파일 생성
    local JOB_NAME="job-${TYPE}-${ID}"
    local JOB_FILE="$USER_DIR/${JOB_NAME}.yaml"
    local SUBMIT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")

    log "📝 Job 파일 생성: $JOB_FILE"

    cat > "$JOB_FILE" <<EOF
# ${JOB_NAME}.yaml

# ===== 사용자 정보 =====
user:
  type: "$TYPE"
  id: "$ID"
  index: $(yq '.index' "$SUBMIT_FILE")

# ===== 작업 식별 =====
job:
  name: "$JOB_NAME"
  submit_time: "$SUBMIT_TIME"

# ===== 실행 설정 =====
execution:
  script: "$SCRIPT"
  time: "$TIME"

# ===== 리소스 요구사항 =====
resource:
  gpu: $GPU
  cpu: $CPU
  mem: "$MEM"

# ===== 데이터 =====
data:
  files:
$(yq '.data[]' "$SUBMIT_FILE" 2>/dev/null | sed 's/^/    - "/' | sed 's/$/"/' || echo "    []")

# ===== 경로 정보 =====
paths:
  job_spec_path: "$USER_DIR/${JOB_NAME}.yaml"
  workspace: "$USER_DIR"
  script_path: "$SCRIPT_PATH"
  data_path: "$USER_DIR/data"
  result_path: "$USER_DIR/results"
  output_path: "/mnt/test-k8s/outputs/${TYPE}-${ID}"
  log_stdout: "/mnt/test-k8s/logs/${JOB_NAME}.out"
  log_stderr: "/mnt/test-k8s/logs/${JOB_NAME}.err"
EOF

    log "✅ Job 파일 생성 완료"

    # Slurm 제출 대신 check_k8s_capacity.sh 실행
    log "🚀 Kubernetes 용량 체크 및 Job 제출 중..."

    # 환경변수와 함께 스크립트 실행
    JOB_SPEC_PATH="$JOB_FILE" /mnt/test-k8s/check_k8s_capacity.sh
    local CHECK_EXIT=$?

    if [ $CHECK_EXIT -eq 0 ]; then
        log "✅ Kubernetes Job 제출 완료!"
    
        # job-submit.yaml에 submitted 플래그 추가
        yq -i '.submitted = true' "$SUBMIT_FILE"
    
        return 0
    else
       log "❌ Kubernetes Job 제출 실패! Exit code: $CHECK_EXIT"
        return 1
    fi
}

# 메인 모니터링 루프
log "=== Job Submit Monitor 시작 ==="
log "감시 디렉토리: $WATCH_DIR"

inotifywait -m -r -e create --format '%w%f' "$WATCH_DIR" | while read NEW_FILE
do
    if [[ "$NEW_FILE" == *"/job-submit.yaml" ]]; then
        log "📥 새 job-submit.yaml 감지: $NEW_FILE"

        USER_DIR=$(dirname "$NEW_FILE")

        # 파일 쓰기 완료 대기
        sleep 1

        # 검증 및 처리
        validate_and_process "$NEW_FILE" "$USER_DIR"
    fi
done