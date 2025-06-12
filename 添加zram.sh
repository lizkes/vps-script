#!/bin/bash

# --- 脚本初始化和权限检查 ---
set -e
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本需要以 root 权限运行。"
   echo "请尝试使用 'sudo ./your_script_name.sh' 来执行。"
   exit 1
fi

# --- 【高风险功能】检测并直接删除磁盘Swap的函数 ---
detect_and_remove_disk_swap() {
    echo "### 正在检测已存在的磁盘 Swap..."
    DISK_SWAPS=$(swapon --show --noheadings | grep -v "zram" || true)

    if [ -z "$DISK_SWAPS" ]; then
        echo "未检测到活动的磁盘 Swap。继续执行..."
        return
    fi

    echo -e "\n\e[1;31m【严重警告】检测到以下活动的磁盘 Swap：\e[0m"
    echo "------------------------------------------------"
    echo "$DISK_SWAPS"
    echo "------------------------------------------------"
    echo -e "此操作将 \e[1;31m永久禁用\e[0m 以下设备，并修改系统关键文件 /etc/fstab。"
    echo -e "将会执行：\n  1. 停用 (swapoff) 以上设备。\n  2. 从 /etc/fstab 中 \e[1;31m永久删除\e[0m 相关行。\n  3. \e[1;31m不会创建任何备份文件\e[0m。\n  4. 如果是swap文件，则删除该文件。"
    echo -e "\n\e[1;33m这是一个高风险操作，可能导致系统无法启动。除非您完全明白后果，否则请选择 'n'。\e[0m"
    
    read -p $'\e[1;33m您确定要继续执行这些永久性禁用操作吗？ (y/N): \e[0m' choice
    
    if [[ ! "$choice" =~ ^[yY]$ ]]; then
        echo "操作已取消。保留现有磁盘 Swap。"
        return
    fi

    echo "用户已确认高风险操作，正在处理..."
    while read -r line; do
        local swap_device=$(echo "$line" | awk '{print $1}')
        echo -e "\n  -> 正在处理: $swap_device"
        echo "     1. 停用 Swap: swapoff $swap_device"
        swapoff "$swap_device"
        echo -e "     2. \e[1;31m从 /etc/fstab 中永久删除相关行 (无备份)...\e[0m"
        sed -i "\|$swap_device.*swap|d" /etc/fstab
        if [ -f "$swap_device" ]; then
            echo "     3. 检测到 $swap_device 是一个文件，正在删除..."
            rm -f "$swap_device"
        fi
        echo "     处理完成: $swap_device"
    done <<< "$DISK_SWAPS"
    echo -e "\n所有已发现的磁盘 Swap 已被成功禁用。"
}

#####################################################################
#                              主脚本开始
#####################################################################

echo "### 欢迎使用 zram 智能配置脚本 (V10 - 全新检测核心) ###"

# --- 步骤 1: 调用磁盘Swap检测与移除功能 ---
detect_and_remove_disk_swap


# --- 步骤 2: 检查并处理已有的 zram swap ---
if swapon --show | grep -q "zram"; then
    echo -e "\n检测到 zram swap 已处于激活状态。"
    echo "当前状态如下："
    swapon --show; echo "--------------------"; zramctl
    echo "--------------------"
    read -p "你是否仍要强制重新配置 zram？ (y/N): " choice
    case "$choice" in 
      y|Y ) 
        echo "用户选择强制重新配置，脚本将继续..."
        echo "正在停用现有的 zram 服务..."
        systemctl stop zramswap 2>/dev/null || true
        ;;
      * ) 
        echo "操作已取消。"
        exit 0
        ;;
    esac
else
    echo -e "\n检测到 zram swap 未激活，准备开始配置..."
fi


# --- 步骤 3: 先安装工具，确保所有内核模块文件都已存在 ---
echo -e "\n### 正在更新软件包列表并安装 zram-tools..."
apt-get update
apt-get install -y zram-tools


# --- 步骤 4: 【全新检测方法】检查 zstd.ko 模块文件是否存在 ---
echo -e "\n### 正在检查内核模块以确定算法支持..."
# uname -r 会获取当前运行的内核版本，如 5.15.0-107-generic
# 然后在对应版本的模块目录中查找 zstd.ko 文件
# 这种方法比“运行时测试”更稳定可靠，从根本上避免了时序问题
if find "/lib/modules/$(uname -r)/kernel/" -name "zstd.ko" | grep -q "zstd.ko"; then
    ALGO="zstd"
    echo "检测通过：发现 zstd.ko 内核模块，系统支持 zstd 算法。"
else
    ALGO="lzo"
    echo "检测失败：未发现 zstd.ko 内核模块，将自动回退到 lzo 算法。"
fi


# --- 步骤 5: 让用户设置内存百分比 ---
echo "" 
while true; do
    read -p "请输入要用作 zram 的物理内存百分比 (推荐 50-150，直接回车使用默认值 100): " PERCENT_INPUT
    if [[ -z "$PERCENT_INPUT" ]]; then
        PERCENT=100
        echo "未输入值，将使用默认百分比: ${PERCENT}%"
        break
    fi
    if ! [[ "$PERCENT_INPUT" =~ ^[0-9]+$ ]]; then
        echo "错误：请输入一个有效的数字。"
        continue 
    fi
    if (( PERCENT_INPUT < 10 || PERCENT_INPUT > 400 )); then
        echo "错误：请输入一个介于 10 和 400 之间的百分比。"
        continue
    fi
    PERCENT=$PERCENT_INPUT
    echo "将使用百分比: ${PERCENT}%"
    break 
done


# --- 步骤 6: 写入最终配置 (不再需要临时加载模块)---
echo -e "\n### 正在写入最终配置..."
cat <<EOT >/etc/default/zramswap
# (此文件由脚本自动生成)
ALGO=${ALGO}
PERCENT=${PERCENT}
EOT
echo "配置文件 /etc/default/zramswap 已写入，算法: ${ALGO}, 百分比: ${PERCENT}%"


# --- 步骤 7: 启用并重启服务 ---
echo -e "\n### 正在启用并重启 zramswap 服务..."
# 确保 zram 模块在服务启动前是卸载的，以应用新配置
modprobe -r zram 2>/dev/null || true
systemctl enable zramswap
systemctl restart zramswap

echo -e "\n### ✅ 操作成功完成！###"
echo "zramswap 服务已配置并启动。"
echo -e "\n当前 zram 最终状态："
zramctl
