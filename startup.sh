#!/usr/bin/env bash

set -euo pipefail

# =====================
# ChartSpark Env Sync Script
# Installs Miniconda (if needed), creates conda env, installs Python deps,
# installs nvm/Node.js, runs frontend npm install, and optionally downloads models.
# =====================

# Colors
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"

# Defaults
ENV_NAME="chartspark"
PYTHON_VERSION="3.9"
NODE_VERSION="lts/*"  # or explicit e.g. 18, 20
CONDA_AUTO_INSTALL=true
DO_PIP_INSTALL=true
DO_NODE_INSTALL=true
DO_FRONTEND_INSTALL=true
DO_MODEL_DOWNLOAD=false
MODEL_DIR="$WORKSPACE_DIR/generation/ldm/models"
MODEL_URLS=()
MODELS_FILE=""
NON_INTERACTIVE=false

usage() {
	cat <<EOF
${BLUE}ChartSpark Environment Setup${NC}

Usage: ./startup.sh [options]

Options:
	--env-name <name>        Conda environment name (default: ${ENV_NAME})
	--python <version>       Python version for conda env (default: ${PYTHON_VERSION})
	--node <version|lts/*>   Node version for nvm (default: ${NODE_VERSION})
	--model-url <url>        Add a model URL to download (repeatable)
	--models-file <path>     File containing model URLs (one per line)
	--model-dir <path>       Target directory for downloaded models (default: ${MODEL_DIR})

	--skip-conda             Skip conda installation (assumes conda available)
	--skip-pip               Skip Python requirements installation
	--skip-node              Skip nvm/Node.js installation
	--skip-frontend          Skip npm install in frontend/
	--download-models        Enable model download step (requires URLs)
	--yes                    Non-interactive mode; assume "yes" where applicable
	-h, --help               Show this help

Examples:
	./startup.sh --env-name chartspark --python 3.10 --node lts/* --yes
	./startup.sh --download-models --model-url https://host/path/model.bin --model-dir ./generation/ldm/models
	./startup.sh --models-file ./models.txt --yes
EOF
}

log() { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1" >&2; }

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		err "Missing required command: $1"; return 1
	fi
}

# Detect architecture for Miniconda
detect_arch() {
	local arch="$(uname -m)"
	case "$arch" in
		x86_64) echo "x86_64" ;;
		aarch64|arm64) echo "aarch64" ;;
		*) err "Unsupported architecture: $arch"; return 1 ;;
	esac
}

fetch_to_file() {
	# Args: URL DEST
	local url="$1" dest="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$dest"
	elif command -v wget >/dev/null 2>&1; then
		wget -q "$url" -O "$dest"
	else
		err "Neither curl nor wget found"; return 1
	fi
}

fetch_stream() {
	# Args: URL | outputs to stdout
	local url="$1"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O - "$url"
	else
		err "Neither curl nor wget found"; return 1
	fi
}

install_miniconda_if_needed() {
	if command -v conda >/dev/null 2>&1; then
		info "conda found; skipping Miniconda installation"
		return 0
	fi
	if [[ "$CONDA_AUTO_INSTALL" != true ]]; then
		warn "conda not found and --skip-conda provided; continuing without installing conda"
		return 0
	fi

	local arch="$(detect_arch)" || return 1
	local installer="Miniconda3-latest-Linux-${arch}.sh"
	local url="https://repo.anaconda.com/miniconda/${installer}"
	local tmp_installer="${TMPDIR:-/tmp}/${installer}"

	info "Downloading Miniconda installer (${arch})..."
	fetch_to_file "$url" "$tmp_installer"
	chmod +x "$tmp_installer"

	local target="$HOME/miniconda3"
	info "Installing Miniconda to $target ..."
	if [[ "$NON_INTERACTIVE" == true ]]; then
		bash "$tmp_installer" -b -p "$target"
	else
		bash "$tmp_installer" -p "$target"
	fi

	# Initialize conda for bash
	source "$target/etc/profile.d/conda.sh" || true
	"$target/bin/conda" init bash || true
	log "Miniconda installed"
}

ensure_conda_shell() {
	if command -v conda >/dev/null 2>&1; then
		eval "$(conda shell.bash hook)" || true
	else
		# Attempt to source from default location
		if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
			source "$HOME/miniconda3/etc/profile.d/conda.sh"
			eval "$(conda shell.bash hook)" || true
		fi
	fi
}

conda_env_exists() {
	local env_path
	env_path="$(conda info --base 2>/dev/null)/envs/${ENV_NAME}"
	[[ -d "$env_path" ]]
}

create_conda_env() {
	require_cmd conda || return 1
	if conda_env_exists; then
		info "Conda env '${ENV_NAME}' already exists"
	else
		info "Creating conda env '${ENV_NAME}' with Python ${PYTHON_VERSION}..."
		conda create -y -n "$ENV_NAME" "python=${PYTHON_VERSION}"
		log "Conda env '${ENV_NAME}' created"
	fi
}

pip_install_requirements() {
	if [[ "$DO_PIP_INSTALL" != true ]]; then
		warn "Skipping pip install per flag"
		return 0
	fi
	require_cmd conda || return 1
	if [[ ! -f "$WORKSPACE_DIR/requirements.txt" ]]; then
		warn "requirements.txt not found; skipping"
		return 0
	fi
	info "Upgrading pip and installing Python requirements..."
	conda run -n "$ENV_NAME" python -m pip install --upgrade pip
	conda run -n "$ENV_NAME" python -m pip install -r "$WORKSPACE_DIR/requirements.txt"
	log "Python dependencies installed"
}

install_nvm_and_node() {
	if [[ "$DO_NODE_INSTALL" != true ]]; then
		warn "Skipping nvm/Node installation per flag"
		return 0
	fi

	local nvm_dir="$HOME/.nvm"
	if ! command -v nvm >/dev/null 2>&1; then
		info "Installing nvm..."
		# Pin a stable nvm version
		fetch_stream "https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh" | bash
	fi
	export NVM_DIR="$nvm_dir"
	# shellcheck disable=SC1090
	[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

	info "Installing/using Node '$NODE_VERSION' via nvm..."
	nvm install "$NODE_VERSION"
	nvm use "$NODE_VERSION"
	log "Node version: $(node -v), npm: $(npm -v)"
}

install_frontend_dependencies() {
	if [[ "$DO_FRONTEND_INSTALL" != true ]]; then
		warn "Skipping frontend npm install per flag"
		return 0
	fi
	if [[ ! -d "$WORKSPACE_DIR/frontend" ]]; then
		warn "frontend/ directory not found; skipping"
		return 0
	fi
	pushd "$WORKSPACE_DIR/frontend" >/dev/null
	if [[ -f package-lock.json ]]; then
		info "Running npm ci in frontend/ ..."
		npm ci
	else
		info "Running npm install in frontend/ ..."
		npm install
	fi
	popd >/dev/null
	log "Frontend dependencies installed"
}

download_one_model() {
	# Args: URL TARGET_DIR
	local url="$1" target_dir="$2"
	mkdir -p "$target_dir"
	local filename
	filename="$(basename "${url%%\?*}")"
	local dest="$target_dir/$filename"

	info "Downloading model: $url -> $dest"
	if command -v aria2c >/dev/null 2>&1; then
		aria2c -x 16 -s 16 -k 1M -d "$target_dir" -o "$filename" "$url"
	else
		fetch_to_file "$url" "$dest"
	fi
	log "Downloaded: $dest"
}

download_models() {
	if [[ "$DO_MODEL_DOWNLOAD" != true ]]; then
		warn "Model download disabled; skipping"
		return 0
	fi

	# Read URLs from file if provided
	if [[ -n "$MODELS_FILE" ]]; then
		if [[ -f "$MODELS_FILE" ]]; then
			mapfile -t file_urls < <(grep -E -v '^\s*(#|$)' "$MODELS_FILE")
			MODEL_URLS+=("${file_urls[@]}")
		else
			warn "Models file not found: $MODELS_FILE"
		fi
	fi

	if [[ ${#MODEL_URLS[@]} -eq 0 ]]; then
		warn "No model URLs provided; skip download"
		return 0
	fi

	info "Downloading ${#MODEL_URLS[@]} model(s) to $MODEL_DIR ..."
	for url in "${MODEL_URLS[@]}"; do
		download_one_model "$url" "$MODEL_DIR"
	done
	log "Model download step completed"
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--env-name)
				ENV_NAME="$2"; shift 2 ;;
			--python)
				PYTHON_VERSION="$2"; shift 2 ;;
			--node)
				NODE_VERSION="$2"; shift 2 ;;
			--model-url)
				MODEL_URLS+=("$2"); DO_MODEL_DOWNLOAD=true; shift 2 ;;
			--models-file)
				MODELS_FILE="$2"; DO_MODEL_DOWNLOAD=true; shift 2 ;;
			--model-dir)
				MODEL_DIR="$2"; shift 2 ;;
			--skip-conda)
				CONDA_AUTO_INSTALL=false; shift ;;
			--skip-pip)
				DO_PIP_INSTALL=false; shift ;;
			--skip-node)
				DO_NODE_INSTALL=false; shift ;;
			--skip-frontend)
				DO_FRONTEND_INSTALL=false; shift ;;
			--download-models)
				DO_MODEL_DOWNLOAD=true; shift ;;
			--yes)
				NON_INTERACTIVE=true; shift ;;
			-h|--help)
				usage; exit 0 ;;
			*)
				err "Unknown option: $1"; usage; exit 1 ;;
		esac
	done
}

main() {
	parse_args "$@"

	info "Workspace: $WORKSPACE_DIR"
	info "Conda env: $ENV_NAME (Python ${PYTHON_VERSION})"
	info "Node: ${NODE_VERSION}"

	install_miniconda_if_needed
	ensure_conda_shell
	require_cmd conda || { err "conda is required"; exit 1; }
	create_conda_env
	pip_install_requirements

	install_nvm_and_node
	install_frontend_dependencies

	download_models

	echo
	log "Environment setup complete"
	echo -e "${BLUE}Summary:${NC}"
	echo "  - Conda env: ${ENV_NAME} (Python ${PYTHON_VERSION})"
	echo "  - Node version: ${NODE_VERSION}"
	echo "  - Frontend deps: ${DO_FRONTEND_INSTALL}"
	echo "  - Models downloaded: ${DO_MODEL_DOWNLOAD} -> ${MODEL_DIR}"
	echo
	echo "Next steps:"
	echo "  - Activate env: conda activate ${ENV_NAME}"
	echo "  - Run backend: python chartSpeak.py (after env activation)"
	echo "  - Run frontend dev: cd frontend && npm run dev"
}

trap 'err "Script failed at line $LINENO"' ERR

main "$@"

