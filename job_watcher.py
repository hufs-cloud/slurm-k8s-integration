#!/usr/bin/env python3
"""Job 파일 감시 및 처리 모듈"""

import logging
import time
from pathlib import Path
from datetime import datetime
import json
import inotify.adapters
from job_validator import JobValidator

class JobWatcher:
    """Job 파일 감시 및 검증 클래스"""

    USER_BASE_DIR = Path('/mnt/test-k8s/users')

    def __init__(self, queue_dir: str, failed_dir: str):
        """
        Args:
            queue_dir: 검증 통과한 Job 정보 저장 경로
            failed_dir: 검증 실패한 Job 정보 저장 경로
        """
        self.queue_dir = Path(queue_dir)
        self.failed_dir = Path(failed_dir)
        self.validator = JobValidator()

        # 디렉토리 생성
        self.USER_BASE_DIR.mkdir(parents=True, exist_ok=True)
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        self.failed_dir.mkdir(parents=True, exist_ok=True)

        # 로깅 설정
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(Path.home() / 'job-watcher.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def start(self):
        """파일 감시 시작 - users 디렉토리 전체 감시"""
        self.logger.info(f"사용자 디렉토리 감시 시작: {self.USER_BASE_DIR}")
        self.logger.info(f"큐 디렉토리: {self.queue_dir}")
        self.logger.info(f"실패 디렉토리: {self.failed_dir}")

        # users 디렉토리 전체를 재귀적으로 감시
        i = inotify.adapters.InotifyTree(str(self.USER_BASE_DIR))

        try:
            for event in i.event_gen(yield_nones=False):
                (_, type_names, path, filename) = event

                # job_spec.yaml 파일이 생성되거나 수정된 경우
                if 'IN_CLOSE_WRITE' in type_names or 'IN_MOVED_TO' in type_names:
                    if filename == 'job_spec.yaml':
                        job_file = Path(path) / filename
                        self.logger.info(f"새 Job 파일 감지: {job_file}")
                        self._process_job_file(job_file)

        except KeyboardInterrupt:
            self.logger.info("감시 종료 (사용자 중단)")
        except Exception as e:
            self.logger.error(f"감시 중 오류 발생: {e}")

    def _process_job_file(self, job_file: Path):
        """Job 파일 처리"""
        try:
            # 파일 쓰기 완료 대기
            time.sleep(0.2)

            # 검증
            is_valid, errors, data = self.validator.validate(job_file)

            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

            if is_valid:
                # 검증 성공
                job_name = self.validator.generate_job_name(data)

                # job_spec.yaml은 원래 자리에 유지
                # 큐에는 메타데이터만 저장
                queue_file = self.queue_dir / f"{timestamp}_{job_name}.json"

                # 메타데이터 생성 및 저장
                metadata = self._create_metadata(job_file, data, job_name, timestamp)
                with open(queue_file, 'w', encoding='utf-8') as f:
                    json.dump(metadata, f, indent=2, ensure_ascii=False)

                self.logger.info(f"✓ 검증 통과: {job_file} -> 큐에 추가 ({job_name})")

            else:
                # 검증 실패
                user_dir = job_file.parent.name
                failed_file = self.failed_dir / f"{timestamp}_{user_dir}.json"

                # 실패 정보 저장
                failure_info = {
                    'job_file': str(job_file),
                    'failed_at': datetime.now().isoformat(),
                    'errors': errors,
                    'data': data if data else None
                }

                with open(failed_file, 'w', encoding='utf-8') as f:
                    json.dump(failure_info, f, indent=2, ensure_ascii=False)

                self.logger.error(f"✗ 검증 실패: {job_file}")
                for error in errors:
                    self.logger.error(f"  - {error}")

        except Exception as e:
            self.logger.error(f"Job 파일 처리 중 오류: {job_file} - {e}")

    def _create_metadata(self, job_file: Path, data: dict, job_name: str, timestamp: str) -> dict:
        """메타데이터 생성"""

        # preset 기본값 설정
        preset = data['resource'].get('preset', 'standard')
        resource_spec = self.validator.RESOURCE_PRESETS[preset]

        metadata = {
            'job_name': job_name,
            'job_id': f"{timestamp}_{job_name}",
            'submitted_at': datetime.now().isoformat(),
            'status': 'queued',
            'type': data['type'],
            'id': data['id'],
            'resource': {
                'gpu': data['resource']['gpu'],
                'preset': preset,
                'cpu': resource_spec['cpu'],
                'memory': resource_spec['memory']
            },
            'script': data['script'],
            'paths': {
                'job_spec': str(job_file),
                'user_dir': str(job_file.parent),
                'script_path': str(job_file.parent / data['script'])
            }
        }

        # index가 있으면 추가
        if 'index' in data and data['index']:
            metadata['index'] = data['index']

        # data가 있으면 추가
        if 'data' in data and data['data']:
            metadata['data'] = data['data']
            metadata['paths']['data_dir'] = str(job_file.parent / 'data')

        return metadata