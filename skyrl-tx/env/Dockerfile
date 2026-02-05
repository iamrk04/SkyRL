# SkyRL-TX Dockerfile
# Supports both JAX and SkyRL-Train backends

FROM anyscale/ray:2.51.1-slim-py312-cu128

# Install system dependencies
RUN sudo apt-get update -y && sudo apt-get install -y \
    git curl wget build-essential \
    && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# Install uv package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/ray/.local/bin:$PATH"

# Clone and install SkyRL-TX
WORKDIR /app
RUN git clone -b rk/fix https://github.com/iamrk04/SkyRL.git .
WORKDIR /app/skyrl-tx
RUN uv sync --extra gpu --extra tinker --extra skyrl_train

# Create directories for runtime data (needs sudo in ray image)
RUN sudo mkdir -p /data/{checkpoints,lora_models,tinker_db,ray,huggingface,tmp} && \
    sudo chown -R ray:ray /data

# Environment variables
ENV RAY_TMPDIR=/data/ray \
    UV_CACHE_DIR=/data/uv_cache \
    HF_HOME=/data/huggingface \
    TMPDIR=/data/tmp

# Start bash by default - users start services manually
CMD ["bash"]
