#!/bin/bash

# this script is intended to be run on the RunPod machine of the type:
#     RunPod Pytorch 2.2.0
#     runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04
#
# You must make sure that in the secrets you set your HuggingFace token in the "key"/variable HF_TOKEN

# get the models:
echo "---------- get the models"
mkdir -p /workspace/models
cd /workspace/models
if [ ! -f "t5xxl_fp16.safetensors" ]; then
    wget --show-progress https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors?download=true -O t5xxl_fp16.safetensors
fi
if [ ! -f "clip_l.safetensors" ]; then
    wget --show-progress https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true -O clip_l.safetensors
fi
if [ ! -f "ae.safetensors" ]; then
    wget --show-progress https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors?download=true -O ae.safetensors
fi
if [ ! -f "flux1-dev.safetensors" ]; then
    wget --header="Authorization: Bearer $HF_TOKEN" https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors?download=true -O flux1-dev.safetensors
fi
cd ..

# get kohya in the branch "sd3-flux.1" to train Flux.1:
echo "---------- get kohya"
cd /workspace
apt-get update --yes && apt-get install --yes python3-venv python3-tk vim libcudnn8 libcudnn8-dev
# TODO: is this sufficient?
#apt-get update --yes && apt-get install --yes python3-venv python3-tk vim libcudnn8
apt-get -y install cudnn-cuda-12 libnccl2 libnccl-dev

# accelerate config
wget https://github.com/StableLlama/kohya_on_RunPod/raw/main/accelerate/default_config.yaml -O /root/.cache/huggingface/accelerate/default_config.yaml

if [ ! -f "kohya_ss" ]; then
    git clone --recursive https://github.com/bmaltais/kohya_ss.git
    cd /workspace/kohya_ss
    git checkout sd3-flux.1
    git pull --recurse-submodules
fi
cd /workspace/kohya_ss

echo "---------- prepare setup"
python -m pip install --upgrade pip
pip install tensorflow[and-cuda]>=2.15.0 --extra-index-url https://pypi.nvidia.com
CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))
TENSORRT_LIBS_PATH=$(dirname $(python -c "import tensorrt_libs;print(tensorrt_libs.__file__)"))
export LD_LIBRARY_PATH=$TENSORRT_LIBS_PATH:$CUDNN_PATH/lib:$LD_LIBRARY_PATH

echo "---------- setup kohya"
chmod +x ./setup.sh
./setup.sh -n -p -r -s -u

# update the python packages
pip install torch==2.4.0+cu121 torchvision==0.19.0+cu121 xformers==0.0.27.post2 torchaudio --index-url https://download.pytorch.org/whl/cu121

echo "---------- start kohya"
echo "To start kohya-ss you need to run in the directory \"/workspace/kohya_ss\":"
echo ""
echo "./gui.sh --server_port 7860 --listen=0.0.0.0 --headless"

