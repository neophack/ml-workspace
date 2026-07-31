# cuda-runtime desktop

基于 `nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04` 的精简 GPU 桌面镜像。

## 特性

- **桌面环境**：xfce4
- **远程访问**：noVNC（浏览器）+ SSH，单端口复用（`8080` 同时承载 noVNC HTTP 与 SSH）
- **编辑器**：VS Code
- **输入法**：fcitx + 百度拼音
- **noVNC 标题动态化**：浏览器标签自动显示 `自定义标题 [容器名 @ 容器IP]`

> 本镜像**不安装**任何 ML / Python 包，仅提供系统自带的 `python3`。如需 PyTorch 等，请进入容器后自行安装。

## 构建

```bash
docker build -t cuda-runtime-desktop .
```

## 运行

```bash
docker run --gpus all -it --rm \
  -p 8080:8080 \
  -e NOVNC_TITLE="我的工作站" \
  -v $(pwd)/workspace:/workspace \
  cuda-runtime-desktop
```

- 浏览器访问 `http://localhost:8080` 即可进入桌面。
- SSH：`ssh -p 8080 ml@localhost`（同一端口，自动协议复用）。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `NOVNC_TITLE` | `Desktop` | noVNC 浏览器标签的自定义标题前缀，最终标题为 `NOVNC_TITLE [容器名 @ IP]` |
| `VNC_PW` | `vncpassword` | VNC 密码 |
| `VNC_RESOLUTION` | `1600x900` | 桌面分辨率 |
| `WORKSPACE_PORT` | `8080` | oneport 监听端口 |

## 端口

| 端口 | 用途 |
| --- | --- |
| `8080` | 主端口，复用 noVNC（HTTP）与 SSH |
| `5901` | 原始 VNC 端口（可选） |
