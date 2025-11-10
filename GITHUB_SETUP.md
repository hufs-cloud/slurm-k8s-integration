# GitHub 저장소 설정 가이드

## 방법 1: 새 저장소 생성 (추천)

### 1단계: GitHub에서 새 저장소 생성
1. GitHub 로그인 → 우측 상단 `+` → `New repository`
2. 저장소 이름: `slurm-k8s-integration` (또는 원하는 이름)
3. **Private** 선택 (보안상 권장)
4. ✅ **Add a README file** 체크 해제 (우리가 이미 만들었으므로)
5. `.gitignore` 선택: **None** (우리가 직접 만들 것)
6. `Create repository` 클릭

### 2단계: 로컬에서 Git 초기화 및 푸시

```bash
# 다운로드한 파일들이 있는 디렉토리로 이동
cd ~/slurm-k8s-integration/

# Git 초기화
git init

# 모든 파일 추가
git add .

# 첫 커밋
git commit -m "Initial commit: Slurm-K8s integration system"

# 원격 저장소 연결 (YOUR_USERNAME을 실제 GitHub 계정명으로 변경)
git remote add origin https://github.com/YOUR_USERNAME/slurm-k8s-integration.git

# 기본 브랜치 이름을 main으로 변경
git branch -M main

# GitHub에 푸시
git push -u origin main
```

### 3단계: 서버에서 Clone

```bash
# 서버 접속
ssh user@slurm-server

# Clone (Private 저장소인 경우 GitHub 인증 필요)
git clone https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
cd slurm-k8s-integration/

# 바로 설치 시작!
bash QUICK_START.md
```

---

## 방법 2: GitHub Personal Access Token 사용 (Private 저장소)

Private 저장소를 사용하는 경우 Personal Access Token이 필요합니다.

### PAT 생성
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. `Generate new token (classic)` 클릭
3. Note: `slurm-k8s-server`
4. Expiration: `90 days` (또는 적절한 기간)
5. 권한 선택:
   - ✅ `repo` (전체 선택)
6. `Generate token` 클릭
7. **토큰 복사** (다시 볼 수 없으므로 안전한 곳에 저장)

### Clone 시 토큰 사용
```bash
# 서버에서
git clone https://YOUR_TOKEN@github.com/YOUR_USERNAME/slurm-k8s-integration.git
```

---

## 방법 3: SSH Key 사용 (가장 편리)

### SSH Key 생성 (서버에서)
```bash
# 서버에서 실행
ssh-keygen -t ed25519 -C "your_email@example.com"
# Enter 3번 (기본 경로, 비밀번호 없음)

# 공개키 출력
cat ~/.ssh/id_ed25519.pub
# 출력된 내용 복사
```

### GitHub에 SSH Key 등록
1. GitHub → Settings → SSH and GPG keys → New SSH key
2. Title: `Slurm Server`
3. Key: 복사한 공개키 붙여넣기
4. `Add SSH key` 클릭

### Clone 시 SSH 사용
```bash
# 서버에서
git clone git@github.com:YOUR_USERNAME/slurm-k8s-integration.git
```

---

## 업데이트 워크플로우

### 로컬에서 수정 후 푸시
```bash
# 파일 수정 후
git add .
git commit -m "Update: 스크립트 수정"
git push
```

### 서버에서 최신 버전 받기
```bash
cd ~/slurm-k8s-integration/
git pull

# 스크립트 재설치
sudo cp *.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh
sudo systemctl restart slurm-job-watcher
```

---

## 브랜치 전략 (팀 작업용)

```bash
# 각 담당자별 브랜치 생성
git checkout -b feature/job-validator    # 최윤서
git checkout -b feature/scheduling       # 김금동
git checkout -b feature/result-collector # 박세현

# 작업 후 커밋
git add .
git commit -m "Add: Job validator logic"
git push origin feature/job-validator

# GitHub에서 Pull Request 생성
# → 코드 리뷰 후 main 브랜치로 merge
```

---

## 권장 디렉토리 구조

```
slurm-k8s-integration/
├── README.md                    # 프로젝트 개요
├── QUICK_START.md              # 빠른 시작 가이드
├── IMPLEMENTATION_GUIDE.md     # 상세 구현 가이드
├── .gitignore                  # Git 제외 파일
├── scripts/                    # 실행 스크립트
│   ├── slurm_k8s_prolog.sh
│   ├── slurm_k8s_epilog.sh
│   ├── job_validator.sh
│   ├── job_watcher.sh
│   └── install.sh              # 설치 자동화 스크립트
├── config/                     # 설정 파일
│   ├── slurm.conf.example
│   └── pod-template.yaml
├── examples/                   # 예제 파일
│   └── example-job.sh
├── tests/                      # 테스트 스크립트
│   └── test_suite.sh
└── docs/                       # 추가 문서
    └── troubleshooting.md
```

---

## 보안 주의사항

### .gitignore에 추가해야 할 것들
- 실제 Slurm 설정 파일 (slurm.conf - 내부 정보 포함)
- 로그 파일
- 임시 파일
- 개인 정보가 포함된 Job 파일

```gitignore
# 로그 파일
*.log
logs/

# Slurm 설정 (example은 제외)
slurm.conf
!slurm.conf.example

# Job 파일 (실제 사용자 데이터)
*.sbatch
jobs/

# 임시 파일
*.tmp
*.swp
.DS_Store

# 환경 설정
.env
secrets/
```

---

## 자동 설치 스크립트 추가 (선택사항)

더 편리하게 만들고 싶다면 `install.sh`를 추가하세요:

```bash
#!/bin/bash
# install.sh

echo "Installing Slurm-K8s Integration System..."

# 스크립트 설치
sudo cp scripts/*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh

# 로그 디렉토리 생성
sudo mkdir -p /var/log/slurm-k8s
sudo chown slurm:slurm /var/log/slurm-k8s

# NAS 디렉토리 생성
mkdir -p /mnt/nas/slurm-jobs/{submit,processed,failed}
mkdir -p /mnt/nas/results

echo "Installation complete!"
echo "Next steps:"
echo "1. Update /etc/slurm/slurm.conf (see config/slurm.conf.example)"
echo "2. sudo systemctl restart slurmctld"
echo "3. Setup job-watcher service"
```

사용법:
```bash
git clone https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
cd slurm-k8s-integration/
chmod +x install.sh
./install.sh
```

---

## 추천 워크플로우

1. **GitHub에 Private 저장소 생성**
2. **서버에서 SSH Key 설정** (한 번만)
3. **Clone 받기**
4. **QUICK_START.md 따라 설치**
5. **수정사항 있으면 커밋 & 푸시**
6. **다른 서버에서도 같은 설정 적용 가능**

이렇게 하면:
- ✅ 버전 관리 용이
- ✅ 여러 서버에 동일한 설정 적용 가능
- ✅ 팀원들과 협업 가능
- ✅ 롤백 가능 (문제 발생 시 이전 버전으로)
