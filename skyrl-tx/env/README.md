# SkyRL-TX Docker Environment

Docker configuration for running SkyRL-TX with the SkyRL-Train backend.

## Quick Start

### Option 1: Docker Compose (Recommended)

Runs both SkyRL-TX (training) and vLLM (inference) together:

```bash
cd skyrl-tx/env

# Set the base model
export BASE_MODEL=mistralai/Mistral-7B-v0.1

# Set data directory (for checkpoints, models, etc.)
export DATA_DIR=/path/to/data

# Start services
docker compose up -d

# View logs
docker compose logs -f
```

### Option 2: Build and Run Separately

```bash
# Set data directory and base model
export DATA_DIR=/path/to/data
export BASE_MODEL=mistralai/Mistral-7B-v0.1

# Build the SkyRL-TX image
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

### vLLM fails to start
- Ensure you have enough GPU memory
- Check `docker compose logs vllm` for errors
- Try a smaller model for testing: `BASE_MODEL=Qwen/Qwen3-0.6B`

### LoRA rank mismatch
- Ensure `MAX_LORA_RANK` matches your training configuration
- Default LoRA rank in SkyRL-TX is 32

### Permission issues
- Ensure `DATA_DIR` is writable by Docker
- Run: `chmod -R 777 /path/to/data`
