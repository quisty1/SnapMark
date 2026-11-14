import AppKit
import SwiftUI

final class ToolbarTips: NSObject {
    private weak var toolbar: NSView?
    private weak var anchor: ToolbarTipAnchor?
    private var pending: Task<Void, Never>?
    private var bubble: NSView?

    init(toolbar: NSView, window: NSWindow) {
        self.toolbar = toolbar
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: window)
    }

    func enter(_ anchor: ToolbarTipAnchor) {
        hide()
        self.anchor = anchor
        pending = Task { [weak self, weak anchor] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard let self, let anchor, self.anchor === anchor else { return }
            show(for: anchor)
        }
    }

    func leave(_ anchor: ToolbarTipAnchor) {
        if self.anchor === anchor { hide() }
    }

    @objc private func windowDidResignKey(_ notification: Notification) { hide() }

    private func hide() {
        pending?.cancel()
        pending = nil
        anchor = nil
        bubble?.removeFromSuperview()
        bubble = nil
    }

    private func show(for anchor: ToolbarTipAnchor) {
        guard anchor.window?.isKeyWindow == true,
              let toolbar, let canvas = toolbar.superview else { return }

        // The editor sits above the system help window. Draw the tip in the canvas
        // so it stays above the editor and outside the toolbar's clipping bounds.
        let view = ToolbarTipBubble(rootView: ToolbarTipLabel(title: anchor.title, detail: anchor.detail))
        view.appearance = toolbar.effectiveAppearance
        let size = view.fittingSize
        let button = anchor.convert(anchor.bounds, to: canvas)
        let bounds = canvas.bounds.insetBy(dx: 8, dy: 8)
        let x = min(max(button.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let below = toolbar.frame.maxY + 6
        let above = toolbar.frame.minY - 6 - size.height
        let y = below + size.height <= bounds.maxY ? below : max(bounds.minY, above)
        view.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        canvas.addSubview(view, positioned: .above, relativeTo: nil)
        bubble = view
    }
}

private struct ToolbarTipLabel: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title).fontWeight(.semibold)
            if let detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15))
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

private final class ToolbarTipBubble: NSHostingView<ToolbarTipLabel> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ToolbarTipAnchor: NSView {
    weak var tips: ToolbarTips?
    var title = ""
    var detail: String?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { tips?.enter(self) }
    override func mouseExited(with event: NSEvent) { tips?.leave(self) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { tips?.leave(self) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { updateTrackingAreas() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        let rect = bounds
        if window != nil, tracking?.rect == rect { return }
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        guard window != nil, !rect.isEmpty else { return }
        let area = NSTrackingArea(rect: rect, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }
}

private struct ToolbarTipTrackingView: NSViewRepresentable {
    let tips: ToolbarTips
    let title: String
    let detail: String?

    func makeNSView(context: Context) -> ToolbarTipAnchor { ToolbarTipAnchor() }

    func updateNSView(_ view: ToolbarTipAnchor, context: Context) {
        view.tips = tips
        view.title = title
        view.detail = detail
    }
}

extension View {
    func toolbarTip(_ tips: ToolbarTips, _ title: String, detail: String? = nil) -> some View {
        background {
            ToolbarTipTrackingView(tips: tips, title: title, detail: detail)
        }
        .accessibilityHint(Text(verbatim: detail ?? title))
    }
}
