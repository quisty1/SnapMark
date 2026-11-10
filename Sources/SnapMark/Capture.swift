import AppKit
import ScreenCaptureKit
import SnapMarkCore

struct DisplaySnapshot {
    let display: SCDisplay
    let screen: NSScreen
    let image: CGImage
}
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var keyHandler: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

final class CaptureCoordinator {
    var panels: [KeyPanel] = []
    var snapshots: [DisplaySnapshot] = []
    var windows: [SCWindow] = []
    var windowMode = false
    var fullDisplay = false
    var onImage: ((CGImage, CGRect, DisplaySnapshot) -> Void)?
    var onCancel: (() -> Void)?
    var capturing = false
    func start(fullDisplay: Bool = false, windowMode: Bool = false) async throws {
        guard !capturing else { return }
        capturing = true
        defer { capturing = false }
        self.fullDisplay = fullDisplay; self.windowMode = windowMode
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 30 }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var result: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = CGDisplayPixelsWide(id); config.height = CGDisplayPixelsHigh(id)
            config.showsCursor = false; config.captureResolution = .best
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(DisplaySnapshot(display: display,screen: screen,image: image))
        }
        guard !result.isEmpty else { throw CocoaError(.fileReadUnknown) }
        snapshots = result
        NSApp.activate(ignoringOtherApps: true)
        for snapshot in snapshots {
            let panel = KeyPanel(contentRect: snapshot.screen.frame,styleMask: [.borderless],backing: .buffered,defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue-1)
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.isOpaque = true; panel.backgroundColor = .black; panel.isReleasedWhenClosed = false
            let view = CaptureView(snapshot: snapshot,coordinator: self)
            panel.contentView = view
            panel.orderFrontRegardless(); panels.append(panel)
            if snapshot.screen.frame.contains(NSEvent.mouseLocation) { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view) }
        }
    }
    func cancel() { close(); onCancel?() }
    func close() { panels.forEach { $0.close() }; panels.removeAll(); snapshots.removeAll(); windows.removeAll() }
    func chosen(_ rect: CGRect, snapshot: DisplaySnapshot) {
        let full = CGRect(origin: .zero,size: snapshot.screen.frame.size)
        let local = rect.intersection(full)
        guard local.width > 3, local.height > 3 else { return }
        let global = CGRect(x: snapshot.screen.frame.minX+local.minX,y: snapshot.screen.frame.maxY-local.maxY,width: local.width,height: local.height)
        let pixels = Geometry.pixelRect(screenRect: global,displayFrame: snapshot.screen.frame,pixelSize: CGSize(width: snapshot.image.width,height: snapshot.image.height))
        guard let image = snapshot.image.cropping(to: pixels) else { return }
        close(); onImage?(image,local,snapshot)
    }
    func windowRect(at point: CGPoint, snapshot: DisplaySnapshot) -> CGRect? {
        guard let main = NSScreen.screens.first else { return nil }
        let global = CGPoint(x: snapshot.screen.frame.minX+point.x,y: main.frame.maxY-snapshot.screen.frame.maxY+point.y)
        guard let w = windows.first(where: { $0.frame.contains(global) }) else { return nil }
        return CGRect(x: w.frame.minX-snapshot.screen.frame.minX,y: w.frame.minY-(main.frame.maxY-snapshot.screen.frame.maxY),width: w.frame.width,height: w.frame.height)
    }
}
final class CaptureView: NSView {
    let snapshot: DisplaySnapshot
    unowned let coordinator: CaptureCoordinator
    var start: CGPoint?
    var selection: CGRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(snapshot: DisplaySnapshot, coordinator: CaptureCoordinator) {
        self.snapshot = snapshot; self.coordinator = coordinator
        super.init(frame: CGRect(origin: .zero,size: snapshot.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero,options: [.activeAlways,.mouseMoved,.inVisibleRect],owner: self))
    }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: snapshot.image,size: bounds.size).draw(in: bounds)
        NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
        let selected = coordinator.fullDisplay ? bounds : selection
        if let r = selected, !r.isEmpty {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: r).addClip()
            NSImage(cgImage: snapshot.image,size: bounds.size).draw(in: bounds); NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke(); let border = NSBezierPath(rect: r); border.lineWidth = 1.5; border.stroke()
            let label = "\(Int(r.width*snapshot.imageSizeScale)) × \(Int(r.height*snapshot.imageSizeScale))"
            drawLabel(label, at: CGPoint(x: min(bounds.maxX-160,max(16,r.minX)),y: max(16,r.minY-32)))
        }
        drawLabel(tr("Drag to capture · Space: window · Esc: cancel", "Выделите область · Пробел: окно · Esc: отмена"),at: CGPoint(x: max(20,bounds.midX-220),y: 40))
    }
    func drawLabel(_ value: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13,weight: .medium),.foregroundColor: NSColor.white]
        let size = (value as NSString).size(withAttributes: attrs)
        let r = CGRect(x: point.x-10,y: point.y-6,width: size.width+20,height: size.height+12)
        NSColor.black.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect: r,xRadius: 8,yRadius: 8).fill()
        (value as NSString).draw(at: point,withAttributes: attrs)
    }
    override func mouseMoved(with event: NSEvent) {
        if coordinator.windowMode { selection = coordinator.windowRect(at: convert(event.locationInWindow,from: nil),snapshot: snapshot); needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow,from: nil)
        if coordinator.fullDisplay { coordinator.chosen(bounds,snapshot: snapshot); return }
        if coordinator.windowMode {
            if let r = coordinator.windowRect(at: p,snapshot: snapshot) { coordinator.chosen(r,snapshot: snapshot) }; return
        }
        start = p; selection = nil
    }
    override func mouseDragged(with event: NSEvent) { if let start { selection = Geometry.rect(start,convert(event.locationInWindow,from: nil)).intersection(bounds); needsDisplay = true } }
    override func mouseUp(with event: NSEvent) { if let r = selection, start != nil { start = nil; coordinator.chosen(r,snapshot: snapshot) } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { coordinator.cancel() }
        else if event.keyCode == 49 { coordinator.windowMode.toggle(); coordinator.fullDisplay = false; start = nil; selection = nil; needsDisplay = true }
    }
}
extension DisplaySnapshot { var imageSizeScale: CGFloat { CGFloat(image.width)/screen.frame.width } }
