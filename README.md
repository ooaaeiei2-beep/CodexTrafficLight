# Codex Traffic Light 🚦

macOS 状态栏红绿灯，实时显示 Codex 的工作状态。

## 效果

| 状态 | 灯光 | 说明 |
|---|---|---|
| 思考中 | 🟢 绿灯呼吸 | Codex 正在处理你的请求 |
| 需要确认 | 🟡 黄灯闪烁 + 通知 | Codex 在等你确认 |
| 空闲 | 🔴 红灯常亮 | Codex 已结束当前回合 |

## 工作原理

```
Codex hooks ──> traffic_light_hook.sh ──> /tmp/codex_traffic_light_state
                                                  │
Swift 状态栏 app 每秒读取 ─────────────────────────┘
```

纯 hooks 事件驱动，不轮询、不猜测。

## 安装

### 1. 编译

```bash
./build.sh
```

### 2. 配置 Codex hooks

```bash
cp hooks.json ~/.codex/hooks.json
```

在 `~/.codex/config.toml` 的 `[features]` 中加入：

```toml
[features]
hooks = true
```

### 3. 启动

```bash
killall CodexTrafficLight 2>/dev/null; sleep 1
nohup ~/Documents/学习引导/CodexTrafficLight.app/Contents/MacOS/CodexTrafficLight > /dev/null 2>&1 &
```

## 功能

- 🟢 绿灯呼吸动画 — 余光能感知 Codex 在跑
- 🟡 黄灯 8 秒后弹通知 — 提醒你 Codex 需要确认
- 🔴 红灯显示「上次思考时长」— 知道 Codex 干了多久
- 📋 点击图标弹出菜单 — 看当前对话、一键打开 Codex

## 文件

| 文件 | 说明 |
|---|---|
| `Sources/main.swift` | Swift 状态栏 app 源码 |
| `hooks.json` | Codex hooks 配置 |
| `traffic_light_hook.sh` | Hook 脚本，写状态文件 |
| `build.sh` | 编译脚本 |
