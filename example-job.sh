#!/bin/bash
#SBATCH --job-name=pytorch-training
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:2
#SBATCH --time=04:00:00
#SBATCH --output=/mnt/nas/results/%j.out
#SBATCH --error=/mnt/nas/results/%j.err

# K8s 관련 메타데이터
#K8S_IMAGE=nas-hub.local:5407/pytorch:2.0-cuda11.8
#K8S_WORKDIR=/workspace
#K8S_SCRIPT=/mnt/nas/scripts/train_model.py

# 환경 설정
export CUDA_VISIBLE_DEVICES=0,1
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# 작업 정보 출력
echo "=========================================="
echo "SLURM Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo "=========================================="

# GPU 정보 확인
nvidia-smi

# Python 환경 확인
python --version
pip list | grep torch

# 메인 학습 스크립트 실행
python /mnt/nas/scripts/train_model.py \
    --data-dir /mnt/nas/datasets/imagenet \
    --output-dir /results \
    --epochs 100 \
    --batch-size 256 \
    --learning-rate 0.001 \
    --num-workers $SLURM_CPUS_PER_TASK

# 학습 완료 후 체크포인트를 NAS로 복사
echo "Copying results to NAS..."
cp -r /results/* /mnt/nas/results/$SLURM_JOB_ID/

echo "=========================================="
echo "Job completed at: $(date)"
echo "=========================================="
