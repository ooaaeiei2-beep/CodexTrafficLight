import AppKit

let stateFile = "/tmp/codex_traffic_light_state"

class DraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
}

func makeTrafficLightImage(active: String, w: CGFloat = 180, h: CGFloat = 66) -> NSImage {
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()
    let housing = NSBezierPath(roundedRect: NSRect(x: 4, y: 6, width: w - 8, height: h - 12), xRadius: 14, yRadius: 14)
    NSColor(white: 0.15, alpha: 1).setFill(); housing.fill()
    let inner = NSBezierPath(roundedRect: NSRect(x: 10, y: 12, width: w - 20, height: h - 24), xRadius: 8, yRadius: 8)
    NSColor(white: 0.1, alpha: 1).setFill(); inner.fill()
    let now: CGFloat = CGFloat(Date().timeIntervalSince1970)
    let colors: [(String, NSColor)] = [
        ("working", NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)),
        ("input",   NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)),
        ("idle",    NSColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)),
    ]
    let r: CGFloat = 18, spacing: CGFloat = (w - 20) / 3
    let centers: [CGFloat] = [10 + spacing/2, 10 + spacing*1.5, 10 + spacing*2.5]
    for (i, centerX) in centers.enumerated() {
        let (state, bright) = colors[i], isActive = state == active, color = bright
        let cx = centerX, cy: CGFloat = h / 2
        let socket = NSBezierPath(ovalIn: NSRect(x: cx - r - 4, y: cy - r - 4, width: (r+4)*2, height: (r+4)*2))
        NSColor(white: 0.05, alpha: 1).setFill(); socket.fill()
        if isActive {
            let k: CGFloat = active == "working" ? 0.6+0.4*(sin(now*2.5)+1)/2 : active == "input" ? 0.2+0.8*abs(sin(now*5.0)) : 1.0
            for (off, ba): (CGFloat, CGFloat) in [(14,0.06),(10,0.05),(7,0.04),(5,0.03),(3,0.02)] {
                let g = NSBezierPath(ovalIn: NSRect(x: cx-r-off, y: cy-r-off, width: (r+off)*2, height: (r+off)*2))
                color.withAlphaComponent(ba*k).setFill(); g.fill()
            }
            let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            color.withAlphaComponent(k).setFill(); c.fill()
            let hl = NSBezierPath(ovalIn: NSRect(x: cx-7, y: cy-5, width: 8, height: 8))
            NSColor.white.withAlphaComponent(0.35*k).setFill(); hl.fill()
        } else {
            let c = NSBezierPath(ovalIn: NSRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            color.withAlphaComponent(0.12).setFill(); c.fill()
        }
    }
    img.unlockFocus(); return img
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 200, height: 80),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isMovableByWindowBackground = true
window.makeKeyAndOrderFront(nil)

let imageView = DraggableImageView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
window.contentView?.addSubview(imageView)
imageView.image = makeTrafficLightImage(active: "idle")

Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let state = (try? String(contentsOfFile: stateFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "idle"
    DispatchQueue.main.async {
        imageView.image = makeTrafficLightImage(active: state)
    }
}

app.run()
