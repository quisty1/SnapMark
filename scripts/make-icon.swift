import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination,withIntermediateDirectories: true)
for points in [16,32,128,256,512] {
    for multiplier in [1,2] {
        let pixels = points*multiplier
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: pixels,pixelsHigh: pixels,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let c = NSGraphicsContext.current!.cgContext
        c.scaleBy(x: CGFloat(pixels)/1024,y: CGFloat(pixels)/1024)
        NSColor(srgbRed: 0.08,green: 0.12,blue: 0.2,alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 58,y: 58,width: 908,height: 908),xRadius: 210,yRadius: 210).fill()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        let corners = NSBezierPath(); corners.lineWidth = 40; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
        for (x,y,dx,dy) in [(270.0,754.0,1.0,-1.0),(754,754,-1,-1),(270,270,1,1),(754,270,-1,1)] {
            corners.move(to: CGPoint(x: x+dx*112,y: y)); corners.line(to: CGPoint(x: x,y: y)); corners.line(to: CGPoint(x: x,y: y+dy*112))
        }
        corners.stroke()
        NSColor(srgbRed: 0.24,green: 0.62,blue: 1,alpha: 1).setStroke()
        let arrow = NSBezierPath(); arrow.lineWidth = 58; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        arrow.move(to: CGPoint(x: 390,y: 380)); arrow.line(to: CGPoint(x: 650,y: 645))
        arrow.move(to: CGPoint(x: 490,y: 645)); arrow.line(to: CGPoint(x: 650,y: 645)); arrow.line(to: CGPoint(x: 650,y: 485)); arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = multiplier == 2 ? "@2x" : ""
        try rep.representation(using: .png,properties: [:])!.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
