#!/bin/bash
# Slurm-K8s 통합 시스템 테스트 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=0

# 테스트 결과 출력 함수
test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC} $test_name: $message"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=========================================="
echo "Slurm-K8s Integration Test Suite"
echo "=========================================="

# 1. 기본 인프라 검증
echo -e "\n${YELLOW}[1] Infrastructure Validation${NC}"

# 1.1 NAS 마운트 확인
if mountpoint -q /mnt/nas; then
    test_result "NAS mount" "PASS"
else
    test_result "NAS mount" "FAIL" "/mnt/nas not mounted"
fi

# 1.2 로컬 레지스트리 접근 확인
if nerdctl-safe images | grep -q "nas-hub.local:5407"; then
    test_result "Local registry access" "PASS"
else
    test_result "Local registry access" "FAIL" "Cannot access nas-hub.local:5407"
fi

# 1.3 K8s 클러스터 연결 확인
if kubectl cluster-info &>/dev/null; then
    test_result "K8s cluster connection" "PASS"
else
    test_result "K8s cluster connection" "FAIL" "Cannot connect to K8s cluster"
fi

# 1.4 Slurm 서비스 상태 확인
if systemctl is-active --quiet slurmctld; then
    test_result "Slurm controller service" "PASS"
else
    test_result "Slurm controller service" "FAIL" "slurmctld not running"
fi

# 2. Job 파일 검증 테스트
echo -e "\n${YELLOW}[2] Job Validation Tests${NC}"

# 2.1 정상 Job 파일 검증
TEST_JOB="/tmp/test-valid-job.sh"
cat > "$TEST_JOB" <<'EOF'
#!/bin/bash
#SBATCH --job-name=test-job
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --output=/tmp/test-%j.out
#SBATCH --error=/tmp/test-%j.err
#K8S_IMAGE=nas-hub.local:5407/alpine:latest
echo "Test job"
EOF

if /usr/local/bin/job_validator.sh "$TEST_JOB" &>/dev/null; then
    test_result "Valid job file validation" "PASS"
else
    test_result "Valid job file validation" "FAIL" "Valid job rejected"
fi

# 2.2 필수 필드 누락 Job 검증
TEST_INVALID_JOB="/tmp/test-invalid-job.sh"
cat > "$TEST_INVALID_JOB" <<'EOF'
#!/bin/bash
#SBATCH --job-name=test-job
echo "Missing required fields"
EOF

if ! /usr/local/bin/job_validator.sh "$TEST_INVALID_JOB" &>/dev/null; then
    test_result "Invalid job file rejection" "PASS"
else
    test_result "Invalid job file rejection" "FAIL" "Invalid job accepted"
fi

# 3. 스케줄링 정책 테스트
echo -e "\n${YELLOW}[3] Scheduling Policy Tests${NC}"

# 3.1 Backfill 스케줄러 설정 확인
if scontrol show config | grep -q "SchedulerType.*backfill"; then
    test_result "Backfill scheduler enabled" "PASS"
else
    test_result "Backfill scheduler enabled" "FAIL" "Backfill not configured"
fi

# 3.2 Multifactor 우선순위 설정 확인
if scontrol show config | grep -q "PriorityType.*multifactor"; then
    test_result "Multifactor priority enabled" "PASS"
else
    test_result "Multifactor priority enabled" "FAIL" "Multifactor not configured"
fi

# 4. K8s 리소스 생성 테스트
echo -e "\n${YELLOW}[4] K8s Resource Creation Tests${NC}"

# 4.1 테스트 Job 제출
TEST_JOB_SUBMIT="/tmp/test-k8s-job.sh"
cat > "$TEST_JOB_SUBMIT" <<'EOF'
#!/bin/bash
#SBATCH --job-name=k8s-test
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/tmp/k8s-test-%j.out
#SBATCH --error=/tmp/k8s-test-%j.err
#K8S_IMAGE=nas-hub.local:5407/alpine:latest
sleep 10
echo "K8s integration test completed"
EOF

JOB_ID=$(sbatch "$TEST_JOB_SUBMIT" 2>/dev/null | grep -oP '\d+' || echo "")

if [[ -n "$JOB_ID" ]]; then
    test_result "Job submission to Slurm" "PASS"
    
    # Pod 생성 대기
    sleep 5
    
    # 4.2 Pod 생성 확인
    if kubectl get pod "slurm-job-${JOB_ID}" &>/dev/null; then
        test_result "K8s Pod creation" "PASS"
    else
        test_result "K8s Pod creation" "FAIL" "Pod not created"
    fi
    
    # 4.3 PVC 생성 확인
    if kubectl get pvc | grep -q "$JOB_ID"; then
        test_result "K8s PVC creation" "PASS"
    else
        test_result "K8s PVC creation" "FAIL" "PVC not created"
    fi
    
    # Job 취소
    scancel "$JOB_ID" 2>/dev/null || true
else
    test_result "Job submission to Slurm" "FAIL" "Job submission failed"
fi

# 5. 결과 수집 테스트
echo -e "\n${YELLOW}[5] Result Collection Tests${NC}"

# 5.1 결과 디렉토리 생성 확인
RESULT_DIR="/mnt/nas/results"
if [[ -d "$RESULT_DIR" ]]; then
    test_result "Result directory accessible" "PASS"
else
    test_result "Result directory accessible" "FAIL" "$RESULT_DIR not found"
fi

# 5.2 로그 수집 구조 확인
if [[ -x /usr/local/bin/slurm_k8s_epilog.sh ]]; then
    test_result "Epilog script executable" "PASS"
else
    test_result "Epilog script executable" "FAIL" "Epilog not executable"
fi

# 6. 전체 워크플로우 통합 테스트
echo -e "\n${YELLOW}[6] End-to-End Workflow Test${NC}"

E2E_JOB="/tmp/e2e-test-job.sh"
cat > "$E2E_JOB" <<'EOF'
#!/bin/bash
#SBATCH --job-name=e2e-test
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:02:00
#SBATCH --output=/mnt/nas/results/e2e-%j.out
#SBATCH --error=/mnt/nas/results/e2e-%j.err
#K8S_IMAGE=nas-hub.local:5407/alpine:latest

echo "E2E test started at $(date)"
echo "Job ID: $SLURM_JOB_ID"
sleep 30
echo "E2E test completed at $(date)"
EOF

E2E_JOB_ID=$(sbatch "$E2E_JOB" 2>/dev/null | grep -oP '\d+' || echo "")

if [[ -n "$E2E_JOB_ID" ]]; then
    echo "Submitted E2E test job: $E2E_JOB_ID"
    
    # Job 완료 대기 (최대 5분)
    TIMEOUT=300
    ELAPSED=0
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        JOB_STATE=$(scontrol show job "$E2E_JOB_ID" 2>/dev/null | grep -oP 'JobState=\K\w+' || echo "NOTFOUND")
        
        if [[ "$JOB_STATE" == "COMPLETED" ]]; then
            test_result "E2E workflow completion" "PASS"
            
            # 결과 파일 확인
            if [[ -f "/mnt/nas/results/e2e-${E2E_JOB_ID}.out" ]]; then
                test_result "E2E result file creation" "PASS"
            else
                test_result "E2E result file creation" "FAIL" "Output file not found"
            fi
            break
        elif [[ "$JOB_STATE" == "FAILED" || "$JOB_STATE" == "CANCELLED" ]]; then
            test_result "E2E workflow completion" "FAIL" "Job state: $JOB_STATE"
            break
        fi
        
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        test_result "E2E workflow completion" "FAIL" "Timeout waiting for job completion"
    fi
else
    test_result "E2E workflow submission" "FAIL" "Could not submit E2E test job"
fi

# 최종 결과 출력
echo -e "\n=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo "=========================================="

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
