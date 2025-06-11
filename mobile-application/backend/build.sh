#!/bin/bash
set -o errexit

# Install system dependencies
apt-get update
apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \          # Required for PaddlePaddle
    libsm6 \            # OpenCV dependency
    libxext6 \          # OpenCV dependency
    libxrender-dev      # OpenCV dependency

# Install Python dependencies
pip install -r requirements.txt