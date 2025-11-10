# ⚡ 5분 완성 가이드

Slurm-K8s 통합 시스템을 가장 빠르게 시작하는 방법입니다.

## 🎯 목표
- Slurm으로 Job 스케줄링
- K8s에서 실제 실행
- 5분 안에 첫 Job 실행!

---

## 📦 Step 1: GitHub에서 받기 (1분)

```bash
# 서버 접속
ssh user@your-slurm-server

# Clone (Public 저장소)
git clone https://github.com/YOUR_USERNAME/slurm-k8s-integration.git
cd slurm-k8s-integration/

# Private 저장소면 SSH Key 설정 필요
# → GITHUB_QUICK_GUIDE.md 참고
```

---

## 🔧 Step 2: 자동 설치 (2분)

```bash
# 설치 스크립트 실행
sudo bash install.sh

# 화면에 나오는 안내 따라하기
# ✅ Slurm 설정 추가 필요하면 알려줌
# ✅ 모든 디렉토리 자동 생성
# ✅ 서비스 자동 구성
```

---

## ⚙️ Step 3: Slurm 설정 (1분)

```bash
# Slurm 설정 파일 열기
sudo nano /etc/slurm/slurm.conf

# 아래 3줄만 추가하면 됨 (파일 끝에)
Prolog=/usr/local/bin/slurm_k8s_prolog.sh
Epilog=/usr/local/bin/slurm_k8s_epilog.sh
PrologEpilogTimeout=600

# 저장: Ctrl+O, Enter, Ctrl+X

# Slurm 재시작
sudo systemctl restart slurmctld
```

---

## 🚀 Step 4: 서비스 시작 (30초)

```bash
# Job Watcher 시작
sudo systemctl start slurm-job-watcher

# 상태 확인
sudo systemctl status slurm-job-watcher
```

---

## ✅ Step 5: 첫 테스트! (30초)

```bash
# 예제 Job 제출
sbatch example-job.sh

# 실시간 모니터링
watch -n 2 'echo "=== Slurm Queue ==="; squeue; echo ""; echo "=== K8s Pods ==="; kubectl get pods -l app=slurm-job'

# Ctrl+C로 종료
```

**성공하면 이렇게 보임:**
```
=== Slurm Queue ===
JOBID PARTITION  NAME     USER  ST  TIME  NODES
12345 gpu        hello    user  R   0:10  k8s-virtual

=== K8s Pods ===
NAME              READY   STATUS    RESTARTS   AGE
slurm-job-12345   1/1     Running   0          12s
```

---

## 🎉 완료!

축하합니다! 이제 Slurm-K8s 통합 시스템이 작동합니다!

### 결과 확인
```bash
# Job 완료 후 결과 보기
ls /mnt/nas/results/
cat /mnt/nas/results/12345/stdout.log
```

### 다음 Job 제출
```bash
# 방법 1: NAS 폴더에 복사 (자동 제출)
cp my_job.sh /mnt/nas/slurm-jobs/submit/

# 방법 2: 직접 제출
sbatch my_job.sh
```

---

## 📚 더 알아보기

- **Job 작성법**: `example-job.sh` 참고
- **상세 설정**: `QUICK_START.md`
- **문제 해결**: `IMPLEMENTATION_GUIDE.md`
- **GitHub 활용**: `GITHUB_QUICK_GUIDE.md`

---

## 🆘 문제가 생기면?

### Pod가 안 생김
```bash
# Prolog 로그 확인
tail -f /var/log/slurm-k8s/prolog_*.log

# 이미지 확인
nerdctl-safe images | grep nas-hub.local
```

### Job이 큐에만 있음
```bash
# 원인 확인
scontrol show job JOB_ID | grep Reason

# K8s 리소스 확인
kubectl get nodes
kubectl top nodes
```

### 결과 파일이 없음
```bash
# Epilog 로그 확인
tail -f /var/log/slurm-k8s/epilog_*.log

# NAS 마운트 확인
mountpoint /mnt/nas
```

---

## ⏱️ 소요 시간 요약

1. GitHub Clone: **1분**
2. 자동 설치: **2분**
3. Slurm 설정: **1분**
4. 서비스 시작: **30초**
5. 첫 테스트: **30초**

**총 5분!**

---

## 🎯 체크리스트

설치 전:
- [ ] Slurm 설치되어 있음
- [ ] K8s 클러스터 구성됨
- [ ] NAS 마운트됨 (`/mnt/nas`)
- [ ] 서버 SSH 접속 가능

설치 후:
- [ ] `install.sh` 실행 완료
- [ ] Slurm 설정 업데이트
- [ ] `slurmctld` 재시작
- [ ] `slurm-job-watcher` 시작
- [ ] 테스트 Job 성공

---

**이제 시작하세요! 🚀**

문제가 생기면 다른 문서들을 참고하거나
로그 파일(`/var/log/slurm-k8s/`)을 확인해보세요!
