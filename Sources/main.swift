import AppKit
import UserNotifications

let debugLog = "/tmp/traffic_light_debug.log"
var activeLights: Set<String> = ["idle"]
var lastWorkingStart: Date? = nil
var lastWorkingDuration: TimeInterval? = nil
var yellowStart: Date? = nil
var yellowNotified = false
var desktopOverlayRunning = false

let appStartTimeMs = Int64(Date().timeIntervalSince1970 * 1000)

func log(_ msg: String) {
    let line = ISO8601DateFormatter().string(from: Date()) + " " + msg + "\n"
    if let fh = FileHandle(forWritingAtPath: debugLog) {
        fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close()
    } else { try? line.write(toFile: debugLog, atomically: true, encoding: .utf8) }
}

func makeTrafficLightImage(active: Set<String>) -> NSImage {
    let w: CGFloat = 78, h: CGFloat = 22
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()
    let housing = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: w - 2, height: h - 4), xRadius: 5, yRadius: 5)
    NSColor(white: 0.15, alpha: 1).setFill(); housing.fill()
    let inner = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: w - 6, height: h - 8), xRadius: 3, yRadius: 3)
    NSColor(white: 0.1, alpha: 1).setFill(); inner.fill()
    let now: CGFloat = CGFloat(Date().timeIntervalSince1970)
    let configs: [(String, NSColor)] = [
        ("working",    NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)),
        ("input",      NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)),
        ("auto_review",NSColor(red: 0.1, green: 0.4,  blue: 1.0, alpha: 1)),
        ("idle",       NSColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)),
    ]
    let r: CGFloat = 6, spacing: CGFloat = (w - 12) / 4
    let centers: [CGFloat] = [8 + spacing*0.5, 8 + spacing*1.5, 8 + spacing*2.5, 8 + spacing*3.5]
    let isPartial = active.contains("partial")
    for (i, centerX) in centers.enumerated() {
        let (state, bright) = configs[i], color = bright
        let isActive: Bool = state == "idle" ? (active.contains("idle") || isPartial) : active.contains(state)
        let cx = centerX, cy: CGFloat = h / 2
        let socket = NSBezierPath(ovalIn: NSRect(x: cx - r - 1.5, y: cy - r - 1.5, width: (r+1.5)*2, height: (r+1.5)*2))
        NSColor(white: 0.05, alpha: 1).setFill(); socket.fill()
        if isActive {
            let k: CGFloat
            if state == "working"     { k = 0.6 + 0.4 * (sin(now * 2.5) + 1) / 2 }
            else if state == "input"  { k = 0.2 + 0.8 * abs(sin(now * 5.0)) }
            else if state == "auto_review" { k = 0.3 + 0.7 * abs(sin(now * 4.0)) }
            else if isPartial         { k = 0.2 + 0.8 * abs(sin(now * 6.0)) }
            else { k = 1.0 }
            for (off, ba): (CGFloat, CGFloat) in [(4.5,0.08),(3.5,0.06),(3.0,0.04),(2.0,0.03),(1.5,0.02)] {
                let g = NSBezierPath(ovalIn: NSRect(x: cx-r-off, y: cy-r-off, width: (r+off)*2, height: (r+off)*2))
                color.withAlphaComponent(ba*k).setFill(); g.fill()
            }
            let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            color.withAlphaComponent(k).setFill(); c.fill()
            let hl = NSBezierPath(ovalIn: NSRect(x: cx-2.5, y: cy-2, width: 3, height: 3))
            NSColor.white.withAlphaComponent(0.35*k).setFill(); hl.fill()
        } else {
            let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            color.withAlphaComponent(0.15).setFill(); c.fill()
        }
    }
    img.unlockFocus(); return img
}

func stateLabel(_ active: Set<String>) -> String {
    if active.contains("partial") { return "部分空闲" }
    if active.contains("idle"), let d = lastWorkingDuration { return "空闲 · 上次思考 \(formatDuration(d))" }
    var parts: [String] = []
    if active.contains("working")     { parts.append("思考中") }
    if active.contains("input")       { parts.append("需要确认") }
    if active.contains("auto_review") { parts.append("自动审批") }
    if parts.isEmpty                  { parts.append("空闲") }
    return parts.joined(separator: " + ")
}

func formatDuration(_ sec: TimeInterval) -> String {
    if sec < 60 { return String(format: "%.0f 秒", sec) }
    let m = Int(sec)/60, s = Int(sec)%60
    return s == 0 ? "\(m) 分" : "\(m) 分 \(s) 秒"
}

func sqliteQuery(_ sql: String) -> String? {
    let db = NSHomeDirectory() + "/.codex/state_5.sqlite"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = ["-readonly", db, sql]
    let pipe = Pipe(); p.standardOutput = pipe
    do { try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let out = out, !out.isEmpty { return out }
    } catch {}
    return nil
}

func threadDisplayName() -> String? {
    guard let threadId = sqliteQuery("SELECT id FROM threads WHERE archived=0 ORDER BY updated_at_ms DESC LIMIT 1") else { return nil }
    let indexPath = NSHomeDirectory() + "/.codex/session_index.jsonl"
    guard let content = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return nil }
    for line in content.components(separatedBy: "\n") {
        if line.contains("\"id\":\"\(threadId)\"") || line.contains("\"id\": \"\(threadId)\"") {
            if let r = line.range(of: "\"thread_name\":\"") {
                let start = r.upperBound; if let end = line[start...].firstIndex(of: "\"") { return String(line[start..<end]) }
            }
        }
    }
    if let name = sqliteQuery("SELECT agent_nickname FROM threads WHERE archived=0 AND agent_nickname IS NOT NULL ORDER BY updated_at_ms DESC LIMIT 1"), !name.isEmpty { return name }
    return sqliteQuery("SELECT title FROM threads WHERE archived=0 ORDER BY updated_at_ms DESC LIMIT 1")
}

func openCodex() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration()) }

// MARK: - 方案C

func readPerThreadStates() -> [String: String] {
    var states: [String: String] = [:]
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else { return states }
    for file in files {
        guard file.hasPrefix("codex_tl_") else { continue }
        let tid = String(file.dropFirst("codex_tl_".count))
        if let content = try? String(contentsOfFile: "/tmp/\(file)", encoding: .utf8) {
            states[tid] = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return states
}

func allActiveThreads() -> [(id: String, updated: Int64, path: String)] {
    guard let result = sqliteQuery("SELECT id, updated_at_ms, rollout_path FROM threads WHERE archived=0") else { return [] }
    var threads: [(String, Int64, String)] = []
    for line in result.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: "|")
        if parts.count >= 3, let updated = Int64(parts[1]), !parts[2].isEmpty {
            threads.append((parts[0], updated, parts[2]))
        }
    }
    return threads
}

// 只看当前回合最后一条 escalated call：有 prefix_rule → 自动审批
func lastEscalatedIsAuto(_ path: String) -> Bool? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    var found = false
    for line in content.components(separatedBy: "\n").reversed() {
        if line.contains("\"type\":\"task_complete\"") { break }
        if line.contains("\"type\":\"function_call\"") && line.contains("require_escalated") {
            if found { continue }
            found = true
            return line.contains("prefix_rule")
        }
    }
    return nil  // 没有 escalated call
}

func aggregateState() -> (working: Bool, input: Bool, auto: Bool, hasIdle: Bool) {
    let perThread = readPerThreadStates(), allThreads = allActiveThreads()
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    var hasWorking = false, hasInput = false, hasAuto = false, hasIdle = false

    for t in allThreads {
        if t.updated < appStartTimeMs { continue }
        let recent = (nowMs - t.updated) < 30000
        let hookState = perThread[t.id]

        if (hookState == "working" || hookState == "input") && recent { hasWorking = true }

        // 黄灯：per-thread 为 input 时，查 rollout 确认是否真的人工审批
        if hookState == "input" && recent {
            if let isAuto = lastEscalatedIsAuto(t.path) {
                // 最后一条 escalated call 有 prefix_rule → 自动 → 不亮黄
                // 没有 prefix_rule → 人工 → 亮黄
                if !isAuto { hasInput = true }
            }
        }

        // 蓝灯：per-thread 为 working 时，查最后一条 escalated call 是否自动
        if hookState == "working" && recent {
            if let isAuto = lastEscalatedIsAuto(t.path), isAuto {
                hasAuto = true
            }
        }

        if !recent && hookState != "working" && hookState != "input" { hasIdle = true }
    }

    if perThread.isEmpty { hasWorking = allThreads.contains(where: { nowMs - $0.updated < 3000 }) }
    return (hasWorking, hasInput, hasAuto, hasIdle)
}

// MARK: - 桌面悬浮

let overlayPath = NSHomeDirectory() + "/Documents/学习引导/CodexTrafficLight/DesktopOverlay/DesktopOverlay"

func toggleDesktopOverlay() {
    if desktopOverlayRunning {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["DesktopOverlay"]; try? p.run(); p.waitUntilExit()
        desktopOverlayRunning = false
    } else {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "nohup '\(overlayPath)' >/dev/null 2>&1 &"]
        try? p.run(); desktopOverlayRunning = true
    }
}

func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: stateLabel(activeLights), action: nil, keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(AppDelegate.openCodexAction), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: desktopOverlayRunning ? "✓ 桌面悬浮" : "桌面悬浮", action: #selector(AppDelegate.toggleOverlayAction), keyEquivalent: ""))
    menu.addItem(.separator())
    if let name = threadDisplayName() { menu.addItem(NSMenuItem(title: name.count > 28 ? String(name.prefix(28))+"..." : name, action: nil, keyEquivalent: "")) }
    menu.addItem(.separator()); menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    return menu
}

func updateMenu() { item.menu = buildMenu(); item.button?.toolTip = activeLights.contains("idle") && lastWorkingDuration != nil ? "上次思考 \(formatDuration(lastWorkingDuration!))" : stateLabel(activeLights) }

func sendYellowNotification() {
    let c = UNMutableNotificationContent(); c.title = "Codex 需要你的确认"; c.body = "点击此通知打开 Codex"; c.sound = .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "codex-yellow", content: c, trigger: nil))
}

func tick() {
    let (isWorking, isInput, isAuto, isIdle) = aggregateState()
    var lights = Set<String>()
    if isWorking { lights.insert("working") }
    if isInput   { lights.insert("input") }
    if isAuto    { lights.insert("auto_review") }
    if isWorking && isIdle { lights.insert("partial") }
    else if lights.isEmpty { lights.insert("idle") }
    log("w=\(isWorking) i=\(isInput) a=\(isAuto) d=\(isIdle) -> \(lights.sorted().joined(separator: "+"))")
    let changed = lights != activeLights; activeLights = lights
    if lights.contains("working") || lights.contains("auto_review") { if lastWorkingStart == nil { lastWorkingStart = Date() } }
    else { if let s = lastWorkingStart { lastWorkingDuration = Date().timeIntervalSince(s); lastWorkingStart = nil } }
    if lights.contains("input") { if yellowStart == nil { yellowStart = Date(); yellowNotified = false } else if !yellowNotified, let s = yellowStart, Date().timeIntervalSince(s) > 8 { sendYellowNotification(); yellowNotified = true } }
    else { yellowStart = nil; yellowNotified = false }
    if changed { DispatchQueue.main.async { updateMenu() } }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        if let iconPath = Bundle.main.path(forResource: "CodexTrafficLight", ofType: "icns") { NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath) }
        let c = UNUserNotificationCenter.current(); c.delegate = self; c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) { openCodex(); h() }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }
    @objc func openCodexAction() { openCodex() }
    @objc func toggleOverlayAction() { toggleDesktopOverlay(); updateMenu() }
}

log("=== START ===")
let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); item.length = 80; item.button?.image = makeTrafficLightImage(active: ["idle"]); item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp]); updateMenu()
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in DispatchQueue.main.async { item.button?.image = makeTrafficLightImage(active: activeLights) } }
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tick() }
app.run()
