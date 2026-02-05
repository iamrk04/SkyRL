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

# Build venv with all dependencies
RUN uv sync --extra gpu --extra tinker --extra skyrl_train

# Install uv wrapper that makes 'uv run' use the pre-built venv Python directly
# This prevents Ray from detecting uv and creating new venvs per worker
COPY skyrl-tx/env/uv-wrapper.sh /usr/local/bin/uv
RUN chmod +x /usr/local/bin/uv

# Create mount points for runtime data
RUN sudo mkdir -p /data && sudo chown -R $(whoami) /data

# Environment variables
ENV UV_CACHE_DIR=/home/ray/.cache/uv \
    HF_HOME=/data/huggingface

# Start bash by default - users start services manually
CMD ["bash"]
