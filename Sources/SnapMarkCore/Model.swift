import AppKit

public enum Tool: String, CaseIterable, Sendable {
    case select, pen, highlighter, line, arrow, rectangle, ellipse, text, step, blur, pixelate, conceal, crop
}
public struct RGBA: Equatable, Codable, Sendable {
    public var red: Double; public var green: Double; public var blue: Double; public var alpha: Double
    public init(red: Double = 0.08, green: Double = 0.45, blue: Double = 1, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var tool: Tool; public var points: [CGPoint]; public var text: String
    public var color = RGBA(); public var width: CGFloat = 12; public var fontSize: CGFloat = 28
    public var bold = false; public var filled = false; public var strength: CGFloat = 16; public var number = 1
    public init(id: UUID = UUID(), tool: Tool, points: [CGPoint], text: String = "") {
        self.id = id; self.tool = tool; self.points = points; self.text = text
    }
    @MainActor public var bounds: CGRect {
        guard let p = points.first else { return .zero }
        if tool == .text {
            let font = NSFont.systemFont(ofSize: fontSize,weight: bold ? .semibold : .regular)
            let measured = (text as NSString).size(withAttributes: [.font: font])
            return CGRect(x: p.x,y: p.y,width: max(fontSize,ceil(measured.width)+2),height: max(fontSize*1.3,ceil(measured.height)))
        }
        if tool == .step { return CGRect(x: p.x - fontSize * 0.65, y: p.y - fontSize * 0.65, width: fontSize * 1.3, height: fontSize * 1.3) }
        return points.reduce(CGRect(origin: p, size: .zero)) { r, p in
            CGRect(x: min(r.minX, p.x), y: min(r.minY, p.y), width: max(r.maxX, p.x) - min(r.minX, p.x), height: max(r.maxY, p.y) - min(r.minY, p.y))
        }
    }
    public mutating func translate(dx: CGFloat, dy: CGFloat) { points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) } }
    @MainActor public mutating func resize(to rect: CGRect) {
        let old = bounds
        let sx = rect.width / max(1, old.width), sy = rect.height / max(1, old.height)
        if tool == .text || tool == .step {
            let factor = abs(sx-1) >= abs(sy-1) ? sx : sy
            fontSize = max(8,fontSize*factor)
            points = [tool == .step ? CGPoint(x: rect.minX+fontSize*0.65,y: rect.minY+fontSize*0.65) : rect.origin]
        } else {
            let count = points.count
            points = points.enumerated().map { index, point in
                let fraction = CGFloat(index)/CGFloat(max(1,count-1))
                return CGPoint(x: rect.minX+(old.width < 0.01 ? fraction*rect.width : (point.x-old.minX)*sx),
                               y: rect.minY+(old.height < 0.01 ? fraction*rect.height : (point.y-old.minY)*sy))
            }
        }
    }
}
public struct DocumentState: Equatable, Sendable {
    public var annotations: [Annotation] = []
    public var crop: CGRect
    public init(crop: CGRect) { self.crop = crop }
}
public enum Geometry {
    public static func pixelRect(screenRect: CGRect, displayFrame: CGRect, pixelSize: CGSize) -> CGRect {
        let r = screenRect.intersection(displayFrame)
        guard !r.isNull, displayFrame.width > 0, displayFrame.height > 0 else { return .zero }
        let sx = pixelSize.width / displayFrame.width, sy = pixelSize.height / displayFrame.height
        return CGRect(x: (r.minX-displayFrame.minX)*sx, y: (displayFrame.maxY-r.maxY)*sy,
                      width: r.width*sx, height: r.height*sy).integral
    }
    public static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
}
@MainActor public final class EditSession {
    public let image: CGImage
    public private(set) var state: DocumentState
    public private(set) var undoStates: [DocumentState] = [], redoStates: [DocumentState] = []
    public var canUndo: Bool { !undoStates.isEmpty }; public var canRedo: Bool { !redoStates.isEmpty }
    public init(image: CGImage) { self.image = image; state = DocumentState(crop: CGRect(x: 0,y: 0,width: image.width,height: image.height)) }
    public func commit(_ state: DocumentState) {
        guard state != self.state else { return }
        undoStates.append(self.state)
        if undoStates.count > 150 { undoStates.removeFirst() }
        self.state = state; redoStates.removeAll()
    }
    public func add(_ annotation: Annotation) { var next = state; next.annotations.append(annotation); commit(next) }
    public func setCrop(_ rect: CGRect) {
        let clipped = rect.standardized.integral.intersection(state.crop)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return }
        var next = state; next.crop = clipped; commit(next)
    }
    public func undo() { guard let previous = undoStates.popLast() else { return }; redoStates.append(state); state = previous }
    public func redo() { guard let next = redoStates.popLast() else { return }; undoStates.append(state); state = next }
}
