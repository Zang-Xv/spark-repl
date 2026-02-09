#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# ChartSpark 环境搭建与启动脚本 (Environment Setup & Startup Script)
# ==============================================================================
# 
# 这个脚本不仅仅是一个自动安装工具，也是一份可执行的 "README" 文档。
# 你可以通过阅读本脚本了解 ChartSpark 运行所需的环境依赖和配置流程。
#
# 流程概览:
# 1. 检查并安装 Conda (如果未安装)
# 2. 创建名为 'spark' 的 Python 3.9 虚拟环境
# 3. 安装 Python 后端依赖 (requirements.txt)
# 4. 安装 Node.js v18 (使用 nvm)
# 5. 安装前端依赖 (npm install)
# 6. 下载模型文件(因为需要配置代理等问题, 这里仅作占位)
# ==============================================================================

# 定义颜色用于输出显示
green() { echo -e "\033[32m[OK] $1\033[0m"; }
blue()  { echo -e "\033[34m[INFO] $1\033[0m"; }
yellow(){ echo -e "\033[33m[WARN] $1\033[0m"; }
red()   { echo -e "\033[31m[ERR] $1\033[0m"; }

# ------------------------------------------------------------------------------
# 配置部分 (Configuration)
# ------------------------------------------------------------------------------
ENV_NAME="spark"
PYTHON_VERSION="3.9"
NODE_VERSION="v18.20.8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"

blue "开始执行 ChartSpark 环境搭建流程..."

# ------------------------------------------------------------------------------
# 第一步: Conda 环境检查与安装 (Step 1: Check & Install Conda)
# ------------------------------------------------------------------------------
# 我们首先需要 Conda 来管理 Python 环境。如果系统中没有 conda，
# 脚本会自动下载 Miniconda 并安装到当前用户的目录下。
#
# 安装细节:
# - 安装位置: $HOME/miniconda3 (默认用户主目录下的 miniconda3 文件夹)
# - 策略: 如果检测到目录已存在，尝试直接加载；否则下载并安装。
# ------------------------------------------------------------------------------

if ! command -v conda >/dev/null 2>&1; then
    INSTALL_TARGET="$HOME/miniconda3"
    
    # 防御措施：如果目录存在，先尝试加载，避免重复安装
    if [ -d "$INSTALL_TARGET" ]; then
        yellow "检测到 '$INSTALL_TARGET' 已存在，尝试加载..."
        source "$INSTALL_TARGET/etc/profile.d/conda.sh" || true
    fi
    
    # 再次检查，如果加载后 still missing，则执行安装
    if ! command -v conda >/dev/null 2>&1; then
        blue "未检测到 Conda，准备安装 Miniconda..."
        
        # 根据系统架构选择安装包
        ARCH="$(uname -m)"
        INSTALLER="Miniconda3-latest-Linux-${ARCH}.sh"
        URL="https://repo.anaconda.com/miniconda/${INSTALLER}"
        TMP_INSTALLER="${TMPDIR:-/tmp}/${INSTALLER}"

        blue "正在下载安装包: $URL"
        curl -fsSL "$URL" -o "$TMP_INSTALLER"
        chmod +x "$TMP_INSTALLER"

        blue "正在安装 Miniconda 到 $INSTALL_TARGET ..."
        # -u 更新模式 (update)，防止目录存在报错
        bash "$TMP_INSTALLER" -b -u -p "$INSTALL_TARGET"

        # 初始化 Conda 环境
        source "$INSTALL_TARGET/etc/profile.d/conda.sh"
        "$INSTALL_TARGET/bin/conda" init bash
        
        green "Miniconda 安装完成"
    else
        green "通过加载现有目录成功找到 Conda"
    fi
else
    green "检测到系统已安装 Conda"
fi

# 确保当前可以使用 conda 命令
# 注意：在某些 shell 环境下，可能需要重新 source 配置文件
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
fi

# ------------------------------------------------------------------------------
# 针对可能出现的 CondaToSNonInteractiveError，自动接受相关频道的服务条款
# ------------------------------------------------------------------------------
if conda tos --help >/dev/null 2>&1; then
    blue "检测到可能需要接受 Conda 服务条款，正在尝试接受..."
    # 按照提示接受 main 和 r 频道的协议
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >/dev/null 2>&1 || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >/dev/null 2>&1 || true
    green "已尝试接受 Conda 服务条款"
fi

# ------------------------------------------------------------------------------
# 第二步: Python 虚拟环境配置 (Step 2: Setup Python Virtual Env)
# ------------------------------------------------------------------------------
# 创建一个独立的 Conda 环境来运行后端代码，避免污染全局环境。
# 环境名称默认为 'spark'，Python 版本为 3.9。
#
# 配置细节:
# - 环境名称: spark (变量 $ENV_NAME)
# - Python版本: 3.9 (变量 $PYTHON_VERSION)
# - 策略: 检查环境是否已存在。如果存在则跳过创建直接激活；否则创建新环境。
# ------------------------------------------------------------------------------

blue "检查 Conda 环境: $ENV_NAME"

# 防御措施：判断当前是否已经在正确的环境中
if [[ "${CONDA_DEFAULT_ENV:-}" == "$ENV_NAME" ]]; then
    green "当前已激活环境 '$ENV_NAME'，跳过创建与激活步骤"
else
    if conda env list | grep -q "$ENV_NAME"; then
        blue "环境 '$ENV_NAME' 已存在，跳过创建"
    else
        blue "正在创建 Conda 环境 '$ENV_NAME' (Python $PYTHON_VERSION)..."
        conda create -y -n "$ENV_NAME" "python=$PYTHON_VERSION"
        green "环境 '$ENV_NAME' 创建成功"
    fi

    # 激活环境
    # 防御措施：尝试多种方式激活环境
    blue "正在激活环境..."
    if command -v activate >/dev/null 2>&1; then
        source activate "$ENV_NAME"
    else
        # 尝试 source conda.sh 再次确保环境
        # 这里加了 || true 防止 conda info 失败导致脚本退出
        CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")
        if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
            source "$CONDA_BASE/etc/profile.d/conda.sh"
        fi
        conda activate "$ENV_NAME"
    fi
    green "已激活 Conda 环境: $ENV_NAME"
fi

# ------------------------------------------------------------------------------
# 第三步: 安装后端依赖 (Step 3: Install Backend Dependencies)
# ------------------------------------------------------------------------------
# 后端依赖定义在 requirements.txt 文件中。
#
# 安装细节:
# - 依赖文件: ./requirements.txt
# - 安装工具: pip (对应 'spark' 环境中的 pip)
# - 策略: 检查文件是否存在。存在则升级 pip 并安装依赖；不存在则跳过。
# ------------------------------------------------------------------------------

REQUIREMENTS_FILE="$WORKSPACE_DIR/requirements.txt"

if [[ -f "$REQUIREMENTS_FILE" ]]; then
    # 防御措施：确认安装目录
    PYTHON_EXEC=$(which python)
    if [[ "$PYTHON_EXEC" != *"$ENV_NAME"* ]]; then
        yellow "警告: Python 路径 '$PYTHON_EXEC' 似乎不包含环境名 '$ENV_NAME'"
        yellow "依赖可能会安装到错误的位置。请确认是否继续? (由脚本自动继续...)"
    fi

    blue "正在安装 Python 依赖库 (pip)..."
    blue "使用 Python: $PYTHON_EXEC"
    pip install --upgrade pip
    pip install -r "$REQUIREMENTS_FILE"
    green "Python 依赖安装完成"
else
    yellow "未找到 $REQUIREMENTS_FILE，跳过 Python 依赖安装"
fi

# ------------------------------------------------------------------------------
# 第四步: Node.js 环境配置 (Step 4: Setup Node.js Environment)
# ------------------------------------------------------------------------------
# 前端项目需要 Node.js 环境。这里使用 NVM (Node Version Manager) 来管理版本，
# 确保使用且仅使用我们指定的 Node 版本 (v18.20.8)。
#
# 安装细节:
# - 工具: NVM (Node Version Manager)
# - NVM位置: $HOME/.nvm
# - Node版本: v18.20.8
# - 策略: 检查 nvm 是否安装，未安装则自动下载脚本安装。最后强制切换到指定 Node 版本。
# ------------------------------------------------------------------------------

if ! command -v nvm >/dev/null 2>&1; then
    blue "未检测到 nvm，正在安装..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    green "nvm 安装完成"
else
    # 确保加载 nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    green "检测到已安装 nvm"
fi

blue "正在安装/切换到 Node.js $NODE_VERSION ..."
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"
green "当前 Node 版本: $(node -v)"
green "当前 npm 版本: $(npm -v)"

# ------------------------------------------------------------------------------
# 第五步: 安装前端依赖 (Step 5: Install Frontend Dependencies)
# ------------------------------------------------------------------------------
# 进入 frontend 目录并运行 npm install。
#
# 安装细节:
# - 目录位置: ./frontend
# - 命令: npm install
# - 策略: 检查 frontend 目录是否存在。存在则进入目录执行安装；否则跳过。
# ------------------------------------------------------------------------------

FRONTEND_DIR="$WORKSPACE_DIR/frontend"

if [[ -d "$FRONTEND_DIR" ]]; then
    blue "正在安装前端依赖 (npm install)..."
    pushd "$FRONTEND_DIR" >/dev/null
    npm install
    popd >/dev/null
    green "前端依赖安装完成"
else
    yellow "未找到 frontend 目录，跳过前端依赖安装"
fi

# ==============================================================================
# 搭建完成 (Setup Complete)
# ==============================================================================

echo ""
echo -e "\033[32m========== 环境搭建全流程结束 ===========\033[0m"
echo -e "\033[34m接下来你可以通过以下命令启动项目：\033[0m"
echo ""
echo "1. 激活环境 (如果新开终端):"
echo "   conda activate $ENV_NAME"
echo ""
echo "2. 启动后端服务:"
echo "   python chartSpeak.py"
echo ""
echo "3. 启动前端开发服务器:"
echo "   cd frontend && npm run dev"
echo ""
