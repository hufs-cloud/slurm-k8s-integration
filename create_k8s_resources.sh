#!/bin/bash
# create_k8s_resources.sh

set -e

JOB_SPEC_FILE=$1

if [ -z "$JOB_SPEC_FILE" ]; then
    echo "Error: Job spec file path required"
    exit 1
fi

if [ ! -f "$JOB_SPEC_FILE" ]; then
    echo "Error: File $JOB_SPEC_FILE not found"
    exit 1
fi

# YAML에서 값 추출
USER_TYPE=$(yq eval '.user.type' "$JOB_SPEC_FILE")
USER_ID=$(yq eval '.user.id' "$JOB_SPEC_FILE")
USER_INDEX=$(yq eval '.user.index' "$JOB_SPEC_FILE")
JOB_NAME=$(yq eval '.job.name' "$JOB_SPEC_FILE")
WORKSPACE=$(yq eval '.paths.workspace' "$JOB_SPEC_FILE")
SCRIPT_PATH=$(yq eval '.execution.script' "$JOB_SPEC_FILE")
GPU=$(yq eval '.resource.gpu' "$JOB_SPEC_FILE")
CPU=$(yq eval '.resource.cpu' "$JOB_SPEC_FILE")
MEM=$(yq eval '.resource.mem' "$JOB_SPEC_FILE")
SCHEDULING_RESOURCE=$(yq eval '.scheduling.resource' "$JOB_SPEC_FILE")
SCHEDULING_NUM=$(yq eval '.scheduling.num' "$JOB_SPEC_FILE")

# Slurm 환경변수에서 노드 이름 가져오기
NODE_NAME=${SLURM_NODELIST:-"gpu-node1"}

TEMP_DIR="/tmp/k8s-manifests-${JOB_NAME}"
mkdir -p "$TEMP_DIR"

echo "=========================================="
echo "Creating Kubernetes resources"
echo "=========================================="
echo "Job Name: $JOB_NAME"
echo "User: $USER_TYPE-$USER_ID (index: $USER_INDEX)"
echo "Workspace: $WORKSPACE"
echo "Node: $NODE_NAME"
echo "Resources: GPU=$GPU, CPU=$CPU, MEM=$MEM"
echo "Scheduling: resource=$SCHEDULING_RESOURCE, num=$SCHEDULING_NUM"
echo "=========================================="

# PV 생성 - job별로 고유
cat > "$TEMP_DIR/pv.yaml" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${JOB_NAME}
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: nas-hub.local
    path: ${WORKSPACE}
  persistentVolumeReclaimPolicy: Retain
EOF

# PVC 생성 - job별로 고유
cat > "$TEMP_DIR/pvc.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${JOB_NAME}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
  volumeName: pv-${JOB_NAME}
EOF

# Pod 생성
cat > "$TEMP_DIR/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${JOB_NAME}
  labels:
    app: slurm-job
    user: ${USER_TYPE}-${USER_ID}
    job: ${JOB_NAME}
spec:
  nodeName: ${NODE_NAME}
  restartPolicy: Never
  containers:
  - name: job-container
    image: nas-hub.local:5407/${JOB_NAME}:latest
    command: ["/bin/bash"]
    args: ["/workspace/${SCRIPT_PATH}"]
    resources:
      requests:
        memory: "${MEM}"
        cpu: "${CPU}"
        nvidia.com/gpu: "${GPU}"
      limits:
        memory: "${MEM}"
        cpu: "${CPU}"
        nvidia.com/gpu: "${GPU}"
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: pvc-${JOB_NAME}
EOF

# Kubernetes 리소스 생성
echo ""
echo "Step 1: Creating PersistentVolume..."
kubectl apply -f "$TEMP_DIR/pv.yaml"

echo ""
echo "Step 2: Creating PersistentVolumeClaim..."
kubectl apply -f "$TEMP_DIR/pvc.yaml"

echo ""
echo "Step 3: Waiting for PVC to be bound..."
if kubectl wait --for=condition=bound pvc/pvc-${JOB_NAME} --timeout=30s; then
    echo "PVC successfully bound"
else
    echo "Warning: PVC binding timeout, but continuing..."
fi

echo ""
echo "Step 4: Creating Pod..."
kubectl apply -f "$TEMP_DIR/pod.yaml"

echo ""
echo "=========================================="
echo "Resources created successfully"
echo "=========================================="
echo "Pod name: ${JOB_NAME}"
echo "Manifests saved in: $TEMP_DIR"
echo ""
echo "Pod status:"
kubectl get pod ${JOB_NAME}

exit 0