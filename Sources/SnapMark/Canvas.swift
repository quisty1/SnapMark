import AppKit
import SnapMarkCore

final class CanvasView: NSView, NSTextFieldDelegate {
    let model: EditorModel
    let background: DisplaySnapshot?
    var imageOrigin: CGPoint
    var scale: CGFloat
    var cachedCrop: CGRect
    var cachedState: DocumentState?
    var rendered: CGImage?
    var draft: Annotation?
    var editingOriginal: Annotation?
    var dragStart: CGPoint?
    var dragViewStart: CGPoint?
    var originAtDrag: CGPoint?
    var resize = false
    var panning = false
    var spaceHeld = false
    var cropPreview: CGRect?
    var textField: NSTextField?
    var textAnnotation: Annotation?
    var action: ((NSEvent) -> Bool)?
    var onError: ((Error) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: EditorModel, frame: CGRect, placement: CGRect, background: DisplaySnapshot?) {
        self.model = model; self.background = background
        imageOrigin = placement.origin; scale = placement.width/CGFloat(model.session.image.width)
        cachedCrop = model.session.state.crop
        super.init(frame: frame)
        model.onChange = { [weak self] in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    var previewState: DocumentState {
        var state = model.session.state
        if let draft {
            if let i = state.annotations.firstIndex(where: { $0.id == draft.id }) { state.annotations[i] = draft }
            else { state.annotations.append(draft) }
        }
        return state
    }
    var imageRect: CGRect { CGRect(origin: imageOrigin,size: CGSize(width: cachedCrop.width*scale,height: cachedCrop.height*scale)) }
    func pointInImage(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x-imageOrigin.x)/scale+cachedCrop.minX,y: (p.y-imageOrigin.y)/scale+cachedCrop.minY) }
    func rectOnView(_ r: CGRect) -> CGRect {
        CGRect(x: imageOrigin.x+(r.minX-cachedCrop.minX)*scale,y: imageOrigin.y+(r.minY-cachedCrop.minY)*scale,width: r.width*scale,height: r.height*scale)
    }
    func refresh() {
        let newCrop = model.session.state.crop
        if newCrop != cachedCrop {
            imageOrigin.x += (newCrop.minX-cachedCrop.minX)*scale; imageOrigin.y += (newCrop.minY-cachedCrop.minY)*scale
            cachedCrop = newCrop
        }
        let state = previewState
        if state != cachedState {
            do { rendered = try ImageRenderer.render(image: model.session.image,state: state); cachedState = state }
            catch { onError?(error) }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if let background {
            NSImage(cgImage: background.image,size: bounds.size).draw(in: bounds)
        } else { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
        NSColor.black.withAlphaComponent(0.48).setFill(); bounds.fill()
        if let rendered { NSImage(cgImage: rendered,size: imageRect.size).draw(in: imageRect) }
        NSColor.white.withAlphaComponent(0.4).setStroke()
        NSBezierPath(rect: imageRect).stroke()
        if let id = model.selectedID, let a = previewState.annotations.first(where: { $0.id == id }) {
            let r = rectOnView(a.bounds).insetBy(dx: -4,dy: -4)
            NSColor.systemBlue.setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 1; p.setLineDash([4,3],count: 2,phase: 0); p.stroke()
            let handle = CGRect(x: r.maxX-4,y: r.maxY-4,width: 8,height: 8)
            NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); NSBezierPath(rect: handle).stroke()
        }
        if let r = cropPreview { NSColor.systemBlue.setStroke(); let p = NSBezierPath(rect: rectOnView(r)); p.lineWidth = 2; p.setLineDash([6,4],count: 2,phase: 0); p.stroke() }
        let help = tr("⌘C Copy   ⌘S Save   Esc Cancel   ·   Scroll to pan, ⌥ scroll to zoom", "⌘C Копировать   ⌘S Сохранить   Esc Отмена   ·   Прокрутка: сдвиг, ⌥ прокрутка: масштаб")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),.foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        (help as NSString).draw(at: CGPoint(x: 24,y: bounds.height-30),withAttributes: attrs)
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor: model.tool == .select ? .arrow : .crosshair) }
    override func mouseDown(with event: NSEvent) {
        finishText()
        window?.makeKey(); window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow,from: nil), ip = pointInImage(p)
        dragViewStart = p; originAtDrag = imageOrigin
        if spaceHeld || event.buttonNumber == 2 { panning = true; NSCursor.closedHand.push(); return }
        guard imageRect.contains(p) else { model.select(nil); return }
        dragStart = ip
        if model.tool == .select {
            if let id = model.selectedID, let a = model.session.state.annotations.first(where: { $0.id == id }),
               rectOnView(a.bounds).insetBy(dx: -4,dy: -4).contains(p),
               abs(p.x-rectOnView(a.bounds).maxX) < 12 && abs(p.y-rectOnView(a.bounds).maxY) < 12 {
                editingOriginal = a; draft = a; resize = true; return
            }
            let found = model.session.state.annotations.reversed().first { $0.bounds.insetBy(dx: -8/scale,dy: -8/scale).contains(ip) }
            model.select(found); editingOriginal = found; draft = found
            if event.clickCount == 2, let found, found.tool == .text { draft = nil; editingOriginal = nil; beginText(found) }
        } else if model.tool == .text { beginText(model.annotation(at: ip)) }
        else if model.tool == .crop { cropPreview = CGRect(origin: ip,size: .zero) }
        else { model.select(nil); draft = model.annotation(at: ip); refresh() }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil)
        if panning, let start = dragViewStart, let originAtDrag {
            imageOrigin = CGPoint(x: originAtDrag.x+p.x-start.x,y: originAtDrag.y+p.y-start.y); needsDisplay = true; return
        }
        guard let start = dragStart, textField == nil else { return }
        var ip = pointInImage(p)
        ip.x = max(cachedCrop.minX,min(cachedCrop.maxX,ip.x)); ip.y = max(cachedCrop.minY,min(cachedCrop.maxY,ip.y))
        if model.tool == .crop { cropPreview = Geometry.rect(start,ip); needsDisplay = true; return }
        if let original = editingOriginal {
            var a = original
            if resize {
                a.resize(to: CGRect(x: original.bounds.minX,y: original.bounds.minY,width: max(8,ip.x-original.bounds.minX),height: max(8,ip.y-original.bounds.minY)))
            } else { a.translate(dx: ip.x-start.x,dy: ip.y-start.y) }
            draft = a
        } else if var a = draft {
            if a.tool == .pen || a.tool == .highlighter { a.points.append(ip) }
            else if a.tool != .step { a.points = [start,ip] }
            draft = a
        }
        refresh()
    }
    override func mouseUp(with event: NSEvent) {
        if panning { panning = false; NSCursor.pop(); return }
        defer { dragStart = nil; dragViewStart = nil; editingOriginal = nil; resize = false; draft = nil; cropPreview = nil; refresh() }
        if let cropPreview { model.session.setCrop(cropPreview); model.changed(); return }
        guard let a = draft else { return }
        if editingOriginal != nil {
            var state = model.session.state
            if let i = state.annotations.firstIndex(where: { $0.id == a.id }) { state.annotations[i] = a; model.session.commit(state) }
        } else if a.points.count > 1 || a.tool == .step || a.tool == .pen || a.tool == .highlighter { model.session.add(a) }
        model.changed()
    }
    func beginText(_ a: Annotation) {
        textAnnotation = a
        let field = NSTextField(string: a.text)
        let r = rectOnView(a.bounds)
        let font = NSFont.systemFont(ofSize: max(10,a.fontSize*scale),weight: a.bold ? .semibold : .regular)
        field.font = font; field.textColor = a.color.nsColor; field.backgroundColor = .textBackgroundColor
        field.isBezeled = true; field.isEditable = true; field.isSelectable = true; field.focusRingType = .exterior
        field.frame = CGRect(x: r.minX,y: r.minY,width: max(180,min(bounds.maxX-r.minX-12,max(300,r.width+40))),height: font.pointSize*1.5+8)
        field.placeholderString = tr("Type text…", "Введите текст…"); field.delegate = self
        addSubview(field); textField = field; window?.makeFirstResponder(field); field.selectText(nil)
    }
    func finishText(cancel: Bool = false) {
        guard let field = textField, var a = textAnnotation else { return }
        textField = nil; textAnnotation = nil
        a.text = field.stringValue
        field.removeFromSuperview()
        if !cancel && !a.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var state = model.session.state
            if let i = state.annotations.firstIndex(where: { $0.id == a.id }) { state.annotations[i] = a }
            else { state.annotations.append(a) }
            model.session.commit(state)
        }
        model.changed(); window?.makeFirstResponder(self)
    }
    func controlTextDidEndEditing(_ obj: Notification) { finishText() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(cancel: true); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finishText(); return true }
        return false
    }
    @objc func copy(_ sender: Any?) { if let event = NSApp.currentEvent { _ = action?(event) } }
    @objc func saveDocument(_ sender: Any?) { if let event = NSApp.currentEvent { _ = action?(event) } }
    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    override func keyDown(with event: NSEvent) {
        if action?(event) == true { return }
        if event.keyCode == 49 { spaceHeld = true; return }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceHeld = false } }
    override func scrollWheel(with event: NSEvent) {
        finishText()
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            zoom(by: exp(event.scrollingDeltaY*0.012),at: convert(event.locationInWindow,from: nil))
        } else { imageOrigin.x += event.scrollingDeltaX; imageOrigin.y += event.scrollingDeltaY; needsDisplay = true }
    }
    override func magnify(with event: NSEvent) { finishText(); zoom(by: 1+event.magnification,at: convert(event.locationInWindow,from: nil)) }
    func zoom(by factor: CGFloat, at p: CGPoint) {
        let anchor = CGPoint(x: (p.x-imageOrigin.x)/scale,y: (p.y-imageOrigin.y)/scale)
        scale = min(8,max(0.04,scale*factor)); imageOrigin = CGPoint(x: p.x-anchor.x*scale,y: p.y-anchor.y*scale); needsDisplay = true
    }
}
