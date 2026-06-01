# Codex Traffic Light 🚦

macOS 菜单栏红绿灯，通过 Codex hooks 实时显示 Codex 工作状态。

![screenshot](https://img.shields.io/badge/platform-macOS%2015%2B-blue) ![swift](https://img.shields.io/badge/swift-6.0%2B-orange)

## 效果

| 状态 | 灯光 | 说明 |
|---|---|---|
| 思考中 | 🟢 绿灯呼吸 | Codex 正在处理请求 |
| 需要确认 | 🟡 黄灯急闪 + 8s 通知 | Codex 等待审批 |
| 空闲 | 🔴 红灯常亮 | Codex 回合结束 |

## 系统要求

| 依赖 | 版本 |
|---|---|
| macOS | 15.0+ |
| Xcode Command Line Tools | 16.0+（提供 `swiftc`） |
| Codex | 支持 hooks 的版本 |

验证环境：

```bash
swiftc --version   # Apple Swift version 6.0+
xcrun --show-sdk-path   # 存在即可
```

## 工作原理

核心思路借鉴了 [agent-light](https://github.com/eternityspring/agent-light) 的事件驱动模式：不轮询、不猜测，通过 Codex hooks 在特定生命周期事件发生时直接写入状态，Swift 状态栏 app 读取状态文件并渲染红绿灯。

```
Codex hooks 事件
  → traffic_light_hook.sh 写状态到 /tmp/codex_traffic_light_state
  → Swift 状态栏 app 读取状态文件 + 渲染红绿灯
```

## Hook 事件映射

Codex hooks 配置完全参考了 [codex-lamp](https://github.com/loopbrew/codex-lamp) 的 hooks.json 格式和事件映射方案：

| Codex 事件 | 写入状态 | 含义 |
|---|---|---|
| `UserPromptSubmit` | `working` | 用户发消息 |
| `PreToolUse` | `working` | 执行工具前 |
| `PostToolUse` | `working` | 工具执行完 |
| `PermissionRequest` | `input` | 等待审批 |
| `Stop` | `idle` | 回合结束 |
| `SessionStart` | `idle` | 会话启动 |

## 功能清单

- 🟢 绿灯呼吸动画 — Codex 思考时缓慢明暗变化
- 🟡 黄灯急闪 + 8 秒后弹通知 — 提醒处理审批，点击通知打开 Codex
- 🔴 红灯常亮 + 显示上次思考时长 — 回合结束后展示耗时
- 📋 点击图标弹出菜单 — 显示当前线程名称、一键打开 Codex
- 🛡️ 黄灯安全兜底 — hooks 状态卡住时自动通过 SQLite 纠正

## 安装

### 1. 克隆

```bash
git clone https://github.com/ooaaeiei2-beep/CodexTrafficLight.git
cd CodexTrafficLight
```

### 2. 编译

```bash
./build.sh
```

编译产物：`../CodexTrafficLight.app`

### 3. 配置 Codex hooks

替换路径占位符并复制配置文件：

```bash
sed -i '' "s|REPO_DIR|$(pwd)|g" hooks.json
cp hooks.json ~/.codex/hooks.json
```

在 `~/.codex/config.toml` 的 `[features]` 中加入：

```toml
[features]
hooks = true
```

重启 Codex 使 hooks 生效。

### 4. 初始化状态文件

```bash
echo "idle" > /tmp/codex_traffic_light_state
```

### 5. 启动

```bash
killall CodexTrafficLight 2>/dev/null; sleep 1
nohup ~/Documents/学习引导/CodexTrafficLight.app/Contents/MacOS/CodexTrafficLight > /dev/null 2>&1 &
```

如需开机自启，在「系统设置 → 通用 → 登录项」中添加该二进制。

## 项目结构

```
CodexTrafficLight/
├── Sources/main.swift          # Swift 状态栏 app 源码
├── hooks.json                  # Codex hooks 配置（含 REPO_DIR 占位符）
├── traffic_light_hook.sh       # Hook 脚本，写状态文件
├── build.sh                    # 编译脚本
├── CodexTrafficLight.icns      # App 图标
└── README.md
```

## 手动测试

```bash
echo "working" > /tmp/codex_traffic_light_state   # 模拟绿灯
echo "input"   > /tmp/codex_traffic_light_state   # 模拟黄灯（8 秒后弹通知）
echo "idle"    > /tmp/codex_traffic_light_state   # 模拟红灯
```

## 致谢

本项目深受以下两个优秀项目的启发，特别是 Codex hooks 的配置格式和事件映射方案：

- **[eternityspring/agent-light](https://github.com/eternityspring/agent-light)** — 事件驱动的 Agent 状态指示灯方案，确立了「不轮询、不猜测，通过 hooks 直接获取状态」的核心思路。
- **[loopbrew/codex-lamp](https://github.com/loopbrew/codex-lamp)** — Codex 物理灯项目，提供了完整的 hooks.json 配置格式、状态文件通信模式，以及 `PermissionRequest` 等关键 hook 事件的使用示范。

## License

MIT
