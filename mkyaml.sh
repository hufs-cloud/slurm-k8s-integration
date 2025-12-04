#!/bin/bash

# Kubernetes Manifest Generator Script
# Usage:
#   mkyaml {manifest_type} {resource}{num} {cls|std} {id} [index] [port]
# Examples:
#   mkyaml pv  gpu4 std 201900650
#   mkyaml pvc cpu1 cls F05401302 3
#   mkyaml deploy gpu4 std 201900650           # auto-picks free NodePort
#   mkyaml deploy cpu1 cls F05401302 3 30001   # explicit NodePort


show_help() {
  cat << EOF
=================================================
       Kubernetes Manifest Generator
=================================================

사용법:
    mkyaml [옵션] {매니페스트타입} {리소스}{번호} {cls|std} {ID} [인덱스] [포트]

매니페스트 타입:
    pv          PersistentVolume 생성
    pvc         PersistentVolumeClaim 생성
    deploy      Deployment + Service 생성

리소스:
    cpu{번호}   CPU 노드 (예: cpu1, cpu2)
    gpu{번호}   GPU 노드 (예: gpu1, gpu4)

타입:
    cls         수업용 (인덱스 필수)
    std         개별 학습용 (인덱스 불필요)

포트 자동 할당:
    deployment에서 포트를 생략하면, 현재 클러스터의 NodePort(30000~32767) 중
    "가장 작은 비어있는 값"을 kubectl을 통해 자동 선택합니다.

출력 위치:
    \$HOME/yaml/{cpu|gpu}-node{N}/{이름}.yaml

옵션:
    -h, --help      도움말 표시
=================================================
EOF
}

if [ $# -eq 0 ]; then
  show_help; exit 0
fi

case "$1" in
  -h|--h|--help|-help)
    show_help; exit 0;;
esac

# ---- Arguments --------------------------------------------------------------
if [ $# -lt 4 ]; then
  echo "오류: 매개변수가 부족합니다." >&2
  show_help; exit 1
fi

MANIFEST_TYPE=$1           # pv|pvc|deploy
RESOURCE_NUM=$2            # cpuN|gpuN
TYPE=$3                    # cls|std
ID=$4                      # user/student id
INDEX=${5:-}               # cls일 때 필수
# PORT는 아래에서 cls/std에 따라 위치 재해석

# ---- Validate manifest type -------------------------------------------------
if [[ ! "$MANIFEST_TYPE" =~ ^(pv|pvc|deploy)$ ]]; then
  echo "오류: 첫 번째 매개변수는 pv|pvc|deploy 중 하나여야 합니다." >&2
  exit 1
fi

# ---- Parse resource ---------------------------------------------------------
if [[ $RESOURCE_NUM =~ ^(cpu|gpu)([0-9]+)$ ]]; then
  RESOURCE=${BASH_REMATCH[1]}  # cpu|gpu
  NUM=${BASH_REMATCH[2]}       # digits
else
  echo "오류: 두 번째 매개변수는 cpu{숫자} 또는 gpu{숫자} 형태여야 합니다. (예: cpu1, gpu4)" >&2
  exit 1
fi

# ---- Validate type & index --------------------------------------------------
if [[ ! "$TYPE" =~ ^(cls|std)$ ]]; then
  echo "오류: 세 번째 매개변수는 cls 또는 std 여야 합니다." >&2
  exit 1
fi

if [ "$TYPE" = "cls" ]; then
  if [ -z "${INDEX:-}" ]; then
    echo "오류: cls 타입에서는 인덱스가 필요합니다. 예: mkyaml pv cpu1 cls F05401302 3" >&2
    exit 1
  fi
  if [[ ! "$INDEX" =~ ^[0-9]+$ ]]; then
    echo "오류: 인덱스는 숫자여야 합니다." >&2
    exit 1
  fi
else
  if [ -n "${INDEX:-}" ]; then
    echo "경고: std 타입에서는 인덱스가 필요하지 않습니다. 무시합니다." >&2
    INDEX=""
  fi
fi

# ---- NodePort picker --------------------------------------------------------
# Returns the smallest free NodePort within range [NODEPORT_START, NODEPORT_END]
pick_free_nodeport() {
  local start="${NODEPORT_START:-30000}"
  local end="${NODEPORT_END:-32767}"

  # collect used nodePorts (ignore empty)
  mapfile -t used < <(
    kubectl get svc -A -o jsonpath='{range .items[*].spec.ports[*]}{.nodePort}{"\n"}{end}' 2>/dev/null \
    | awk 'NF' | sort -n | uniq
  )

  local p
  for ((p=start; p<=end; p++)); do
    if ! printf '%s\n' "${used[@]}" | grep -qx -- "$p"; then
      echo "$p"
      return 0
    fi
  done

  echo "오류: 사용 가능한 NodePort가 없습니다." >&2
  return 1
}

# ---- Compute NAME, PORT, defaults ------------------------------------------
if [ "$MANIFEST_TYPE" = "deploy" ]; then
  # Port position differs by type
  if [ "$TYPE" = "cls" ]; then
    PORT=${6:-}
  else
    PORT=${5:-}
  fi
  # Auto-pick if not provided
  if [ -z "${PORT:-}" ]; then
    PORT="$(pick_free_nodeport)"
  fi
  # Validate
  if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt "${NODEPORT_START:-30000}" ] || [ "$PORT" -gt "${NODEPORT_END:-32767}" ]; then
    echo "오류: 포트 번호는 ${NODEPORT_START:-30000}-${NODEPORT_END:-32767} 범위의 숫자여야 합니다." >&2
    exit 1
  fi
fi

# Name scheme
if [ "$MANIFEST_TYPE" = "deploy" ]; then
  NAME="${RESOURCE}${NUM}-${TYPE}-${ID}$([ -n "${INDEX:-}" ] && echo "-${INDEX}")"
else
  NAME="${RESOURCE}${NUM}-${MANIFEST_TYPE}-${TYPE}-${ID}$([ -n "${INDEX:-}" ] && echo "-${INDEX}")"
fi

# Resource defaults
if [ "$RESOURCE" = "gpu" ]; then
  MEMORY_SIZE=24   # Gi
  CPU=3            # cores
  GPU=1
  DEFAULT_IMAGE="nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04"
else
  MEMORY_SIZE=16
  CPU=4
  GPU=""
  DEFAULT_IMAGE="ubuntu:22.04"
fi

# Storage size (Gi)
STORAGE_SIZE=300

# Output path
OUTPUT_DIR="${HOME}/yaml/${RESOURCE}-node${NUM}"
OUTPUT_FILE="${NAME}.yaml"
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
mkdir -p "${OUTPUT_DIR}"

# ---- Generators -------------------------------------------------------------
generate_pv() {
  cat << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${NAME}
spec:
  capacity:
    storage: ${STORAGE_SIZE}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/ssd
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${RESOURCE}-node${NUM}
EOF
}

generate_pvc() {
  cat << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: ${STORAGE_SIZE}Gi
EOF
}

generate_gpu_deployment() {
  cat << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - ${RESOURCE}-node${NUM}
      volumes:
      - name: local-persistent-storage
        persistentVolumeClaim:
          claimName: ${RESOURCE}${NUM}-pvc-${TYPE}-${ID}$([ -n "${INDEX:-}" ] && echo "-${INDEX}")
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 8Gi
      containers:
      - name: ${NAME}
        image: ${DEFAULT_IMAGE}
        imagePullPolicy: IfNotPresent
        command: ["/bin/bash","-lc"]
        args:
          - |
            set -e
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
              openssh-server vim tmux sudo rsyslog && \
              rm -rf /var/lib/apt/lists/*
            mkdir -p /var/run/sshd /run/sshd
            echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
            echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
            echo 'Port 22' >> /etc/ssh/sshd_config
            echo "root:${DEFAULT_POD_PW}" | chpasswd

            # CUDA 경로 환경 변수 설정
            echo 'export PATH=/usr/local/cuda/bin:$PATH' >>/etc/profile
            echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >>/etc/profile
            echo 'export CUDA_HOME=/usr/local/cuda' >>/etc/profile

            # rsyslog (옵션)
            rsyslogd || true

            exec /usr/sbin/sshd -D
        resources:
          limits:
            memory: "${MEMORY_SIZE}G"
            cpu: "${CPU}"
            nvidia.com/gpu: "${GPU}"
          requests:
            memory: "${MEMORY_SIZE}G"
            cpu: "${CPU}"
            nvidia.com/gpu: "${GPU}"
        ports:
        - containerPort: 22
        volumeMounts:
        - name: local-persistent-storage
          mountPath: /mnt/ssd
        - name: dshm
          mountPath: /dev/shm
      dnsConfig:
        nameservers:
        - 8.8.8.8
      imagePullSecrets:
      - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
spec:
  selector:
    app: ${NAME}
  ports:
  - name: ssh
    protocol: TCP
    port: 22
    targetPort: 22
    nodePort: ${PORT}
  type: NodePort
EOF
}

generate_cpu_deployment() {
  cat << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - ${RESOURCE}-node${NUM}
      volumes:
      - name: local-persistent-storage
        persistentVolumeClaim:
          claimName: ${RESOURCE}${NUM}-pvc-${TYPE}-${ID}$([ -n "${INDEX:-}" ] && echo "-${INDEX}")
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 8Gi
      containers:
      - name: ${NAME}
        image: ${DEFAULT_IMAGE}
        imagePullPolicy: IfNotPresent
        command: ["/bin/bash","-lc"]
        args:
          - |
            set -e
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
              openssh-server vim tmux sudo rsyslog && \
              rm -rf /var/lib/apt/lists/*
            mkdir -p /var/run/sshd /run/sshd
            echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
            echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
            echo 'Port 22' >> /etc/ssh/sshd_config
            echo "root:${DEFAULT_POD_PW}" | chpasswd
            rsyslogd || true
            exec /usr/sbin/sshd -D
        resources:
          limits:
            memory: "${MEMORY_SIZE}G"
            cpu: "${CPU}"
          requests:
            memory: "${MEMORY_SIZE}G"
            cpu: "${CPU}"
        ports:
        - containerPort: 22
        volumeMounts:
        - name: local-persistent-storage
          mountPath: /mnt/ssd
        - name: dshm
          mountPath: /dev/shm
      dnsConfig:
        nameservers:
        - 8.8.8.8
      imagePullSecrets:
      - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
spec:
  selector:
    app: ${NAME}
  ports:
  - name: ssh
    protocol: TCP
    port: 22
    targetPort: 22
    nodePort: ${PORT}
  type: NodePort
EOF
}

# ---- Dispatch & write -------------------------------------------------------
generate() {
  case "$MANIFEST_TYPE" in
    pv)          generate_pv ;;
    pvc)         generate_pvc ;;
    deploy)
      if [ "$RESOURCE" = "gpu" ]; then
        generate_gpu_deployment
      else
        generate_cpu_deployment
      fi
      ;;
  esac
}


generate > "${OUTPUT_PATH}"

# For deploy, return the chosen NodePort on stdout so callers can capture it
if [ "$MANIFEST_TYPE" = "deploy" ]; then
  echo "${PORT}"
fi