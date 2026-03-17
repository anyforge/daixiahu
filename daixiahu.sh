#!/bin/bash

# ============================================
# 🚀 逮虾户 - OpenClaw 彻底卸载脚本
# ============================================

# 颜色定义
BOLD='\033[1m'
ACCENT='\033[38;2;255;90;45m'
SUCCESS='\033[38;2;47;191;113m'
WARN='\033[38;2;255;176;32m'
ERROR='\033[38;2;226;61;45m'
MUTED='\033[38;2;139;127;119m'
NC='\033[0m' # No Color

# OpenClaw 核心包名
CLAWDBOT_NPM_PKG="openclaw"

# ============================================
# Spinner Implementation (clack-style)
# ============================================
SPINNER_PID=""
SPINNER_MSG=""
SPINNER_FRAMES=('◒' '◐' '◓' '◑')

spinner_start() {
    local msg="${1:-Processing...}"
    SPINNER_MSG="$msg"
    if [[ ! -t 1 ]]; then
        printf "${ACCENT}◆${NC} ${msg}\n"
        return
    fi
    {
        local idx=0
        while true; do
            printf "\r${ACCENT}${SPINNER_FRAMES[$idx]}${NC} ${msg} "
            ((idx = (idx + 1) % ${#SPINNER_FRAMES[@]}))
            sleep 0.12
        done
    } &
    SPINNER_PID=$!
    disown $SPINNER_PID 2>/dev/null || true
}

spinner_stop() {
    local status="${1:-0}"
    local final_msg="${2:-$SPINNER_MSG}"
    if [[ -n "$SPINNER_PID" ]]; then
        kill $SPINNER_PID 2>/dev/null || true
        wait $SPINNER_PID 2>/dev/null || true
        SPINNER_PID=""
    fi
    if [[ -t 1 ]]; then
        printf "\r\033[K"
    fi
    if [[ "$status" -eq 0 ]]; then
        printf "${SUCCESS}◆${NC} ${final_msg}\n"
    else
        printf "${ERROR}◆${NC} ${final_msg}\n"
    fi
}

# ============================================
# Logging Infrastructure
# ============================================
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg"
}

# ============================================
# Helper Functions
# ============================================
resolve_clawdbot_bin() {
    local npm_bin=""
    npm_bin="$(npm global bin 2>/dev/null || true)"
    if [[ -n "$npm_bin" && -x "${npm_bin}/openclaw" ]]; then
        echo "${npm_bin}/openclaw"
        return 0
    fi
    if command -v openclaw &> /dev/null; then
        command -v openclaw
        return 0
    fi
    return 1
}

# ============================================
# Uninstall Module (Extracted & Adapted)
# ============================================
stop_gateway_service() {
    local claw=""
    claw="$(resolve_clawdbot_bin || true)"
    if [[ -n "$claw" ]]; then
        spinner_start "停止 Gateway 服务..."
        "$claw" gateway stop 2>/dev/null || true
        spinner_stop 0 "Gateway 服务已停止"
    fi

    # Also stop legacy Clawdbot/Moltbot gateway processes if running
    for legacy_bin in clawdbot moltbot; do
        local legacy_path=""
        legacy_path="$(command -v "$legacy_bin" 2>/dev/null || true)"
        if [[ -n "$legacy_path" ]]; then
            "$legacy_path" gateway stop 2>/dev/null || true
        fi
    done
}

uninstall_clawdbot_components() {
    local claw=""
    claw="$(resolve_clawdbot_bin || true)"
    if [[ -n "$claw" ]]; then
        spinner_start "卸载 OpenClaw 组件..."
        "$claw" uninstall --all --yes 2>/dev/null || true
        spinner_stop 0 "组件已卸载"
    fi
}

uninstall_npm_packages() {
    spinner_start "卸载 npm/pnpm 全局包..."
    # npm global uninstall
    npm uninstall -g openclaw clawdbot moltbot clawdbot-dingtalk >/dev/null 2>&1 || true
    # pnpm global uninstall
    if command -v pnpm &> /dev/null; then
        pnpm remove -g openclaw clawdbot moltbot clawdbot-dingtalk >/dev/null 2>&1 || true
        # Remove residual bin links
        local pnpm_bin=""
        pnpm_bin="$(pnpm bin -g 2>/dev/null || true)"
        for bin_name in openclaw clawdbot moltbot; do
            if [[ -n "$pnpm_bin" && -L "${pnpm_bin}/${bin_name}" ]]; then
                rm -f "${pnpm_bin}/${bin_name}" 2>/dev/null || true
            fi
        done
    fi
    # Remove residual directories from npm global
    local npm_root=""
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -n "$npm_root" ]]; then
        for pkg_dir in openclaw clawdbot moltbot clawdbot-dingtalk; do
            rm -rf "${npm_root}/${pkg_dir}" 2>/dev/null || true
        done
    fi
    spinner_stop 0 "npm/pnpm 包已卸载"
}

cleanup_clawdbot_directories() {
    spinner_start "清理所有 OpenClaw 数据目录..."
    # Current OpenClaw directories
    rm -rf ~/.openclaw 2>/dev/null || true
    rm -rf ~/clawd 2>/dev/null || true
    # Legacy Clawdbot/Moltbot directories
    rm -rf ~/.clawdbot 2>/dev/null || true
    rm -rf ~/.moltbot 2>/dev/null || true
    spinner_stop 0 "数据目录已清理"
}

cleanup_service_files() {
    # Linux systemd — current OpenClaw + legacy Clawdbot/Moltbot service names
    local systemd_dir="$HOME/.config/systemd/user"
    local cleaned_systemd=0
    for svc_name in openclaw-gateway clawdbot-gateway moltbot-gateway; do
        if [[ -f "${systemd_dir}/${svc_name}.service" ]]; then
            if [[ "$cleaned_systemd" == "0" ]]; then
                spinner_start "清理 systemd 服务文件..."
                cleaned_systemd=1
            fi
            systemctl --user disable "${svc_name}.service" 2>/dev/null || true
            systemctl --user stop "${svc_name}.service" 2>/dev/null || true
            rm -f "${systemd_dir}/${svc_name}.service" 2>/dev/null || true
        fi
    done
    if [[ "$cleaned_systemd" == "1" ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
        spinner_stop 0 "systemd 服务已清理"
    fi

    # macOS launchd — current OpenClaw + legacy Clawdbot/Moltbot plist labels
    local launch_dir="$HOME/Library/LaunchAgents"
    local cleaned_launchd=0
    for plist_label in ai.openclaw.gateway com.moltbot.gateway com.clawdbot.gateway; do
        if [[ -f "${launch_dir}/${plist_label}.plist" ]]; then
            if [[ "$cleaned_launchd" == "0" ]]; then
                spinner_start "清理 launchd 服务文件..."
                cleaned_launchd=1
            fi
            launchctl bootout "gui/$(id -u)/${plist_label}" 2>/dev/null || \
            launchctl unload "${launch_dir}/${plist_label}.plist" 2>/dev/null || true
            rm -f "${launch_dir}/${plist_label}.plist" 2>/dev/null || true
        fi
    done
    if [[ "$cleaned_launchd" == "1" ]]; then
        spinner_stop 0 "launchd 服务已清理"
    fi
}

# ============================================
# Main Execution
# ============================================
main() {
    echo ""
    echo -e "${ACCENT}${BOLD}┌─────────────────────────────────────────┐${NC}"
    echo -e "${ACCENT}${BOLD}│ 🚀 逮虾户 - OpenClaw 彻底卸载脚本       ${NC}"
    echo -e "${ACCENT}${BOLD}└─────────────────────────────────────────┘${NC}"
    echo ""

    # Confirm uninstall
    echo -e "${WARN}◆${NC} 确定要完全卸载 OpenClaw 并删除所有配置和数据吗？这将无法撤销！"
    read -p " └─ 请输入 yes 确认: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${MUTED}卸载已取消。${NC}"
        exit 0
    fi

    log "INFO" "Starting full uninstallation..."

    # Stop gateway
    stop_gateway_service

    # Uninstall components
    uninstall_clawdbot_components

    # Uninstall npm packages
    uninstall_npm_packages

    # Cleanup directories (Purge all)
    cleanup_clawdbot_directories

    # Cleanup service files
    cleanup_service_files

    # Remove git wrapper if exists
    if [[ -x "$HOME/.local/bin/openclaw" ]]; then
        rm -f "$HOME/.local/bin/openclaw"
        echo -e "${SUCCESS}✓${NC} Git wrapper 已移除"
    fi

    echo ""
    echo -e "${SUCCESS}${BOLD}OpenClaw 已完全卸载，系统已恢复干净。${NC}"
    echo -e "${MUTED}如有残留的浏览器配置或手动安装的依赖，需手动清理。${NC}"
}

main "$@"
