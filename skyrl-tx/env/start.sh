#!/bin/bash
# SkyRL-TX Startup Script
# Usage: chmod +x start.sh && ./start.sh [BASE_MODEL] [DATA_DIR]
#
# This script handles everything:
# - Installs Docker Compose if missing
# - Sets up docker permissions
# - Creates data directories
# - Starts all services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Defaults
export BASE_MODEL="${1:-Qwen/Qwen3-0.6B}"

# Auto-detect best data directory
if [ -z "$2" ]; then
    if [ -d "/eph/nvme0" ]; then
        export DATA_DIR="/eph/nvme0/skyrl-data"
        log_info "Detected Azure NVMe storage, using $DATA_DIR"
    elif [ -d "/mnt" ] && [ "$(df /mnt --output=avail | tail -1)" -gt 100000000 ]; then
        export DATA_DIR="/mnt/skyrl-data"
        log_info "Using /mnt storage: $DATA_DIR"
    else
        export DATA_DIR="$HOME/skyrl-data"
        log_info "Using home directory: $DATA_DIR"
    fi
else
    export DATA_DIR="$2"
fi

echo ""
echo "================================================"
echo "  SkyRL-TX Startup"
echo "================================================"
echo "  BASE_MODEL: $BASE_MODEL"
echo "  DATA_DIR:   $DATA_DIR"
echo "================================================"
echo ""

# ============================================
# Step 1: Check/Install Docker
# ============================================
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# ============================================
# Step 2: Check/Fix Docker Permissions
# ============================================
if ! docker info &> /dev/null; then
    log_warn "Docker permission issue detected"
    
    # Check if user is in docker group
    if ! groups | grep -q docker; then
        log_info "Adding $USER to docker group..."
        sudo usermod -aG docker $USER
        log_info "Added to docker group. Trying newgrp..."
        
        # Re-exec this script with new group
        exec sg docker "$0 $*"
    else
        log_warn "Already in docker group but still no access. Using sudo for docker commands."
        SUDO_PREFIX="sudo"
    fi
else
    SUDO_PREFIX=""
fi

# ============================================
# Step 3: Check/Install Docker Compose
# ============================================
install_docker_compose() {
    log_info "Installing Docker Compose V2..."
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    log_info "Docker Compose V2 installed successfully"
}

# Try docker compose (V2)
if $SUDO_PREFIX docker compose version &> /dev/null; then
    COMPOSE_CMD="$SUDO_PREFIX docker compose"
    log_info "Using Docker Compose V2"
# Try docker-compose (V1)
elif command -v docker-compose &> /dev/null && $SUDO_PREFIX docker-compose version &> /dev/null; then
    COMPOSE_CMD="$SUDO_PREFIX docker-compose"
    log_info "Using Docker Compose V1"
else
    log_warn "Docker Compose not found. Installing..."
    install_docker_compose
    COMPOSE_CMD="$SUDO_PREFIX docker compose"
fi

# ============================================
# Step 4: Check/Configure NVIDIA Docker Runtime
# ============================================
restart_docker() {
    log_info "Restarting Docker daemon..."
    sudo systemctl stop docker.socket docker.service 2>/dev/null || true
    sleep 2
    sudo systemctl start docker.socket docker.service
    sleep 5  # Wait for docker to fully start
    
    # Wait until docker is responsive
    for i in {1..10}; do
        if docker info &> /dev/null || sudo docker info &> /dev/null; then
            log_info "Docker daemon ready"
            return 0
        fi
        log_info "Waiting for Docker daemon... ($i/10)"
        sleep 2
    done
}

configure_nvidia_runtime() {
    log_info "Configuring NVIDIA Docker runtime..."
    sudo nvidia-ctk runtime configure --runtime=docker
    log_info "NVIDIA Docker runtime configured (restart required)"
}

install_nvidia_toolkit() {
    log_info "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA repo
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) 2>/dev/null || distribution="ubuntu22.04"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    configure_nvidia_runtime
    
    log_info "NVIDIA Container Toolkit installed"
}

# Check if nvidia-container-toolkit is installed
NEED_DOCKER_RESTART=false
if ! dpkg -l | grep -q "nvidia-container-toolkit"; then
    log_warn "NVIDIA Container Toolkit not installed"
    install_nvidia_toolkit
    NEED_DOCKER_RESTART=true
fi

# Function to test GPU access
test_gpu_access() {
    # Try with a simple nvidia-smi command (no CUDA image needed)
    docker run --rm --gpus all ubuntu nvidia-smi &> /dev/null || \
    sudo docker run --rm --gpus all ubuntu nvidia-smi &> /dev/null
}

# Test GPU access first (no restart needed if it works)
if test_gpu_access; then
    log_info "GPU access verified ✓"
else
    log_warn "GPU access failed. Checking NVIDIA runtime configuration..."
    
    # Check if nvidia runtime is configured in daemon.json
    if ! grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null; then
        log_info "NVIDIA runtime not configured in Docker"
        configure_nvidia_runtime
        NEED_DOCKER_RESTART=true
    fi
    
    # Only restart if needed
    if [ "$NEED_DOCKER_RESTART" = true ]; then
        restart_docker
        
        # Update SUDO_PREFIX after docker restart
        if docker info &> /dev/null; then
            SUDO_PREFIX=""
        else
            SUDO_PREFIX="sudo"
        fi
    fi
    
    # Try again with retries
    GPU_OK=false
    for attempt in {1..3}; do
        log_info "Testing GPU access (attempt $attempt/3)..."
        if test_gpu_access; then
            GPU_OK=true
            break
        fi
        sleep 3
    done
    
    if [ "$GPU_OK" = false ]; then
        log_error "Still cannot access GPUs from Docker."
        log_info "Checking nvidia-smi directly..."
        nvidia-smi
        log_info ""
        log_info "Trying alternative: running with --runtime=nvidia flag..."
        
        # Try with explicit runtime flag
        if sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi &> /dev/null; then
            log_info "GPU works with --runtime=nvidia flag"
            # Add runtime flag to compose
            export DOCKER_DEFAULT_RUNTIME=nvidia
        else
            log_error "GPU access still failing. Checking Docker daemon config..."
            cat /etc/docker/daemon.json 2>/dev/null || echo "No daemon.json found"
            log_info ""
            log_info "Attempting manual fix..."
            
            # Manually create/fix daemon.json
            sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    },
    "default-runtime": "nvidia"
}
EOF
            # Restart docker again
            restart_docker
            
            # Final test
            if ! test_gpu_access; then
                log_error "All attempts failed. Debug info:"
                sudo docker info | grep -i runtime || true
                exit 1
            fi
        fi
    else
        log_info "GPU access verified ✓"
    fi
fi

# ============================================
# Step 5: Create Data Directories
# ============================================
if [ ! -d "$DATA_DIR" ]; then
    log_info "Creating data directory: $DATA_DIR"
    sudo mkdir -p "$DATA_DIR"
fi

# Create subdirectories and set permissions (777 so container user can write)
mkdir -p "$DATA_DIR"/{checkpoints,lora_models,tinker_db,huggingface,ray,tmp,uv_cache} 2>/dev/null || \
sudo mkdir -p "$DATA_DIR"/{checkpoints,lora_models,tinker_db,huggingface,ray,tmp,uv_cache}

# Make writable by anyone (container runs as different user)
sudo chmod -R 777 "$DATA_DIR"
log_info "Data directories ready ✓"

# ============================================
# Step 6: Start Services
# ============================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

log_info "Building and starting services..."

# Always use sudo with explicit env vars to ensure they're passed correctly
sudo DATA_DIR="$DATA_DIR" BASE_MODEL="$BASE_MODEL" docker compose up --build -d

echo ""
echo "================================================"
echo -e "  ${GREEN}Services Started!${NC}"
echo "================================================"
echo "  vLLM:      http://localhost:7999 (GPUs 4-7)"
echo "  SkyRL-TX:  http://localhost:8000 (GPUs 0-3)"
echo ""
echo "  View logs:"
echo "    sudo docker compose logs -f          # All services"
echo "    sudo docker compose logs -f vllm     # vLLM only"
echo "    sudo docker compose logs -f skyrl-tx # SkyRL-TX only"
echo ""
echo "  Stop:      sudo docker compose down"
echo "  Restart:   sudo docker compose restart"
echo "================================================"
echo ""
log_info "Waiting for vLLM to be healthy (this may take a few minutes)..."
echo "  Run 'sudo docker compose logs -f vllm' to watch vLLM startup"
