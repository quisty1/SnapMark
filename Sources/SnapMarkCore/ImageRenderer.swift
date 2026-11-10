import AppKit
import CoreImage

public enum RenderError: Error { case bitmap, encoding }
@MainActor public enum ImageRenderer {
    private static let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    public static func render(image: CGImage, state: DocumentState) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let full = CGRect(origin: .zero, size: size)
        guard let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.bitmap }
        c.draw(image, in: full)
        c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
        for a in state.annotations {
            c.saveGState()
            c.setStrokeColor(a.color.nsColor.cgColor); c.setFillColor(a.color.nsColor.cgColor)
            c.setLineWidth(a.width); c.setLineCap(.round); c.setLineJoin(.round)
            let r = a.bounds.standardized
            switch a.tool {
            case .blur, .pixelate:
                if let current = c.makeImage() {
                    let source = CIImage(cgImage: current)
                    let output: CIImage
                    if a.tool == .blur {
                        output = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(1,a.strength)]).cropped(to: source.extent)
                    } else {
                        output = source.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(4,a.strength)])
                    }
                    if let masked = ci.createCGImage(output, from: source.extent) {
                        c.clip(to: r); c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1); c.draw(masked, in: full)
                    }
                }
            case .conceal: c.setFillColor(a.color.nsColor.withAlphaComponent(1).cgColor); c.fill(r)
            case .rectangle: c.addRect(r); c.drawPath(using: a.filled ? .fillStroke : .stroke)
            case .ellipse: c.addEllipse(in: r); c.drawPath(using: a.filled ? .fillStroke : .stroke)
            case .pen, .highlighter, .line, .arrow:
                if a.tool == .highlighter { c.setAlpha(0.28); c.setLineWidth(a.width * 4) }
                if let first = a.points.first {
                    c.move(to: first)
                    for p in a.points.dropFirst() { c.addLine(to: p) }
                    if a.points.count == 1 { c.addLine(to: CGPoint(x: first.x+0.1,y: first.y+0.1)) }
                    c.strokePath()
                }
                if a.tool == .arrow, a.points.count > 1, let start = a.points.first, let end = a.points.last {
                    let angle = atan2(end.y-start.y,end.x-start.x), length = max(12,a.width*4)
                    for delta in [-CGFloat.pi/6, CGFloat.pi/6] {
                        c.move(to: end); c.addLine(to: CGPoint(x: end.x-length*cos(angle+delta),y: end.y-length*sin(angle+delta))); c.strokePath()
                    }
                }
            case .text:
                drawText(a.text, in: CGRect(x: r.minX,y: r.minY,width: max(r.width+20,1),height: max(r.height*CGFloat(max(1,a.text.components(separatedBy: "\n").count)),1)),
                         size: a.fontSize, bold: a.bold, color: a.color.nsColor, context: c)
            case .step:
                c.fillEllipse(in: r)
                let text = String(a.number), font = NSFont.systemFont(ofSize: a.fontSize*0.65,weight: .semibold)
                let measured = (text as NSString).size(withAttributes: [.font: font])
                drawText(text,in: CGRect(x: r.midX-measured.width/2,y: r.midY-measured.height/2,width: measured.width+2,height: measured.height+2),
                         size: a.fontSize*0.65,bold: true,color: .white,context: c)
            case .select, .crop: break
            }
            c.restoreGState()
        }
        guard let rendered = c.makeImage(), let cropped = rendered.cropping(to: state.crop.intersection(full).integral) else { throw RenderError.bitmap }
        return cropped
    }
    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool, color: NSColor, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size,weight: bold ? .semibold : .regular), .foregroundColor: color])
        NSGraphicsContext.restoreGraphicsState()
    }
    public static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw RenderError.encoding }; return data
    }
    public static func jpeg(_ image: CGImage) throws -> Data {
        guard let c = CGContext(data: nil,width: image.width,height: image.height,bitsPerComponent: 8,bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RenderError.bitmap }
        let r = CGRect(x: 0,y: 0,width: image.width,height: image.height)
        c.setFillColor(NSColor.white.cgColor); c.fill(r); c.draw(image,in: r)
        guard let flat = c.makeImage(), let data = NSBitmapImageRep(cgImage: flat).representation(using: .jpeg,properties: [.compressionFactor: 0.92]) else { throw RenderError.encoding }
        return data
    }
    public static func thumbnail(_ image: CGImage) throws -> CGImage {
        let factor = min(1,320 / CGFloat(max(image.width,image.height)))
        let w = max(1,Int(CGFloat(image.width)*factor)), h = max(1,Int(CGFloat(image.height)*factor))
        guard let c = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError.bitmap }
        c.interpolationQuality = .high; c.draw(image,in: CGRect(x: 0,y: 0,width: w,height: h))
        guard let result = c.makeImage() else { throw RenderError.bitmap }; return result
    }
}
