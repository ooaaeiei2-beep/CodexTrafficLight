# 🚦 CodexTrafficLight

macOS 状态栏红绿灯，实时监控 Codex 工作状态，让你一眼知道 AI 在干什么。

| 🟢 绿灯缓呼吸 | 🟡 黄灯急闪 | 🔴 红灯 |
|---|---|---|
| Codex 思考中 | 需要人工审批 | 空闲（任务结束闪 3 秒） |

## 安装

1. 从 [Releases](https://github.com/ooaaeiei2-beep/CodexTrafficLight/releases) 下载最新 DMG
2. 双击挂载，将 `CodexTrafficLight.app` 拖到 `/Applications`
3. 首次打开右键 → 「打开」绕过 Gatekeeper
4. 状态栏出现红绿灯 🚦

## 工作原理

通过 Codex Hooks 监控线程状态，区分自动审批和人工审批：

- `UserPromptSubmit` / `PreToolUse` → 绿灯
- `PermissionRequest` + 无人前缀规则 → 黄灯
- `Stop` / `SessionStart` → 红灯

## 环境要求

- macOS 15+
- Codex Desktop app 运行中
- Codex Hooks 已配置（见下方）

## Hooks 配置

将以下内容放入 `~/.codex/hooks.json`：

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh idle" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh working" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh working" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh working" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh input" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "~/Documents/学习引导/traffic_light_hook.sh idle" }] }]
  }
}
```

## 构建

```bash
bash make_dmg.sh
```

## 致谢

灵感来源于：
- [eternityspring/agent-light](https://github.com/eternityspring/agent-light) — Claude Code 物理红绿灯
- [loopbrew/codex-lamp](https://github.com/loopbrew/codex-lamp) — Codex 蓝牙灯方案
- 感谢以上两位作者在 Hooks 监控方案上的先行探索

## 许可

MIT
