#!/bin/bash

# ==============================================================================
# apply-sysctl-to-all-containers.sh (v1.1 - 已修正语法错误)
#
# 将宿主机的 sysctl.conf 配置应用到所有正在运行的 Docker 容器中。
# 使用 nsenter 工具进入容器的命名空间来修改参数。
#
# 用法:
# sudo ./apply-sysctl-to-all-containers.sh
#
# 作者: Gemini
# 日期: 2025-06-07
# ==============================================================================

# --- 配置和变量 ---
set -o pipefail # 管道中的任何一个命令失败，整个管道都失败

# 定义输出颜色
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_CYAN='\033[0;36m'
COLOR_NC='\033[0m' # No Color

# --- 函数定义 ---

# 打印日志
log_info() {
    echo -e "${COLOR_CYAN}[INFO] $1${COLOR_NC}"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS] $1${COLOR_NC}"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR] $1${COLOR_NC}" >&2
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN] $1${COLOR_NC}"
}

# --- 主逻辑 ---

# 1. 检查权限和依赖
if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本需要以 root 权限运行。请使用 'sudo'。"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "未找到 'docker' 命令。请确保 Docker 已安装并处于 PATH 中。"
    exit 1
fi

if ! command -v nsenter &> /dev/null; then
    log_error "未找到 'nsenter' 命令。请安装 'util-linux' 包。"
    exit 1
fi

# 2. 获取所有正在运行的容器 ID
log_info "正在获取所有正在运行的容器列表..."
CONTAINER_IDS=$(docker ps -q)

# *** 这是被修正的部分 ***
if [ -z "$CONTAINER_IDS" ]; then
    log_warn "未找到任何正在运行的容器。"
    exit 0
fi

log_info "将对以下容器应用配置:"
# 使用 docker ps --format 来美化输出
docker ps --format "table {{.ID}}\t{{.Names}}"

# 3. 读取所有 sysctl 配置
# 合并所有 sysctl 配置文件内容到一个变量中
ALL_SYSCTL_FILES=$(find /etc/sysctl.conf /etc/sysctl.d/ -name "*.conf" 2>/dev/null)
if [ -z "$ALL_SYSCTL_FILES" ]; then
    log_warn "未找到任何 sysctl 配置文件。"
    exit 0
fi
# 使用 `sysctl -p` 解析所有文件，这是最健壮的方式
SYSCTL_CONFIGS=$(sysctl -p $ALL_SYSCTL_FILES 2>/dev/null)


# 4. 遍历每个容器并应用配置
for CONTAINER_ID in $CONTAINER_IDS; do
    echo
    CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's/^\///')
    log_info "--- 正在处理容器: $CONTAINER_NAME ($CONTAINER_ID) ---"

    # 获取容器的 PID
    PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_ID")
    if [ -z "$PID" ]; then
        log_error "  -> 无法获取容器 '$CONTAINER_NAME' 的 PID，跳过。"
        continue # 继续处理下一个容器
    fi
    log_info "  -> 容器 PID 为: $PID"

    log_info "  -> 开始应用配置..."
    # 逐行处理已解析的配置
    echo "$SYSCTL_CONFIGS" | while IFS= read -r line || [ -n "$line" ]; do
        key=$(echo "$line" | awk -F'=' '{print $1}' | tr -d '[:space:]')
        value=$(echo "$line" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')

        if [ -z "$key" ] || [ -z "$value" ]; then
            continue
        fi

        # 筛选命名空间化的参数
        case "$key" in
            net.*|kernel.shm*|kernel.msg*|fs.mqueue.*)
                # 使用 nsenter 进入容器的网络(n)和IPC(i)命名空间来应用设置
                if sudo nsenter -t "$PID" -n -i sysctl -w "$key=$value" >/dev/null 2>&1; then
                    echo -e "    ${COLOR_GREEN}✔ 已应用: $key = $value${COLOR_NC}"
                else
                    echo -e "    ${COLOR_YELLOW}✘ 应用失败: $key = $value (容器可能不支持此参数或权限不足)${COLOR_NC}"
                fi
                ;;
            *)
                # 跳过全局参数，不打印日志以保持输出简洁
                :
                ;;
        esac
    done
    log_success "--- 已完成对容器 $CONTAINER_NAME 的处理 ---"
done

echo
log_success "脚本执行完毕。"
