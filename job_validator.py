#!/usr/bin/env python3
"""Job 파일 검증 모듈"""

import yaml
import re
from pathlib import Path
from typing import Tuple, List

class JobValidator:
    """Job spec 파일 검증 클래스"""

    VALID_TYPES = ['std', 'grad', 'prof', 'cls']
    VALID_PRESETS = ['small', 'standard', 'large']
    USER_BASE_DIR = Path('/mnt/test-k8s/users')

    # 리소스 preset 정의
    RESOURCE_PRESETS = {
        'small': {
            'cpu': 2,
            'memory': '8Gi'
        },
        'standard': {
            'cpu': 4,
            'memory': '16Gi'
        },
        'large': {
            'cpu': 8,
            'memory': '32Gi'
        }
    }

    def __init__(self):
        self.errors = []

    def validate(self, job_file: Path) -> Tuple[bool, List[str], dict]:
        """
        Job spec 파일 검증

        Args:
            job_file: 검증할 Job 파일 경로

        Returns:
            (is_valid, error_messages, parsed_data)
        """
        self.errors = []

        # 1. 파일 존재 확인
        if not job_file.exists():
            self.errors.append(f"파일이 존재하지 않습니다: {job_file}")
            return False, self.errors, {}

        # 2. YAML 파싱
        try:
            with open(job_file, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            self.errors.append(f"YAML 파싱 오류: {e}")
            return False, self.errors, {}
        except Exception as e:
            self.errors.append(f"파일 읽기 오류: {e}")
            return False, self.errors, {}

        # 3. 필수 필드 검증
        if not self._validate_required_fields(data):
            return False, self.errors, data

        # 4. 필드 값 검증
        if not self._validate_field_values(data):
            return False, self.errors, data

        # 5. 파일 존재 확인
        if not self._validate_files_exist(data, job_file.parent):
            return False, self.errors, data

        return True, [], data

    def _validate_required_fields(self, data: dict) -> bool:
        """필수 필드 존재 여부 확인"""

        if not isinstance(data, dict):
            self.errors.append("Job 파일은 딕셔너리 형태여야 합니다")
            return False

        # type 필드
        if 'type' not in data:
            self.errors.append("type 필드가 필요합니다")
            return False

        # id 필드
        if 'id' not in data:
            self.errors.append("id 필드가 필요합니다")
            return False

        # resource 필드
        if 'resource' not in data:
            self.errors.append("resource 필드가 필요합니다")
            return False

        if not isinstance(data['resource'], dict):
            self.errors.append("resource는 딕셔너리여야 합니다")
            return False

        if 'gpu' not in data['resource']:
            self.errors.append("resource.gpu 필드가 필요합니다")
            return False

        # script 필드
        if 'script' not in data:
            self.errors.append("script 필드가 필요합니다")
            return False

        return True

    def _validate_field_values(self, data: dict) -> bool:
        """필드 값 검증"""

        # type 검증
        job_type = data['type']
        if job_type not in self.VALID_TYPES:
            self.errors.append(
                f"type은 {self.VALID_TYPES} 중 하나여야 합니다"
            )
            return False

        # id 검증
        job_id = data['id']
        if not isinstance(job_id, str) or not job_id:
            self.errors.append("id는 비어있지 않은 문자열이어야 합니다")
            return False

        if not re.match(r'^[a-zA-Z0-9]+$', job_id):
            self.errors.append("id는 영문자와 숫자만 포함해야 합니다")
            return False

        # cls 타입은 index 필수
        if job_type == 'cls':
            if 'index' not in data or data['index'] is None:
                self.errors.append("cls 타입은 index 필드가 필요합니다")
                return False
            if not isinstance(data['index'], int) or data['index'] < 1:
                self.errors.append("index는 1 이상의 정수여야 합니다")
                return False

        # GPU 개수 검증
        gpu = data['resource']['gpu']
        if not isinstance(gpu, int):
            self.errors.append("resource.gpu는 정수여야 합니다")
            return False

        if gpu < 0:
            self.errors.append("resource.gpu는 0 이상이어야 합니다")
            return False

        # preset 검증 (선택사항)
        if 'preset' in data['resource']:
            preset = data['resource']['preset']
            if preset not in self.VALID_PRESETS:
                self.errors.append(
                    f"resource.preset은 {self.VALID_PRESETS} 중 하나여야 합니다"
                )
                return False

        # script 검증
        script = data['script']
        if not isinstance(script, str):
            self.errors.append("script는 문자열이어야 합니다")
            return False

        if not script.endswith('.sh'):
            self.errors.append("script는 .sh 파일이어야 합니다")
            return False

        return True

    def _validate_files_exist(self, data: dict, user_dir: Path) -> bool:
        """실제 파일 존재 확인"""

        # 스크립트 파일 존재 확인
        script_file = user_dir / data['script']
        if not script_file.exists():
            self.errors.append(f"스크립트 파일이 없습니다: {script_file}")
            return False

        # 데이터 파일/폴더 확인 (선택사항)
        if 'data' in data and data['data']:
            if not isinstance(data['data'], list):
                self.errors.append("data는 리스트여야 합니다")
                return False

            data_dir = user_dir / 'data'
            if not data_dir.exists():
                self.errors.append(f"data 디렉토리가 없습니다: {data_dir}")
                return False

            for item in data['data']:
                data_path = data_dir / item
                if not data_path.exists():
                    self.errors.append(f"데이터가 없습니다: {data_path}")
                    return False

        return True

    def generate_job_name(self, data: dict) -> str:
        """
        Job 이름 생성: job-{TYPE}-{ID}-{INDEX}

        Examples:
            job-std-202431152
            job-cls-F2123523-3
            job-grad-202012345
            job-prof-P001234
        """
        job_type = data['type']
        job_id = data['id']

        if job_type == 'cls' and 'index' in data and data['index']:
            return f"job-{job_type}-{job_id}-{data['index']}"
        else:
            return f"job-{job_type}-{job_id}"

    def generate_user_dirname(self, data: dict) -> str:
        """
        사용자 디렉토리 이름 생성: {TYPE}-{ID}

        Examples:
            std-202431152
            cls-F2123523
        """
        return f"{data['type']}-{data['id']}"