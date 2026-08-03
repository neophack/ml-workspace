#!/bin/bash
#
# 注销 = 停止整个容器。
#
# 由 XFCE 面板菜单的「Log Out」项触发：
#   Dockerfile 在 branding 阶段把 /usr/share/applications/xfce4-session-logout.desktop
#   的 Exec 从 `xfce4-session-logout` 改写为指向本脚本（参考 torch-2.1 的 killall python
#   做法，但本脚本只精确 kill 主链路，不无差别杀所有 python，避免误伤用户进程）。
#
# 机制（已验证）：
#   进程链  tini -g(PID1) → python3 /resources/docker-entrypoint.py
#                            → python3 /resources/scripts/run_workspace.py
#                               └─ run_workspace.py 末尾 run(["supervisord","-n",...]) 阻塞
#                                  └─ supervisord → vncserver/novnc/sshd/oneport
#   整链以 ml 用户运行（Dockerfile 末尾 USER $NB_USER=ml，supervisord.conf user=ml）。
#   ml 杀自己启动的进程无需提权，故本脚本不需要 sudo。
#
#   关键：让退出链走「正常退出」而非被信号强杀——
#     supervisorctl shutdown  →  supervisord 优雅停掉各服务后自身退出
#                              →  run_workspace.py 的 run([...]) 返回 0
#                              →  docker-entrypoint.py sys.exit(0)
#                              →  tini 失去直接子进程而退出 → 容器停止
#     整链 exit 0（配合 restart 策略，logout 不会被当崩溃重启）。
#
#   兜底：若 supervisorctl 不可用，退而求其次 pkill -TERM run_workspace.py ——
#     同样能让链路 unwind、容器停止，但服务会被 PID 命名空间 teardown 时 SIGKILL（非优雅）。
#
# Usage:
#   /resources/scripts/ml-logout.sh        # 由 .desktop 的 Exec 触发，无需参数
#
set -uo pipefail

log() { printf '[ml-logout] %s\n' "$*"; }

# ── 主路径：supervisorctl shutdown（优雅、exit 0）──────────────────────────────
#   supervisord 以 ml 身份运行，unix socket 在 /tmp/supervisor/supervisor.sock
#   （见 supervisord.conf [supervisorctl] serverurl），故 ml 可直接 supervisorctl，无需 sudo。
#   supervisorctl 默认读 /etc/supervisor/supervisord.conf，其中已含 serverurl 指向该 socket。
if command -v supervisorctl >/dev/null 2>&1; then
    if supervisorctl shutdown >/dev/null 2>&1; then
        log "已请求 supervisord 关闭，容器即将停止。"
        exit 0
    fi
    log "supervisorctl shutdown 未成功（supervisord 可能已不在），改用兜底。"
else
    log "未找到 supervisorctl，改用兜底。"
fi

# ── 兜底：pkill run_workspace.py ──────────────────────────────────────────────
#   精确匹配完整路径，避免误伤其它 python 进程（如用户手动起的 Jupyter / 脚本）。
PATTERN='python3 /resources/scripts/run_workspace.py'
if pkill -TERM -f "$PATTERN" 2>/dev/null; then
    log "已发送 SIGTERM 给 run_workspace.py，容器即将停止。"
    exit 0
fi

# ── 都失败 → 提示手动停止 ──────────────────────────────────────────────────────
log "⚠️ 既无法 supervisorctl shutdown，也未匹配到 run_workspace.py。"
log "   请在宿主机手动执行：docker stop <容器名>"
exit 1
