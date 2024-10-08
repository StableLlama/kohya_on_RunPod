#!/bin/bash

# this script is intended to be run on the RunPod machine of the type:
#     RunPod Pytorch 2.2.0
#     runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04
#
# You must make sure that in the secrets you set your HuggingFace token in the "key"/variable HF_TOKEN

# get the models:
echo "---------- get the models"
if [ -z "${HF_TOKEN}" ]; then
    echo "WARNING!!! The environment variable 'HF_TOKEN' is empty."
    echo "WARNING!!! You will most likely NOT be able to download Flux.1[dev]!"
    echo "WARNING!!! You will must provide it yourself!"
fi
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
export DEBIAN_FRONTEND=noninteractive
# TODO: is this required? most likely not
# apt-get update --yes && apt-get install --yes python3-venv python3-tk vim libcudnn8 libcudnn8-dev
apt-get update --yes && apt-get -y install python3-venv python3-tk vim screen libcudnn8
# TODO: is this required?
# apt-get -y install cudnn-cuda-12 libnccl2
apt-get -y install cudnn-cuda-12 libnccl2 libnccl-dev

# accelerate config
if (( $RUNPOD_GPU_COUNT > 1 )); then
    echo "Download of multi GPU config for accelerate"
    wget https://github.com/StableLlama/kohya_on_RunPod/raw/main/accelerate/4gpu_config.yaml -O /root/.cache/huggingface/accelerate/default_config.yaml
    echo "Adapting accelerate for '$RUNPOD_GPU_COUNT' GPUs"
    sed -i "s/num_processes: 4/num_processes: $RUNPOD_GPU_COUNT/g" /root/.cache/huggingface/accelerate/default_config.yaml
else
    echo "Download of single GPU config for accelerate"
    wget https://github.com/StableLlama/kohya_on_RunPod/raw/main/accelerate/default_config.yaml -O /root/.cache/huggingface/accelerate/default_config.yaml
fi

if [ ! -f "kohya_ss" ]; then
    git clone --recursive https://github.com/bmaltais/kohya_ss.git
    cd /workspace/kohya_ss
    git checkout sd3-flux.1
    git pull --recurse-submodules
fi
cd /workspace/kohya_ss

echo "---------- prepare setup"
export PIP_ROOT_USER_ACTION=ignore
python -m pip install --upgrade pip
pip install tensorflow[and-cuda]>=2.15.0 --extra-index-url https://pypi.nvidia.com
CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))
TENSORRT_LIBS_PATH=$(dirname $(python -c "import tensorrt_libs;print(tensorrt_libs.__file__)"))
export LD_LIBRARY_PATH=$TENSORRT_LIBS_PATH:$CUDNN_PATH/lib:$LD_LIBRARY_PATH

echo "---------- setup kohya"
chmod +x ./setup.sh
./setup.sh -n -p -r -s -u

# update the python packages - not required anymore as kohya-ss was updated upstream
# pip install torch==2.4.0+cu121 torchvision==0.19.0+cu121 xformers==0.0.27.post2 torchaudio --index-url https://download.pytorch.org/whl/cu121

echo "---------- start kohya"
cd /workspace/kohya_ss
for MODEL in "/workspace/models/t5xxl_fp16.safetensors" "/workspace/models/clip_l.safetensors" "/workspace/models/ae.safetensors" "/workspace/models/flux1-dev.safetensors"; do
    if [ -f "${MODEL}" ]; then
        FILESIZE=$(stat -c%s "${MODEL}")
        echo "${MODEL} is available and has a size of ${FILESIZE} bytes"
    else
        echo "WARNING: ${MODEL} is NOT available"
    fi
done
echo ""
echo "To start kohya-ss you need to run in the directory \"/workspace/kohya_ss\":"
echo ""
echo "cd /workspace/kohya_ss"
echo "./gui.sh --server_port 7860 --listen=0.0.0.0 --headless"
echo ""
echo "When starting via a SSH connection you might prefer to start it with 'screen'"
echo "screen ./gui.sh --server_port 7860 --listen=0.0.0.0 --headless"


