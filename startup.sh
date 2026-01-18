#!/usr/bin/env bash

set -euo pipefail

# =====================
# Simplified ChartSpark Env Setup Script
# =====================

# Colors
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname \"${BASH_SOURCE[0]}\")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"

# Defaults
ENV_NAME="spark"
PYTHON_VERSION="3.9"
NODE_VERSION="v18.20.8"

log() { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1" >&2; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Missing required command: $1"; exit 1
    fi
}

install_miniconda_if_needed() {
    if command -v conda >/dev/null 2>&1; then
        info "conda found; skipping Miniconda installation"
        return
    fi

    local arch="$(uname -m)"
    local installer="Miniconda3-latest-Linux-${arch}.sh"
    local url="https://repo.anaconda.com/miniconda/${installer}"
    local tmp_installer="${TMPDIR:-/tmp}/${installer}"

    info "Downloading Miniconda installer..."
    curl -fsSL "$url" -o "$tmp_installer"
    chmod +x "$tmp_installer"

    local target="$HOME/miniconda3"
    info "Installing Miniconda to $target ..."
    bash "$tmp_installer" -b -p "$target"

    source "$target/etc/profile.d/conda.sh"
    "$target/bin/conda" init bash
    log "Miniconda installed"
}

create_conda_env() {
    if conda env list | grep -q "$ENV_NAME"; then
        info "Conda env '$ENV_NAME' already exists"
    else
        info "Creating conda env '$ENV_NAME' with Python $PYTHON_VERSION..."
        conda create -y -n "$ENV_NAME" "python=$PYTHON_VERSION"
        log "Conda env '$ENV_NAME' created"
    fi

    source activate "$ENV_NAME"
    info "Activated conda environment: $ENV_NAME"
}

pip_install_requirements() {
    if [[ -f "$WORKSPACE_DIR/requirements.txt" ]]; then
        info "Installing Python dependencies..."
        pip install --upgrade pip
        pip install -r "$WORKSPACE_DIR/requirements.txt"
        log "Python dependencies installed"
    else
        warn "requirements.txt not found; skipping Python dependencies installation"
    fi
}

install_node_and_dependencies() {
    if ! command -v nvm >/dev/null 2>&1; then
        info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    fi

    info "Installing Node.js version $NODE_VERSION..."
    nvm install "$NODE_VERSION"
    nvm use "$NODE_VERSION"
    log "Node.js version: $(node -v), npm: $(npm -v)"

    if [[ -d "$WORKSPACE_DIR/frontend" ]]; then
        info "Installing frontend dependencies..."
        pushd "$WORKSPACE_DIR/frontend" >/dev/null
        npm install
        popd >/dev/null
        log "Frontend dependencies installed"
    else
        warn "frontend/ directory not found; skipping frontend dependencies installation"
    fi
}

main() {
    info "Starting environment setup..."

    install_miniconda_if_needed
    create_conda_env
    pip_install_requirements
    install_node_and_dependencies

    log "Environment setup complete"
    echo -e "${BLUE}Next steps:${NC}"
    echo "  - Activate env: conda activate $ENV_NAME"
    echo "  - Run backend: python chartSpeak.py"
    echo "  - Run frontend dev: cd frontend && npm run dev"
}

main "$@"

