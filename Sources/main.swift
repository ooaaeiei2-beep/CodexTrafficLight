import AppKit
import UserNotifications

let debugLog = "/tmp/traffic_light_debug.log"

var lastWorkingStart: Date? = nil
var lastWorkingDuration: TimeInterval? = nil
var yellowStart: Date? = nil
var yellowNotified = false
var desktopOverlayRunning = false
let appStartTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
var idleFlashStart: Date? = nil
let idleFlashDuration: TimeInterval = 3.0

enum LightState: String {
    case green, yellow, red, redFlash
}

let overlayStateFile = "/tmp/codex_traffic_light_overlay_state"

var lightState: LightState = .red {
    didSet {
        if lightState != oldValue {
            DispatchQueue.main.async { updateMenu() }
            try? lightState.rawValue.write(toFile: overlayStateFile, atomically: true, encoding: .utf8)
        }
    }
}

func log(_ msg: String) {
    let line = ISO8601DateFormatter().string(from: Date()) + " " + msg + "\n"
    if let fh = FileHandle(forWritingAtPath: debugLog) {
        fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close()
    } else { try? line.write(toFile: debugLog, atomically: true, encoding: .utf8) }
}

// MARK: - State Reading (hooks)

func readPerThreadStates() -> [String: String] {
    var states: [String: String] = [:]
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else { return states }
    for file in files {
        guard file.hasPrefix("codex_tl_"), !file.hasSuffix("_approval") else { continue }
        let tid = String(file.dropFirst("codex_tl_".count))
        if let content = try? String(contentsOfFile: "/tmp/\(file)", encoding: .utf8) {
            states[tid] = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return states
}

func allActiveThreads() -> [(id: String, updated: Int64, path: String, cwd: String)] {
    let db = NSHomeDirectory() + "/.codex/state_5.sqlite"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = ["-readonly", db, "SELECT id, updated_at_ms, rollout_path, cwd FROM threads WHERE archived=0"]
    let pipe = Pipe(); p.standardOutput = pipe
    do { try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let out = out {
            var threads: [(String, Int64, String, String)] = []
            for line in out.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 4, let updated = Int64(parts[1]), !parts[2].isEmpty {
                    threads.append((parts[0], updated, parts[2], parts.count >= 4 ? parts[3] : ""))
                }
            }
            return threads
        }
    } catch {}
    return []
}

func hasApprovalFlag(_ tid: String) -> Bool {
    FileManager.default.fileExists(atPath: "/tmp/codex_tl_\(tid)_approval")
}

func approvalFlagAge(_ tid: String) -> TimeInterval? {
    let path = "/tmp/codex_tl_\(tid)_approval"
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mdate = attrs[.modificationDate] as? Date else { return nil }
    return Date().timeIntervalSince(mdate)
}

func isManualApproval(_ path: String) -> Bool {
    // Returns true only if this is a MANUAL (not auto) approval
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }

    // Auto: approvals_reviewer = auto_review
    if content.contains("approvals_reviewer") && content.contains("auto_review") { return false }

    // Auto: prefix_rule in escalated call
    var found = false
    for line in content.components(separatedBy: "\n").reversed() {
        if line.contains("\"type\":\"task_complete\"") { break }
        if line.contains("\"type\":\"function_call\"") && line.contains("require_escalated") {
            if found { continue }
            found = true
            return !line.contains("prefix_rule")
        }
    }
    return false
}

func hookFileMtime(_ tid: String) -> Int64 {
    let path = "/tmp/codex_tl_\(tid)"
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mdate = attrs[.modificationDate] as? Date else { return 0 }
    return Int64(mdate.timeIntervalSince1970 * 1000)
}

func computeLightState() {
    let perThread = readPerThreadStates()
    let allThreads = allActiveThreads()
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

    var hasWorking = false
    var hasManualApproval = false

    for t in allThreads {
        let hookState = perThread[t.id]

        // Working: hook says working or input, use hook file mtime for recency
        let hookMtime = hookFileMtime(t.id)
        let recentHook = hookMtime > 0 && (nowMs - hookMtime) < 30000
        if (hookState == "working" || hookState == "input") && recentHook { hasWorking = true }

        // Manual approval check
        if hasApprovalFlag(t.id), let age = approvalFlagAge(t.id), age < 60 {
            if isManualApproval(t.path) {
                hasManualApproval = true
            }
        }
    }

    // Fallback: no hook data, use SQLite recency
    if perThread.isEmpty && allThreads.contains(where: { nowMs - $0.updated < 3000 }) {
        hasWorking = true
    }

    // Determine light
    if hasManualApproval {
        lightState = .yellow
        if yellowStart == nil { yellowStart = Date(); yellowNotified = false }
        else if !yellowNotified, let s = yellowStart, Date().timeIntervalSince(s) > 8 {
            sendYellowNotification(); yellowNotified = true
        }
    } else if hasWorking {
        lightState = .green
        yellowStart = nil; yellowNotified = false
        if lastWorkingStart == nil { lastWorkingStart = Date() }
    } else {
        // Red: was it previously active?
        let wasActive = lightState == .green || lightState == .yellow
        if wasActive {
            idleFlashStart = Date()
            if let s = lastWorkingStart { lastWorkingDuration = Date().timeIntervalSince(s); lastWorkingStart = nil }
        }
        if let start = idleFlashStart, Date().timeIntervalSince(start) < idleFlashDuration {
            lightState = .redFlash
        } else {
            lightState = .red
        }
        yellowStart = nil; yellowNotified = false
    }

    log("STATE: w=\(hasWorking) manual=\(hasManualApproval) -> \(lightState.rawValue)")
}

// MARK: - Traffic Light Drawing (3 lights)

func makeTrafficLightImage(state: LightState) -> NSImage {
    let w: CGFloat = 60, h: CGFloat = 22
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()

    // Housing
    let housing = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: w - 2, height: h - 4), xRadius: 5, yRadius: 5)
    NSColor(white: 0.15, alpha: 1).setFill(); housing.fill()
    let inner = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: w - 6, height: h - 8), xRadius: 3, yRadius: 3)
    NSColor(white: 0.1, alpha: 1).setFill(); inner.fill()

    let now: CGFloat = CGFloat(Date().timeIntervalSince1970)
    let r: CGFloat = 6, cy: CGFloat = h / 2
    let spacing: CGFloat = (w - 12) / 3
    let cxRed: CGFloat   = 8 + spacing * 0.5
    let cxYellow: CGFloat = 8 + spacing * 1.5
    let cxGreen: CGFloat  = 8 + spacing * 2.5

    let redColor    = NSColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)
    let yellowColor = NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)
    let greenColor  = NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)

    let lights: [(CGFloat, NSColor, Bool, (CGFloat) -> CGFloat)] = [
        (cxRed,    redColor,    state == .red || state == .redFlash,
         state == .redFlash ? { 0.2 + 0.8 * abs(sin($0 * 6.0)) } : { _ in 1.0 }),
        (cxYellow, yellowColor, state == .yellow,
         { 0.2 + 0.8 * abs(sin($0 * 5.0)) }),
        (cxGreen,  greenColor,  state == .green,
         { 0.6 + 0.4 * (sin($0 * 2.5) + 1) / 2 }),
    ]

    for (cx, color, isActive, animFn) in lights {
        // Socket
        let socket = NSBezierPath(ovalIn: NSRect(x: cx - r - 1.5, y: cy - r - 1.5, width: (r+1.5)*2, height: (r+1.5)*2))
        NSColor(white: 0.05, alpha: 1).setFill(); socket.fill()

        if isActive {
            let k = animFn(now)
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

// MARK: - Menu

func stateLabel() -> String {
    switch lightState {
    case .red, .redFlash:
        if let d = lastWorkingDuration { return "空闲 · 上次思考 \(formatDuration(d))" }
        return "空闲"
    case .green:  return "思考中"
    case .yellow: return "需要确认"
    }
}

func formatDuration(_ sec: TimeInterval) -> String {
    if sec < 60 { return String(format: "%.0f 秒", sec) }
    let m = Int(sec)/60, s = Int(sec)%60
    return s == 0 ? "\(m) 分" : "\(m) 分 \(s) 秒"
}

func threadDisplayName() -> String? {
    let threads = allActiveThreads()
    let hookStates = readPerThreadStates()
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    var projects = Set<String>()
    for t in threads {
        if t.updated < appStartTimeMs && hookStates[t.id] == nil { continue }
        let recent = (nowMs - t.updated) < 30000
        let state = hookStates[t.id]
        guard (state == "working" || state == "input") && recent else { continue }
        if !t.cwd.isEmpty {
            projects.insert((t.cwd as NSString).lastPathComponent)
        }
    }
    if projects.isEmpty { return nil }
    let joined = projects.sorted().joined(separator: " + ")
    return joined.count > 14 ? String(joined.prefix(14)) + "..." : joined
}

func openCodex() {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
}

func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: stateLabel(), action: nil, keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(AppDelegate.openCodexAction), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    return menu
}

var statusItem: NSStatusItem!

func updateMenu() {
    statusItem.menu = buildMenu()
    let tip: String
    if (lightState == .red || lightState == .redFlash), let d = lastWorkingDuration {
        tip = "上次思考 \(formatDuration(d))"
    } else {
        tip = stateLabel()
    }
    statusItem.button?.toolTip = tip
}

func sendYellowNotification() {
    let c = UNMutableNotificationContent(); c.title = "Codex 需要你的确认"; c.body = "点击此通知打开 Codex"; c.sound = .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "codex-yellow", content: c, trigger: nil))
}

let overlayPath = NSHomeDirectory() + "/Documents/学习引导/CodexTrafficLight/DesktopOverlay/DesktopOverlay"

func toggleDesktopOverlay() {
    if desktopOverlayRunning {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["DesktopOverlay"]; try? p.run(); p.waitUntilExit(); desktopOverlayRunning = false
    } else {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "nohup '\(overlayPath)' >/dev/null 2>&1 &"]; try? p.run(); desktopOverlayRunning = true
    }
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

log("=== COLD START (v5.0 - 3 lights) ===")
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.length = 64
statusItem.button?.image = makeTrafficLightImage(state: .red)
statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp]); updateMenu()
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in DispatchQueue.main.async { statusItem.button?.image = makeTrafficLightImage(state: lightState) } }
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in computeLightState() }
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in log("HEALTH: light=\(lightState.rawValue)") }
app.run()
