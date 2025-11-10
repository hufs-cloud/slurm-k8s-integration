# 🚀 GitHub로 빠르게 시작하기

## 가장 간단한 방법 (5분)

### 1단계: GitHub 저장소 생성 (2분)
```
1. GitHub.com 접속 → 로그인
2. 우측 상단 '+' → 'New repository' 클릭
3. Repository name: slurm-k8s-integration
4. Private 선택 (추천)
5. 'Create repository' 클릭
```

### 2단계: 로컬에서 업로드 (2분)

다운로드한 모든 파일이 있는 폴더에서:

```bash
cd ~/slurm-k8s-integration/  # 다운로드한 파일들이 있는 폴더

git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/승상님계정명/slurm-k8s-integration.git
git push -u origin main
```

### 3단계: 서버에서 Clone (1분)

```bash
# 서버 접속
ssh user@slurm-server

# Clone
git clone https://github.com/승상님계정명/slurm-k8s-integration.git
cd slurm-k8s-integration/

# 바로 설치!
sudo bash install.sh
```

---

## Private 저장소 접근 방법

### 방법 A: SSH Key (가장 편함, 추천)

**서버에서 한번만 설정:**
```bash
# 1. SSH Key 생성
ssh-keygen -t ed25519 -C "your_email@example.com"
# Enter 3번 눌러서 기본값 사용

# 2. 공개키 복사
cat ~/.ssh/id_ed25519.pub
# 출력된 내용 전체 복사
```

**GitHub에 등록:**
```
1. GitHub → Settings → SSH and GPG keys
2. 'New SSH key' 클릭
3. Title: "Slurm Server"
4. Key: 복사한 내용 붙여넣기
5. 'Add SSH key' 클릭
```

**Clone 시:**
```bash
git clone git@github.com:승상님계정명/slurm-k8s-integration.git
```

### 방법 B: Personal Access Token (간단함)

**Token 생성:**
```
1. GitHub → Settings → Developer settings
2. Personal access tokens → Tokens (classic)
3. 'Generate new token (classic)'
4. Note: "slurm-server"
5. Expiration: 90 days
6. ✅ repo (전체 체크)
7. 'Generate token' 클릭
8. 토큰 복사! (다시 볼 수 없음)
```

**Clone 시:**
```bash
git clone https://토큰@github.com/승상님계정명/slurm-k8s-integration.git
```

---

## 완전 자동화 워크플로우

```bash
# === 로컬 PC에서 ===

# 1. GitHub 저장소 생성 (웹에서)

# 2. 파일들 정리
mkdir slurm-k8s-integration
cd slurm-k8s-integration
# 다운로드한 모든 파일 이 폴더로 이동

# 3. Git 초기화 및 푸시
git init
git add .
git commit -m "Initial commit: Slurm-K8s integration"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
git push -u origin main


# === 서버에서 ===

# 1. Clone
git clone https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
cd slurm-k8s-integration/

# 2. 자동 설치
sudo bash install.sh

# 3. Slurm 설정 업데이트 (install.sh가 안내하는 대로)
sudo nano /etc/slurm/slurm.conf
# slurm.conf.example 내용 참고해서 추가

# 4. 서비스 시작
sudo systemctl restart slurmctld
sudo systemctl start slurm-job-watcher

# 5. 테스트!
sbatch example-job.sh
watch -n 2 'squeue; echo "---"; kubectl get pods -l app=slurm-job'
```

---

## 수정사항 반영 (나중에)

### 로컬에서 수정 후
```bash
git add .
git commit -m "Update: 프롤로그 스크립트 수정"
git push
```

### 서버에서 최신 버전 받기
```bash
cd ~/slurm-k8s-integration/
git pull
sudo bash install.sh  # 재설치
```

---

## 파일 구조 (GitHub에 올라갈 내용)

```
slurm-k8s-integration/
├── .gitignore                   # Git 제외 파일 목록
├── README.md                    # 프로젝트 소개
├── QUICK_START.md              # 빠른 시작 가이드
├── IMPLEMENTATION_GUIDE.md     # 상세 구현 가이드
├── GITHUB_SETUP.md             # 이 파일
├── install.sh                  # 자동 설치 스크립트
├── slurm_k8s_prolog.sh         # Prolog 스크립트
├── slurm_k8s_epilog.sh         # Epilog 스크립트
├── job_validator.sh            # Job 검증
├── job_watcher.sh              # Job 감시
├── test_suite.sh               # 테스트
├── slurm.conf.example          # Slurm 설정 예시
├── pod-template.yaml           # K8s YAML 템플릿
└── example-job.sh              # 샘플 Job
```

---

## 체크리스트

### GitHub 준비
- [ ] GitHub 계정 있음
- [ ] 새 저장소 생성 완료
- [ ] Private/Public 결정

### 로컬 설정
- [ ] 모든 파일 다운로드 완료
- [ ] 한 폴더에 모음
- [ ] Git 설치 확인 (`git --version`)

### 서버 설정  
- [ ] 서버 SSH 접속 가능
- [ ] Git 설치 확인
- [ ] SSH Key 또는 Token 준비 (Private 저장소인 경우)

### 설치
- [ ] Clone 완료
- [ ] `install.sh` 실행 완료
- [ ] Slurm 설정 업데이트
- [ ] 서비스 재시작
- [ ] 테스트 Job 실행 성공

---

## 문제 해결

### "Permission denied (publickey)" 에러
→ SSH Key 설정 안됨. 위의 "방법 A: SSH Key" 따라하기

### "Repository not found" 에러  
→ 저장소 이름 확인 또는 Token 사용

### Clone은 되는데 Private 저장소 안보임
→ GitHub 로그인 확인, Token 권한 확인

---

## 추천: 이렇게 하세요!

```bash
# 1. GitHub에서 Private 저장소 생성
# 2. 서버에서 SSH Key 설정 (한 번만)
# 3. Clone
# 4. sudo bash install.sh
# 5. 끝!
```

**시간: 약 10분**
- GitHub 저장소 생성: 2분
- SSH Key 설정: 3분  
- Clone & 설치: 5분

---

## 다음에 할 일

설치 완료 후:
1. `QUICK_START.md` 보면서 세부 설정
2. `test_suite.sh` 실행해서 전체 검증
3. 실제 워크로드로 테스트

팀 협업:
- 각자 브랜치 만들어서 작업
- Pull Request로 코드 리뷰
- main 브랜치는 항상 안정적으로 유지
