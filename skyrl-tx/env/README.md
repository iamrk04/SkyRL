# SkyRL-TX Docker Environment

Docker configuration for running SkyRL-TX with the SkyRL-Train backend.

## Prerequisites

### Docker Permissions

Add yourself to the docker group to avoid using `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker  # Apply without logout (or log out and back in)
```

### Data Directory Setup

On Azure VMs, use the fast ephemeral NVMe storage:

```bash
# Check available storage
df -h

# Create data directory on NVMe (28TB, very fast, but wiped on VM restart)
sudo mkdir -p /eph/nvme0/skyrl-data
sudo chown $USER:$USER /eph/nvme0/skyrl-data

# Create subdirectories
mkdir -p /eph/nvme0/skyrl-data/{checkpoints,lora_models,tinker_db,huggingface,ray,tmp}

# Set DATA_DIR
export DATA_DIR=/eph/nvme0/skyrl-data
```

> ⚠️ **Warning**: Ephemeral storage is wiped when VM is deallocated/resized. Copy important results to persistent storage (Azure Blob, OS disk, etc.).

## Quick Start

### Option 1: Docker Compose (Recommended)

Runs both SkyRL-TX (training) and vLLM (inference) together:

```bash
cd skyrl-tx/env

# Set the base model
export BASE_MODEL=mistralai/Mistral-7B-v0.1

# Set data directory (for checkpoints, models, etc.)
export DATA_DIR=/eph/nvme0/skyrl-data

# Install Docker Compose V2 if not available
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Start services (use docker-compose if docker compose doesn't work)
docker compose up -d
# or: sudo docker-compose up -d

# View logs
docker compose logs -f
```

### Option 2: Build and Run Separately

```bash
# Set data directory and base model
export DATA_DIR=/eph/nvme0/skyrl-data
export BASE_MODEL=mistralai/Mistral-7B-v0.1

# Build the SkyRL-TX image (from repo root)
cd ~/SkyRL
docker build -t skyrl-tx -f skyrl-tx/env/Dockerfile .

# Terminal 1: Start vLLM server (GPUs 4-7)
docker run -it --gpus '"device=4,5,6,7"' -p 7999:8000 \
  -v $DATA_DIR/lora_models:/lora_models \
  -v $DATA_DIR/huggingface:/root/.cache/huggingface \
  -e VLLM_ALLOW_RUNTIME_LORA_UPDATING=True \
  -e VLLM_PLUGINS=lora_filesystem_resolver \
  -e VLLM_LORA_RESOLVER_CACHE_DIR=/lora_models \
  vllm/vllm-openai:v0.8.5 \
  --model $BASE_MODEL \
  --tensor-parallel-size 4 \
  --enable-lora \
  --max-lora-rank 32

# Terminal 2: Start SkyRL-TX (GPUs 0-3)
docker run -it --gpus '"device=0,1,2,3"' -p 8000:8000 \
  -v $DATA_DIR:/data \
  skyrl-tx \
  uv run --extra gpu --extra tinker --extra skyrl_train \
  -m tx.tinker.api \
  --base-model $BASE_MODEL \
  --backend skyrl_train \
  --database-url sqlite:////data/tinker_db/tinker.db \
  --checkpoints-base /data/checkpoints \
  --external-inference-url http://host.docker.internal:7999 \
  --external-inference-lora-base /data/lora_models
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_MODEL` | HuggingFace model name | `mistralai/Mistral-7B-v0.1` |
| `MAX_LORA_RANK` | Maximum LoRA rank for vLLM | `32` |
| `DATA_DIR` | Host directory for persistent data | `./data` |

### GPU Allocation

By default:
- **GPUs 0-3**: SkyRL-TX (training)
- **GPUs 4-7**: vLLM (inference)

Modify `NVIDIA_VISIBLE_DEVICES` in `docker-compose.yml` to change allocation.

## Directory Structure

```
/data/
├── checkpoints/     # Training checkpoints
├── lora_models/     # LoRA adapter weights (shared with vLLM)
├── tinker_db/       # SQLite database
├── huggingface/     # HuggingFace cache
├── ray/             # Ray temporary files
└── tmp/             # Temporary files
```

## Troubleshooting

### Docker permission denied
```bash
sudo usermod -aG docker $USER
newgrp docker  # Or log out and back in
```

### docker-compose not found
```bash
# Install Docker Compose V2 plugin
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

### vLLM fails to start
- Ensure you have enough GPU memory
- Check `docker compose logs vllm` for errors
- Try a smaller model for testing: `BASE_MODEL=Qwen/Qwen3-0.6B`

### LoRA rank mismatch
- Ensure `MAX_LORA_RANK` matches your training configuration
- Default LoRA rank in SkyRL-TX is 32

### Permission issues on DATA_DIR
```bash
sudo chown -R $USER:$USER $DATA_DIR
# Or if needed: chmod -R 777 $DATA_DIR
```

### Azure VM Storage Options

| Mount | Size | Speed | Persistence | Use For |
|-------|------|-------|-------------|---------|
| `/` | ~124G | Slow | ✅ Persistent | OS, code |
| `/mnt` | ~1TB | Fast | ❌ Temp | Temp cache |
| `/eph/nvme0` | ~28TB | Very fast | ❌ Temp | Training data, checkpoints |

Use `df -h` to check available storage on your VM.
