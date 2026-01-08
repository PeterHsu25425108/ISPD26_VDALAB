#!/bin/bash
set -e

echo ">>> Starting Xplace dependency installation..."

# 1. Install System Dependencies (Root required)
# Installs nvcc (via nvidia-cuda-toolkit), Boost, Cairo, CMake
echo ">>> Installing system libraries..."
apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    pkg-config \
    nvidia-cuda-toolkit \
    libcairo2-dev \
    libboost-all-dev \
    tcl-dev tk-dev \
    libglib2.0-dev

# 2. Configure Conda Environment
echo ">>> Configuring Conda environment..."
source /opt/miniconda3/etc/profile.d/conda.sh

if conda info --envs | grep -q "xplace_env"; then
    echo "Environment 'xplace_env' already exists. Skipping creation."
else
    echo "Creating 'xplace_env' with Python 3.11..."
    # FIX IS HERE: Added --override-channels to strictly ignore the 'defaults' channel
    conda create -n xplace_env -c conda-forge --override-channels python=3.11 -y
fi

# 3. Install Python Dependencies
echo ">>> Installing Python libraries..."
conda activate xplace_env

# Install PyTorch (CUDA 12.1 compatible)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install other python requirements
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    echo "requirements.txt not found, installing manual dependencies..."
    pip install cmake numpy pyyaml cairocffi matplotlib numba pandas scipy
fi

echo ">>> Setup Complete!"
echo "Run 'source /opt/miniconda3/etc/profile.d/conda.sh && conda activate xplace_env' before building."