import AppKit
import UserNotifications

let stateFile = "/tmp/codex_traffic_light_state"
var currentState = "idle"
var lastWorkingStart: Date? = nil
var lastWorkingDuration: TimeInterval? = nil
var yellowStart: Date? = nil

// MARK: - 绘制

func makeTrafficLightImage(active: String) -> NSImage {
    let w: CGFloat = 60, h: CGFloat = 22
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()
    let housing = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: w - 2, height: h - 4), xRadius: 5, yRadius: 5)
    NSColor(white: 0.15, alpha: 1).setFill(); housing.fill()
    let inner = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: w - 6, height: h - 8), xRadius: 3, yRadius: 3)
    NSColor(white: 0.1, alpha: 1).setFill(); inner.fill()
    let now: CGFloat = CGFloat(Date().timeIntervalSince1970)
    let colors: [(String, NSColor)] = [
        ("working", NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)),
        ("input",   NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)),
        ("idle",    NSColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)),
    ]
    let r: CGFloat = 6, centers: [CGFloat] = [12, 30, 48]
    for (i, centerX) in centers.enumerated() {
        let (state, bright) = colors[i], isActive = state == active, color = bright
        let cx = centerX, cy: CGFloat = h / 2
        let socket = NSBezierPath(ovalIn: NSRect(x: cx - r - 1.5, y: cy - r - 1.5, width: (r+1.5)*2, height: (r+1.5)*2))
        NSColor(white: 0.05, alpha: 1).setFill(); socket.fill()
        if isActive {
            let k: CGFloat = active == "working" ? 0.6+0.4*(sin(now*2.5)+1)/2 : active == "input" ? 0.2+0.8*abs(sin(now*5.0)) : 1.0
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

func stateLabel(_ s: String) -> String {
    switch s { case "working": return "思考中"; case "input": return "需要确认"; default: return "空闲" }
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

func threadNameFromIndex() -> String? {
    guard let threadId = sqliteQuery("SELECT id FROM threads WHERE archived=0 ORDER BY updated_at_ms DESC LIMIT 1") else {
        return nil
    }
    let indexPath = NSHomeDirectory() + "/.codex/session_index.jsonl"
    guard let content = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return nil }
    let lines = content.components(separatedBy: "\n")
    for line in lines {
        if line.contains("\"id\":\"\(threadId)\"") || line.contains("\"id\": \"\(threadId)\"") {
            if let r = line.range(of: "\"thread_name\":\"") {
                let start = r.upperBound
                if let end = line[start...].firstIndex(of: "\"") {
                    return String(line[start..<end])
                }
            }
        }
    }
    return nil
}

func threadDisplayName() -> String? {
    if let name = threadNameFromIndex(), !name.isEmpty { return name }
    if let name = sqliteQuery("SELECT agent_nickname FROM threads WHERE archived=0 AND agent_nickname IS NOT NULL ORDER BY updated_at_ms DESC LIMIT 1"),
       !name.isEmpty { return name }
    return sqliteQuery("SELECT title FROM threads WHERE archived=0 ORDER BY updated_at_ms DESC LIMIT 1")
}

func openCodex() {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"),
                                        configuration: NSWorkspace.OpenConfiguration())
}

func buildMenu() -> NSMenu {
    let menu = NSMenu()
    let t: String
    if currentState == "idle", let d = lastWorkingDuration { t = "空闲 · 上次思考 \(formatDuration(d))" }
    else { t = stateLabel(currentState) }
    let h = NSMenuItem(title: t, action: nil, keyEquivalent: ""); h.isEnabled = false; menu.addItem(h)
    menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(AppDelegate.openCodexAction), keyEquivalent: ""))
    menu.addItem(.separator())
    if let name = threadDisplayName() {
        let d = name.count > 28 ? String(name.prefix(28)) + "..." : name
        let item = NSMenuItem(title: d, action: nil, keyEquivalent: ""); item.isEnabled = false; item.toolTip = name
        menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    return menu
}

func updateMenu() {
    item.menu = buildMenu()
    item.button?.toolTip = currentState == "idle" && lastWorkingDuration != nil
        ? "上次思考 \(formatDuration(lastWorkingDuration!))" : stateLabel(currentState)
}

// MARK: - 黄灯通知（每 8 秒重复弹，直到处理）

var lastYellowNotifyTime: Date = Date(timeIntervalSince1970: 0)

func sendYellowNotification() {
    let c = UNMutableNotificationContent()
    c.title = "Codex 需要你的确认"
    c.body = "点击此通知打开 Codex"
    c.sound = .default
    c.categoryIdentifier = "YELLOW"
    // 用不同 identifier 确保每次都是新通知（否则系统会合并）
    let id = "codex-yellow-\(Int(Date().timeIntervalSince1970))"
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    // 清除旧通知
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        let old = notifications.filter { $0.request.identifier.hasPrefix("codex-yellow-") }
            .map { $0.request.identifier }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(old.prefix(old.count - 1)))
    }
}

func readStateFile() -> String {
    (try? String(contentsOfFile: stateFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "idle"
}

func tick() {
    let raw = readStateFile()
    var state = raw
    if state == "input",
       sqliteQuery("SELECT id FROM threads WHERE has_user_event=1 AND archived=0 LIMIT 1") == nil {
        state = "idle"
    }
    let changed = state != currentState
    currentState = state
    if state == "working" { if lastWorkingStart == nil { lastWorkingStart = Date() } }
    else { if let s = lastWorkingStart { lastWorkingDuration = Date().timeIntervalSince(s); lastWorkingStart = nil } }
    
    // 黄灯：每 8 秒重复弹通知，不主动消失
    if state == "input" {
        if yellowStart == nil { yellowStart = Date(); lastYellowNotifyTime = Date(timeIntervalSince1970: 0) }
        if Date().timeIntervalSince(lastYellowNotifyTime) > 8 {
            sendYellowNotification()
            lastYellowNotifyTime = Date()
        }
    } else {
        yellowStart = nil
        // 退出黄灯时清掉所有黄灯通知
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let ids = notifications.filter { $0.request.identifier.hasPrefix("codex-yellow-") }
                .map { $0.request.identifier }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    if changed { DispatchQueue.main.async { updateMenu() } }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        if let iconPath = Bundle.main.path(forResource: "CodexTrafficLight", ofType: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
        }
        let c = UNUserNotificationCenter.current(); c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler h: @escaping () -> Void) {
        if r.notification.request.content.categoryIdentifier == "YELLOW" {
            // 点击黄灯通知 → 打开 Codex + 清掉所有黄灯通知
            c.removeAllDeliveredNotifications()
            openCodex()
        }
        h()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }
    @objc func openCodexAction() { openCodex() }
}

let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
item.length = 62
item.button?.image = makeTrafficLightImage(active: "idle")
item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
updateMenu()

Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    DispatchQueue.main.async { item.button?.image = makeTrafficLightImage(active: currentState) }
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tick() }

app.run()
