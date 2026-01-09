#!/bin/bash

# --- Configuration ---
CONDA_PATH="/opt/miniconda3"
ENV_NAME="xplace_env"

# Ensure the script exits if any command fails
set -e

echo ">>> Starting Xplace Setup & Build..."

# 1. Activate Conda Environment
if [ -f "$CONDA_PATH/etc/profile.d/conda.sh" ]; then
    source "$CONDA_PATH/etc/profile.d/conda.sh"
else
    echo "Error: Conda not found at $CONDA_PATH"
    exit 1
fi

echo ">>> Activating environment: $ENV_NAME"
conda activate $ENV_NAME

# 2. Clean Up & Dependency Install
echo ">>> Cleaning up conflicting libraries..."
pip uninstall -y nvidia-nccl-cu11 nvidia-nccl-cu12 torchvision torchaudio

echo ">>> Installing Dependencies..."
# Install Torch, Pybind, pinned Numpy, and the visualization tools (Seaborn/Matplotlib)
pip install "numpy<2.0" \
    torch==2.0.0+cu118 \
    pybind11 \
    seaborn \
    matplotlib \
    pandas \
    scipy \
    --index-url https://download.pytorch.org/whl/cu118 \
    --force-reinstall \
    --no-cache-dir

# 3. Patch PyTorch Headers (The GCC 12 Fix)
echo ">>> Patching PyTorch headers for GCC 12 compatibility..."
NEW_PYBIND=$(python3 -c "import pybind11; print(pybind11.get_include())")
TORCH_INC=$(python3 -c "from torch.utils import cpp_extension; print(cpp_extension.include_paths()[0])")
BROKEN_PYBIND="$TORCH_INC/pybind11"

# Verify we found the folders
if [ ! -d "$NEW_PYBIND" ] || [ ! -d "$TORCH_INC" ]; then
    echo "CRITICAL ERROR: Could not locate PyBind11 or Torch headers."
    exit 1
fi

# Perform the swap
if [ -d "$BROKEN_PYBIND" ]; then
    if [ ! -d "${BROKEN_PYBIND}_backup" ]; then
        mv "$BROKEN_PYBIND" "${BROKEN_PYBIND}_backup"
        echo "Backed up old PyTorch headers."
    else
        rm -rf "$BROKEN_PYBIND"
        echo "Removed existing broken headers."
    fi
    cp -r "$NEW_PYBIND/pybind11" "$TORCH_INC/"
    echo "Success: PyTorch headers patched with PyBind11 v2.14."
else
    echo "Warning: Target folder $BROKEN_PYBIND not found. Assuming headers are already patched."
fi

# 4. Set Compiler Environment
echo ">>> Setting compiler to GCC 12..."
export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12
export CUDAHOSTCXX=/usr/bin/g++-12
