# 远程桌面控制系统

基于 **Flutter**（控制端 UI）+ **WebRTC**（低延迟画面推流）+ **Node.js**（信令服务器）的远程桌面控制方案。

## 架构

```
┌─────────────────┐     WebSocket 信令      ┌──────────────────┐
│  Flutter 控制端  │ ◄──────────────────────► │  Node.js 信令服务 │
│  (Viewer)       │                          │  (port 3000)     │
└────────┬────────┘                          └────────┬─────────┘
         │                                            │
         │              WebRTC P2P                    │
         │         (视频流 + ICE 协商)                   │
         ▼                                            ▼
┌─────────────────┐                          ┌──────────────────┐
│  远程画面显示    │                          │  主机端           │
│  触控/鼠标输入   │                          │  Flutter / 浏览器  │
└─────────────────┘                          └──────────────────┘
```

## 项目结构

```
remoteControl/
├── server/           # Node.js 信令服务器 + Web 主机页面
├── flutter_client/   # Flutter 客户端（主机 + 控制端）
└── package.json      # 便捷脚本
```

## 快速开始

### 1. 安装依赖

```bash
cd remoteControl
npm run install:all
```

### 2. 启动信令服务器

```bash
npm run server
```

服务启动后：
- 信令 WebSocket: `ws://localhost:3000/ws`
- Web 主机页面: `http://localhost:3000/host.html`
- 健康检查: `http://localhost:3000/health`

### 3. 启动主机端（二选一）

**方式 A：浏览器主机（推荐，最简单）**

1. 打开 `http://localhost:3000/host.html`
2. 点击「开始共享屏幕」，选择要共享的屏幕/窗口
3. 复制显示的房间号

> 浏览器主机仅支持画面共享，不支持注入系统级鼠标/键盘（浏览器安全限制）。

**方式 B：Flutter 桌面主机**

```bash
cd flutter_client
flutter run -d macos   # 或 windows / linux
```

在应用中选择「作为主机」，共享屏幕后将房间号发给控制端。

### 4. 启动 Flutter 控制端

```bash
cd flutter_client
flutter run            # iOS / Android / macOS / Web
```

1. 输入信令服务器地址（默认 `ws://localhost:3000/ws`）
2. 输入主机提供的房间号
3. 点击「作为控制端」连接

连接成功后即可看到远程桌面画面，支持：
- 单指拖动 → 鼠标移动
- 点击 → 左键点击
- 长按/右键 → 右键点击
- 滚轮/双指滑动 → 滚动

## 信令协议

| 消息类型 | 方向 | 说明 |
|---------|------|------|
| `create-room` | 主机 → 服务器 | 创建房间 |
| `join-room` | 控制端 → 服务器 | 加入房间 |
| `offer` / `answer` | 双向 | WebRTC SDP 交换 |
| `ice-candidate` | 双向 | ICE 候选交换 |
| `input-event` | 控制端 → 主机 | 远程输入事件 |

## 输入事件格式

```json
{
  "type": "mousemove | mousedown | mouseup | click | scroll | keydown | keyup",
  "x": 0.5,
  "y": 0.5,
  "button": 0,
  "deltaY": -10
}
```

坐标 `x`/`y` 为 0~1 的归一化值，相对于远程画面尺寸。

## 配置

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `PORT` | `3000` | 信令服务器端口 |

## 平台支持

| 组件 | macOS | Windows | Linux | iOS/Android |
|------|-------|---------|-------|-------------|
| 信令服务器 | ✅ | ✅ | ✅ | — |
| Flutter 控制端 | ✅ | ✅ | ✅ | ✅ |
| Flutter 主机 | ✅ | ✅ | ✅ | 部分 |
| 浏览器主机 | ✅ | ✅ | ✅ | — |

## 注意事项

1. **局域网/公网**：本方案使用 STUN 穿透，局域网内可直接连接；公网部署建议增加 TURN 服务器。
2. **权限**：macOS 主机需要屏幕录制和辅助功能权限。
3. **安全性**：当前为开发版，未加密房间、未做身份认证，生产环境请增加 TLS 和鉴权。

## 开发

```bash
# 信令服务器热重载（Node 18+）
cd server && npm run dev

# Flutter 分析
cd flutter_client && flutter analyze
```
