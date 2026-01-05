#!/bin/bash
# WiFi自动监控与重启脚本
# 功能：定时检查网络连通性，仅在网络异常时才执行重启操作。
# 使用方法：sudo ./wifi-monitor.sh <检查间隔秒数>
# 推荐用法：将其设置为 systemd 服务实现开机自启和后台稳定运行。

# --- 可配置参数 ---

# 1. Ping 测试的目标地址
#    建议设置为你的路由器网关地址（如 "192.168.1.1"），这是最可靠的内网连通性检查。
#    如果需要检查外网连通性，可以使用稳定的公共DNS服务器。
PING_TARGET="10.134.128.1"

# 2. 默认的检查间隔时间（秒）
#    设置得太短可能导致网络没来得及恢复就被误判为异常而陷入重启循环。
#    建议至少设置为 30 秒以上。
DEFAULT_INTERVAL=60

# --- 脚本主体 ---

# 检查传入的参数，如果没有则使用默认值
if [ $# -eq 0 ]; then
    INTERVAL=$DEFAULT_INTERVAL
else
    INTERVAL=$1
fi

# 检查脚本是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本。"
    exit 1
fi

# 检查设定的间隔时间是否过短，并给予警告
if [ "$INTERVAL" -lt 15 ]; then
    echo "警告：检查间隔时间 ($INTERVAL 秒) 小于15秒，可能导致网络来不及恢复而陷入重启循环！"
    echo "脚本将在3秒后继续..."
    sleep 3
fi

echo "--- WiFi连接监控已启动 ---"
echo "检查间隔: $INTERVAL 秒"
echo "Ping目标: $PING_TARGET"
echo "日志格式: [YYYY-MM-DD HH:MM:SS] 消息"
echo "按 Ctrl+C 可以停止脚本 (仅在终端直接运行时有效)"
echo "---------------------------"

# 捕获Ctrl+C信号 (SIGINT)，以便在手动运行时可以优雅退出
trap "echo -e '\n--- WiFi连接监控已停止 ---'; exit 0" INT

# 无限循环，持续监控
while true; do
    # 获取当前时间，用于日志记录
    current_time=$(date '+%Y-%m-%d %H:%M:%S')

    # 使用 ping 命令检查网络连通性
    # -c 1: 只发送1个ICMP数据包
    # -W 3: 等待响应的超时时间为3秒
    # &> /dev/null: 将标准输出和标准错误都重定向到/dev/null，即不显示ping的详细过程
    if ping -c 1 -W 3 "$PING_TARGET" &> /dev/null; then
        # Ping 成功，说明网络连接正常
        echo "[$current_time] 网络连接正常。"
    else
        # Ping 失败，说明网络连接异常，执行重启流程
        echo "[$current_time] 网络连接异常！正在尝试重启WiFi..."

        # 重启 NetworkManager 服务，这是最核心的操作
        systemctl restart NetworkManager

        # 重启后必须给予足够长的等待时间，以确保网络服务和硬件有时间完成初始化和重连
        echo "[$current_time] 重启指令已发送，等待15秒让网络服务恢复..."
        sleep 15

        # 再次检查WiFi硬件状态，作为操作反馈
        if nmcli radio wifi | grep -q "enabled"; then
          echo "[$current_time] WiFi重启操作完成。将在下个周期检查连接结果。"
        else
          echo "[$current_time] 警告：WiFi硬件状态为禁用，尝试强制启用！"
          nmcli radio wifi on
        fi
    fi

    # 等待指定的间隔时间后，进行下一次检查
    echo "[$current_time] 等待 $INTERVAL 秒后进行下一次检查..."
    sleep "$INTERVAL"
done
