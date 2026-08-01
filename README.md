# cuda-runtime desktop

基于 `nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04` 的精简 GPU 桌面镜像，面向 ML 算法工程师的远程开发与可视化调试场景。提供浏览器桌面（noVNC）与 SSH，并通过单端口复用对外暴露，适合企业内网、GPU 集群调度平台或 JupyterHub 集成部署。

## 特性

- **桌面环境**：xfce4 精简桌面
- **远程访问**：noVNC（浏览器）+ SSH，单端口复用（`8080` 同时承载 noVNC HTTP 与 SSH）
- **输入法**：fcitx + 百度拼音
- **动态标题**：浏览器标签自动显示 `自定义标题 [容器名 @ 容器IP]`
- **最小权限**：非 root 用户 `ml` 运行；sudo 受限白名单，敏感操作需密码

> 本镜像**不安装**任何 ML / Python 包，仅提供系统自带的 `python3`。如需 PyTorch 等，请进入容器后自行安装，或基于本镜像构建上层镜像。

## 构建

```bash
docker build -t cuda-runtime-desktop .
```

可选构建参数（覆盖默认 VNC / 登录 / sudo 密码，仅作为镜像内置兜底，建议运行时再覆盖）：

```bash
docker build --build-arg VNC_PW=your-secret -t cuda-runtime-desktop .
```

> `VNC_PW` 同时作为 **VNC 桌面密码**、**SSH 登录密码**、**sudo 密码**。

## 运行

```bash
docker run --gpus all -it --rm \
  -p 8080:8080 \
  -e NOVNC_TITLE="我的工作站" \
  -e VNC_PW=your-secret \
  -v $(pwd)/workspace:/workspace \
  cuda-runtime-desktop
```

- 浏览器访问 `http://localhost:8080` 即可进入桌面。
- SSH（同一端口，自动协议复用）：`ssh -p 8080 ml@localhost`，密码为 `VNC_PW`。

## 安全说明

| 项 | 说明 |
| --- | --- |
| 用户模型 | 容器以非 root 用户 `ml` 运行（独立 gid 1000，非 root 组）；所有桌面/SSH 会话均为 `ml` 身份 |
| sudo 策略 | 默认**需要密码**；仅 `start-sshd.sh`（固定参数）、`configure_ssh.py`、`set-ml-password-if-unlocked.sh` 三条精确命令通过白名单免密（见 `resources/sudoers/ml-services`），无通配符，杜绝提权 |
| 密码 | `VNC_PW` 为弱默认值时自动生成 24 位强随机密码；首次启动经 stdin `chpasswd` 注入并锁定（`/etc/.ml_ssh_pwd_revoked`），随机密码持久化复用（`/etc/.ml_generated_pwd`），重启后 VNC 桌面与 SSH/sudo 密码保持一致；用户用 `passwd` 改密不被覆盖 |
| SSH | 仅允许 `ml` 登录；禁用 root 登录、空密码；`StrictModes yes`、`MaxAuthTries 3`、`GatewayPorts no`、`PermitUserEnvironment no`；支持密钥（`~/.ssh/` 属 ml、0600）+ 密码双因子 |
| 私钥保护 | SSH 私钥保留在 `~/.ssh/`（0600，属 ml），**不再**导出到 `/resources`；仅公钥可下载；`/root/.ssh` 不再交给非 root 用户 |
| 进程隔离 | websockify 仅绑 `127.0.0.1`（外部访问统一走 oneport）；supervisord 关闭 inet HTTP 接口，仅 unix socket 控制 |
| 启动脚本 | **不**从 `/workspace` 执行任何脚本（共享数据卷，防投放后门）；如需启动定制，请基于本镜像扩展并在 `/resources/scripts` 下放置脚本 |
| 供应链 | 构建/运行期保留 Git HTTPS 证书校验；apt 不允许静默卸载 essential 包；SSL 自签证书仅用于 noVNC，不注入系统/Python 信任库，私钥 0600 |
| 文件权限 | 资源/工作/日志目录采用最小必要权限（0775/0755/0644），消除历史 `777`；目录仅设 setgid 不设 setuid |
| 前端 | noVNC 定制前端已移除调试 `console.log`（曾泄露剪贴板内容与按键） |

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `VNC_PW` | `vncpassword` | VNC 桌面密码、SSH 登录密码、sudo 密码。若保持弱默认值，**首次启动会自动生成 24 位强随机密码**并打印到 `docker logs`（`GENERATED_VNC_PW=...`），之后重启复用该密码。建议运行时显式覆盖 |
| `NOVNC_TITLE` | `Desktop` | noVNC 浏览器标签标题前缀，最终为 `NOVNC_TITLE [容器名 @ IP]` |
| `VNC_RESOLUTION` | `1600x900` | 桌面分辨率 |
| `VNC_COL_DEPTH` | `24` | 桌面色深 |
| `WORKSPACE_PORT` | `8080` | oneport 监听端口 |
| `WORKSPACE_BASE_URL` | `/` | 反向代理/JupyterHub 前缀，自动从 `JUPYTERHUB_SERVICE_PREFIX` 解析 |

## 端口

| 端口 | 用途 |
| --- | --- |
| `8080` | 主端口，复用 noVNC（HTTP）与 SSH |
| `5901` | 原始 VNC 端口（可选，不对外暴露） |

## 项目结构

```
.
├── Dockerfile                         # 镜像构建（多阶段：基础→运行时→GUI→输入法→配置）
├── resources/
│   ├── docker-entrypoint.py           # 入口：解析 base url、注入密码、委派启动
│   ├── scripts/
│   │   ├── run_workspace.py           # 服务编排：配置 SSH + 启动 supervisord
│   │   ├── configure_ssh.py           # SSH 密钥生成与权限收敛
│   │   ├── set-ml-password-if-unlocked.sh # 首次启动注入密码（一次性锁定+持久化复用）
│   │   ├── start-sshd.sh             # sshd 特权启动包装（固定参数，防提权）
│   │   ├── start-vnc-server.sh        # TigerVNC 前台化启动
│   │   ├── configure-novnc-title.sh   # 渲染 noVNC 标题
│   │   ├── setup-certs.sh             # SSL 证书生成/挂载
│   │   ├── fix-permissions.sh         # 目录权限修正
│   │   └── clean-layer.sh             # 镜像层清理
│   ├── ssh/                           # ssh_config / sshd_config
│   ├── supervisor/                    # supervisord 与各程序配置
│   ├── sudoers/ml-services            # 受限 sudo 白名单
│   ├── oneport/                       # 单端口协议复用
│   └── novnc/                         # noVNC 定制前端
└── README.md
```
