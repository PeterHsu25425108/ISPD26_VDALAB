#!/bin/bash
# setup.sh - Install ML dependencies for OpenROAD + RL project
# Usage: bash setup.sh

set -e

echo "======================================================================"
echo "  Installing ML/RL Dependencies for System Python 3.12"
echo "======================================================================"

# Force deactivate conda
source /opt/miniconda3/etc/profile.d/conda.sh
conda deactivate 2>/dev/null || true

# Explicitly unset conda environment variables
unset CONDA_DEFAULT_ENV
unset CONDA_PREFIX
unset CONDA_PYTHON_EXE

# Use absolute path to system Python
SYSTEM_PYTHON="/usr/bin/python3"
SYSTEM_PIP="/usr/bin/pip3"

# Verify we're using the correct Python
PYTHON_VERSION=$($SYSTEM_PYTHON --version 2>&1 | awk '{print $2}')
echo "Using:  $SYSTEM_PYTHON"
echo "Python version: $PYTHON_VERSION"

if [[ !  "$PYTHON_VERSION" =~ ^3\.12\.  ]]; then
    echo "ERROR: Expected Python 3.12.x, got $PYTHON_VERSION"
    exit 1
fi

echo ""
echo "Step 1/4: Installing PyTorch with CUDA 12.1 support..."
# Use latest compatible version (2.5.1 is the latest for cu121)
$SYSTEM_PIP install --break-system-packages \
    torch==2.5.1+cu121 \
    torchvision==0.20.1+cu121 \
    torchaudio==2.5.1+cu121 \
    --index-url https://download.pytorch.org/whl/cu121 \
    --no-cache-dir

echo ""
echo "Step 2/4: Installing PyTorch Geometric and extensions..."
$SYSTEM_PIP install --break-system-packages \
    torch-geometric

# Install PyG extensions - using find-links for latest torch version
echo "Installing PyG extensions (this may take a while)..."
$SYSTEM_PIP install --break-system-packages \
    pyg-lib \
    torch-scatter \
    torch-sparse \
    torch-cluster \
    torch-spline-conv \
    -f https://data.pyg.org/whl/torch-2.5.0+cu121.html \
    --no-cache-dir

echo ""
echo "Step 3/4: Installing RL frameworks..."
$SYSTEM_PIP install --break-system-packages \
    torchrl \
    tensordict \
    gymnasium

echo ""
echo "Step 4/4: Installing utility libraries..."
$SYSTEM_PIP install --break-system-packages \
    numpy \
    pandas \
    matplotlib \
    seaborn \
    scikit-learn \
    tensorboard

echo ""
echo "======================================================================"
echo "  Verification"
echo "======================================================================"

# Verify installations using system Python
$SYSTEM_PYTHON << 'EOF'
import sys
print(f"Python:  {sys.version}")
print(f"Python executable: {sys.executable}")

try:
    import torch
    print(f"✓ PyTorch:  {torch.__version__}")
    print(f"  CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"  CUDA version: {torch.version.cuda}")
        print(f"  GPU count: {torch.cuda.device_count()}")
        for i in range(torch.cuda. device_count()):
            print(f"  GPU {i}: {torch.cuda.get_device_name(i)}")
except ImportError as e:
    print(f"✗ PyTorch:  {e}")
    sys.exit(1)

try:
    import torch_geometric
    print(f"✓ PyTorch Geometric: {torch_geometric.__version__}")
except ImportError as e:
    print(f"✗ PyTorch Geometric: {e}")
    sys.exit(1)

try:
    import torchrl
    print(f"✓ TorchRL: {torchrl.__version__}")
except ImportError as e:
    print(f"✗ TorchRL: {e}")
    sys.exit(1)

try:
    import gymnasium
    print(f"✓ Gymnasium: {gymnasium.__version__}")
except ImportError as e:
    print(f"✗ Gymnasium: {e}")
    sys.exit(1)

try:
    import numpy as np
    print(f"✓ NumPy: {np.__version__}")
except ImportError as e:
    print(f"✗ NumPy:  {e}")
    sys.exit(1)

try:
    import pandas as pd
    print(f"✓ Pandas:  {pd.__version__}")
except ImportError as e:
    print(f"✗ Pandas: {e}")
    sys.exit(1)

print("\n✓ All dependencies installed successfully!")
EOF

echo ""
echo "======================================================================"
echo "  Testing OpenROAD Integration"
echo "======================================================================"

# Test OpenROAD + PyTorch integration
openroad -python << 'EOF'
import sys
print(f"OpenROAD Python: {sys.version}")
print(f"OpenROAD Python executable: {sys.executable}")

try:
    import openroad
    import odb
    print("✓ OpenROAD API available")
except ImportError as e: 
    print(f"✗ OpenROAD API: {e}")
    sys.exit(1)

try:
    import torch
    print(f"✓ PyTorch available in openroad -python:  {torch.__version__}")
except ImportError as e:
    print(f"✗ PyTorch in OpenROAD: {e}")
    sys.exit(1)

try:
    import torch_geometric
    print(f"✓ PyG available in openroad -python")
except ImportError as e:  
    print(f"✗ PyG in OpenROAD: {e}")
    sys.exit(1)

try:
    import torchrl
    print(f"✓ TorchRL available in openroad -python")
except ImportError as e:  
    print(f"✗ TorchRL in OpenROAD: {e}")
    sys.exit(1)

print("\n✓ OpenROAD + ML libraries integration confirmed!")
EOF

echo ""
echo "======================================================================"
echo "  Setup Complete!"
echo "======================================================================"
echo ""
echo "Installed versions:"
$SYSTEM_PYTHON -c "import torch; print(f'  PyTorch: {torch.__version__}')"
$SYSTEM_PYTHON -c "import torch_geometric; print(f'  PyG: {torch_geometric.__version__}')"
$SYSTEM_PYTHON -c "import torchrl; print(f'  TorchRL: {torchrl.__version__}')"
echo ""
echo "Usage:"
echo "  openroad -python your_ml_script.py"
echo ""
umask 000