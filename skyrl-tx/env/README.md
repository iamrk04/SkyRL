# SkyRL-TX Docker Environment

Docker configuration for running SkyRL-TX with the SkyRL-Train backend.

## Quick Start

### One-Command Startup

```bash
cd ~/SkyRL/skyrl-tx/env
chmod +x start.sh
./start.sh
```

The script handles everything automatically (docker permissions, compose installation, GPU setup, data directories).

### Manual Startup (with sudo)

If you need sudo for docker, pass environment variables explicitly:

```bash
cd ~/SkyRL/skyrl-tx/env

# Start both services
sudo DATA_DIR=/eph/nvme0/skyrl-data BASE_MODEL=Qwen/Qwen3-0.6B docker compose up -d

# Or rebuild and start (after code changes)
sudo DATA_DIR=/eph/nvme0/skyrl-data BASE_MODEL=Qwen/Qwen3-0.6B docker compose up --build -d
```

## Checking Status & Logs

### Check Running Containers

```bash
# List running containers
sudo docker ps

# With nice formatting
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output when both services are running:
```
NAMES              STATUS                   PORTS
env-vllm-1         Up X minutes (healthy)   0.0.0.0:7999->8000/tcp
env-skyrl-tx-1     Up X minutes             0.0.0.0:8000->8000/tcp
```

### View Logs

```bash
# All services (interleaved)
sudo docker compose logs -f

# vLLM only (in Terminal 1)
sudo docker compose logs -f vllm

# SkyRL-TX only (in Terminal 2)
sudo docker compose logs -f skyrl-tx

# Last 100 lines without following
sudo docker compose logs --tail 100 skyrl-tx
```

### Service Health Checks

```bash
# Check vLLM health
curl http://localhost:7999/health

# Check SkyRL-TX health  
curl http://localhost:8000/health
```

## Stop & Restart

```bash
cd ~/SkyRL/skyrl-tx/env

# Stop all services
sudo docker compose down

# Restart a single service
sudo docker compose restart skyrl-tx

# Rebuild and restart (after code changes)
sudo DATA_DIR=/eph/nvme0/skyrl-data BASE_MODEL=Qwen/Qwen3-0.6B docker compose up --build -d
```

## Services

| Service | URL | GPUs | Purpose |
|---------|-----|------|---------|
| vLLM | http://localhost:7999 | 4-7 | Inference server |
| SkyRL-TX | http://localhost:8000 | 0-3 | Training server |

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_MODEL` | HuggingFace model name | `Qwen/Qwen3-0.6B` |
| `MAX_LORA_RANK` | Maximum LoRA rank for vLLM | `32` |
| `DATA_DIR` | Host directory for persistent data | `./data` |

### GPU Allocation

Default allocation (8 GPU setup):
- **GPUs 0-3**: SkyRL-TX (training)
- **GPUs 4-7**: vLLM (inference)

Edit `device_ids` in `docker-compose.yml` to change allocation.

## Directory Structure

```
$DATA_DIR/
├── checkpoints/     # Training checkpoints
├── lora_models/     # LoRA weights (shared with vLLM)
├── tinker_db/       # SQLite database
├── huggingface/     # HuggingFace cache
├── ray/             # Ray temporary files
└── tmp/             # Temporary files
```

## Prerequisites

### Data Directory Setup (Azure VMs)

Use the fast ephemeral NVMe storage:

```bash
# Check available storage
df -h

# Create data directory
sudo mkdir -p /eph/nvme0/skyrl-data
sudo chmod -R 777 /eph/nvme0/skyrl-data
mkdir -p /eph/nvme0/skyrl-data/{checkpoints,lora_models,tinker_db,huggingface,ray,tmp}
```

> ⚠️ **Warning**: Ephemeral storage (`/eph/nvme0`, `/mnt`) is wiped when VM is deallocated/resized. Copy important results to persistent storage.

### Azure VM Storage Options

| Mount | Size | Speed | Persistence | Use For |
|-------|------|-------|-------------|---------|
| `/` | ~124G | Slow | ✅ Persistent | OS, code |
| `/mnt` | ~1TB | Fast | ❌ Temp | Temp cache |
| `/eph/nvme0` | ~28TB | Very fast | ❌ Temp | Training data, checkpoints |

## Troubleshooting

### Permission denied errors

```bash
# Fix data directory permissions
sudo chmod -R 777 /eph/nvme0/skyrl-data
```

### Container keeps restarting

```bash
# Check logs for errors
sudo docker compose logs skyrl-tx

# Check if exited
sudo docker ps -a
```

### vLLM fails to start

- Check GPU memory: `nvidia-smi`
- Try smaller model: `BASE_MODEL=Qwen/Qwen3-0.6B`
- Check logs: `sudo docker compose logs vllm`

### Environment variables not passed with sudo

Always pass env vars explicitly with sudo:
```bash
sudo DATA_DIR=/eph/nvme0/skyrl-data BASE_MODEL=Qwen/Qwen3-0.6B docker compose up -d
```

### Docker permission denied

```bash
sudo usermod -aG docker $USER
newgrp docker  # Or log out and back in
```

### Install Docker Compose V2

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```
