import AppKit

let stateFile = "/tmp/codex_traffic_light_overlay_state"
let defaultSize: CGFloat = 66
let minSize: CGFloat = 44
let maxSize: CGFloat = 200

var currentSize: CGFloat = defaultSize
var currentState = "red"

class TrafficOverlayView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let housing = NSBezierPath(roundedRect: NSRect(x: 4, y: 6, width: w - 8, height: h - 12), xRadius: 14, yRadius: 14)
        NSColor(white: 0.15, alpha: 1).setFill(); housing.fill()
        let inner = NSBezierPath(roundedRect: NSRect(x: 10, y: 12, width: w - 20, height: h - 24), xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 1).setFill(); inner.fill()

        let now: CGFloat = CGFloat(Date().timeIntervalSince1970)
        let r: CGFloat = h * 0.27, cy: CGFloat = h / 2
        let cxRed: CGFloat   = w * 0.18
        let cxYellow: CGFloat = w * 0.5
        let cxGreen: CGFloat  = w * 0.82

        let redColor    = NSColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)
        let yellowColor = NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)
        let greenColor  = NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)

        let lights: [(CGFloat, NSColor, Bool, (CGFloat) -> CGFloat)] = [
            (cxRed,    redColor,    currentState == "red" || currentState == "redFlash",
             currentState == "redFlash" ? { 0.2 + 0.8 * abs(sin($0 * 6.0)) } : { _ in 1.0 }),
            (cxYellow, yellowColor, currentState == "yellow",
             { 0.2 + 0.8 * abs(sin($0 * 5.0)) }),
            (cxGreen,  greenColor,  currentState == "green",
             { 0.6 + 0.4 * (sin($0 * 2.5) + 1) / 2 }),
        ]

        for (cx, color, isActive, animFn) in lights {
            let socket = NSBezierPath(ovalIn: NSRect(x: cx - r - 2, y: cy - r - 2, width: (r+2)*2, height: (r+2)*2))
            NSColor(white: 0.05, alpha: 1).setFill(); socket.fill()
            if isActive {
                let k = animFn(now)
                let glowSteps: [(CGFloat, CGFloat)] = [(r*0.8,0.06),(r*0.6,0.05),(r*0.4,0.04),(r*0.25,0.03)]
                for (off, ba) in glowSteps {
                    let g = NSBezierPath(ovalIn: NSRect(x: cx-r-off, y: cy-r-off, width: (r+off)*2, height: (r+off)*2))
                    color.withAlphaComponent(ba*k).setFill(); g.fill()
                }
                let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
                color.withAlphaComponent(k).setFill(); c.fill()
                let hl = NSBezierPath(ovalIn: NSRect(x: cx-r*0.4, y: cy-r*0.3, width: r*0.5, height: r*0.5))
                NSColor.white.withAlphaComponent(0.35*k).setFill(); hl.fill()
            } else {
                let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
                color.withAlphaComponent(0.12).setFill(); c.fill()
            }
        }
    }
}

func resizeWindow(to size: CGFloat) {
    let clamped = max(minSize, min(maxSize, size))
    currentSize = clamped
    guard let w = NSApp.windows.first else { return }
    let aspect: CGFloat = 3.0
    let newFrame = NSRect(x: w.frame.origin.x, y: w.frame.origin.y, width: clamped * aspect, height: clamped)
    w.setFrame(newFrame, display: true)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let initialWidth: CGFloat = defaultSize * 3.0
let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: initialWidth, height: defaultSize),
    styleMask: [.borderless, .nonactivatingPanel, .resizable],
    backing: .buffered, defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isMovableByWindowBackground = true
window.title = "Codex Traffic Light"
window.contentMinSize = NSSize(width: minSize * 3.0, height: minSize)
window.contentMaxSize = NSSize(width: maxSize * 3.0, height: maxSize)
window.makeKeyAndOrderFront(nil)

let view = TrafficOverlayView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: defaultSize))
window.contentView = view

// Resize observer
NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
    currentSize = window.frame.height
    view.needsDisplay = true
}

// State poll timer
Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
    let newState = (try? String(contentsOfFile: stateFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "red"
    if newState != currentState {
        currentState = newState
        DispatchQueue.main.async { view.needsDisplay = true }
    }
}

// Animation timer
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    if currentState == "green" || currentState == "yellow" || currentState == "redFlash" {
        DispatchQueue.main.async { view.needsDisplay = true }
    }
}

app.run()
