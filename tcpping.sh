#!/bin/bash

# Usage: ./tcpping_logger.sh <IP_OR_HOST> [PORT]
# Example: ./tcpping_logger.sh 8.8.8.8 443

set -e

TARGET_IP="$1"
TARGET_PORT="${2:-80}"

if [[ -z "$TARGET_IP" ]]; then
  echo "Usage: $0 <IP_OR_HOST> [PORT]"
  exit 1
fi

# 安装依赖函数
install_dependencies() {
  echo "检查并安装依赖包..."

  # 安装tcptraceroute, bc, wget（如果未安装）
  for pkg in tcptraceroute bc wget; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      echo "安装依赖包: $pkg"
      sudo apt-get install -y "$pkg"
    fi
  done

  # 检查tcpping是否存在
  if ! command -v tcpping >/dev/null 2>&1; then
    echo "tcpping 未安装，开始下载..."
    sudo wget -q -O /usr/bin/tcpping http://www.vdberg.org/~richard/tcpping
    sudo chmod 755 /usr/bin/tcpping
    echo "tcpping 安装完成。"
  fi
}

# 日志目录
LOG_DIR="./tcpping_logs"
mkdir -p "$LOG_DIR"

# 日志文件名格式: tcpping_YYYY-MM-DD_<target>.log
get_log_file() {
  local date_str
  date_str=$(date +%F)  # YYYY-MM-DD
  # 用下划线替换IP/域名中的特殊字符，避免文件名问题
  local safe_target
  safe_target=$(echo "$TARGET_IP" | sed 's/[^a-zA-Z0-9]/_/g')
  echo "$LOG_DIR/tcpping_${date_str}_${safe_target}.log"
}

# 轮换日志文件，最多保留7个
rotate_logs() {
  local safe_target
  safe_target=$(echo "$TARGET_IP" | sed 's/[^a-zA-Z0-9]/_/g')
  local files
  files=($(ls -1t "$LOG_DIR"/tcpping_*_"$safe_target".log 2>/dev/null || true))
  local count=${#files[@]}
  if (( count > 7 )); then
    for ((i=7; i<count; i++)); do
      rm -f "${files[i]}"
    done
  fi
}

# 解析tcpping输出，提取延迟和超时信息
parse_tcpping_output() {
  local line="$1"
  # 例子: seq 0: tcp response from 163.223.183.105 [open]  42.321 ms
  if [[ "$line" =~ ([0-9.]+)\ ms ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "timeout"
  fi
}

install_dependencies

echo "开始对 $TARGET_IP TCP端口 $TARGET_PORT 进行tcpping，每秒一次，日志目录：$LOG_DIR"

while true; do
  LOG_FILE=$(get_log_file)
  rotate_logs

  # 运行tcpping一次，超时默认3秒等待
  # 使用 -c 1 只发一次包，-w 3 超时3秒，-p 指定端口
  # 需要sudo权限运行tcpping
  # 捕获输出
  OUTPUT=$(sudo tcpping -w 1 -x 1 "$TARGET_IP" "$TARGET_PORT" 2>&1 || true)

  CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  DELAY=$(parse_tcpping_output "$OUTPUT")

  if [[ "$DELAY" == "timeout" ]]; then
    echo "$CUR_TIME timeout yes" >> "$LOG_FILE"
  else
    echo "$CUR_TIME $DELAY no" >> "$LOG_FILE"
  fi

  # 计算下一秒整点睡眠，保证每秒执行一次
  sleep 1
done

