#!/usr/bin/env python3
"""Job Watcher 실행 스크립트"""

import sys
from job_watcher import JobWatcher

if __name__ == '__main__':
    # 디렉토리 경로
    QUEUE_DIR = '/mnt/test-k8s/job-queue'
    FAILED_DIR = '/mnt/test-k8s/job-failed'

    print("=" * 60)
    print("Job Watcher 시작")
    print("=" * 60)
    print(f"감시 대상:     /mnt/test-k8s/users/**/job_spec.yaml")
    print(f"큐 디렉토리:   {QUEUE_DIR}")
    print(f"실패 디렉토리: {FAILED_DIR}")
    print("=" * 60)
    print("종료: Ctrl+C\n")

    try:
        watcher = JobWatcher(QUEUE_DIR, FAILED_DIR)
        watcher.start()
    except Exception as e:
        print(f"오류 발생: {e}", file=sys.stderr)
        sys.exit(1)