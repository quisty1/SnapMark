import Foundation
import Darwin
import AppKit
import SnapMarkCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () throws -> Bool, file: String = #fileID, line: Int = #line) throws {
    if try !value() { throw CheckFailure(description: "Assertion failed at \(file):\(line)") }
}
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(description: "Required non-nil value") }; return value
}
func expectThrows(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }; throw CheckFailure(description: "Expected an error")
}
@MainActor @main struct CoreTests {
    static func main() {
        let t = CoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("mixed-DPI negative coordinates", t.negativeOriginRetinaCoordinates),
            ("crop, undo, redo", t.cropIsClampedAndUndoRestoresObjects),
            ("flattened opaque mask and crop", t.opaqueMaskAndCropAreBakedIntoPNG),
            ("blur clipped to mask", t.blurChangesPixelsInsideMaskAndPreservesOutside),
            ("flattened history and retention", t.historyRetainsOnlyFinalImagesAndTrims),
            ("history write rollback", t.failedHistoryWriteLeavesExistingIndexUntouched),
            ("wide text bounds", t.textBoundsDoNotClipWideGlyphs),
            ("text and masks use top-left coordinates", t.textAndMaskOrientation),
            ("history delete survives reload", t.deleteHistorySurvivesReload),
            ("corrupt history is preserved", t.corruptHistoryIsNotOverwritten),
            ("all drawing tools render", t.drawingToolsLeaveVisiblePixels),
            ("JPEG flattens transparency on white", t.jpegWhiteBackground)
        ]
        var failures = 0
        for (name, test) in tests {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(tests.count - failures)/\(tests.count) checks passed")
        if failures > 0 { exit(1) }
    }

    func image(_ color: NSColor = .white, width: Int = 100, height: Int = 80) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(color.cgColor); c.fill(CGRect(x: 0, y: 0, width: width, height: height)); return c.makeImage()!
    }
    func negativeOriginRetinaCoordinates() throws {
        let mapped = Geometry.pixelRect(screenRect: CGRect(x: -1400, y: 200, width: 100, height: 50),
            displayFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900), pixelSize: CGSize(width: 2880, height: 1800))
        try expect(mapped == CGRect(x: 80, y: 1300, width: 200, height: 100))
    }
    func cropIsClampedAndUndoRestoresObjects() throws {
        let s = EditSession(image: image())
        let a = Annotation(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)])
        s.add(a); s.setCrop(CGRect(x: -10, y: -5, width: 50, height: 35))
        try expect(s.state.crop == CGRect(x: 0, y: 0, width: 40, height: 30))
        s.undo(); try expect(s.state.crop == CGRect(x: 0, y: 0, width: 100, height: 80))
        s.undo(); try expect(s.state.annotations.isEmpty)
        s.redo(); try expect(s.state.annotations.count == 1)
        s.add(Annotation(tool: .text, points: [.zero], text: "Привет")); try expect(!s.canRedo)
    }
    func opaqueMaskAndCropAreBakedIntoPNG() throws {
        let s = EditSession(image: image())
        var mask = Annotation(tool: .conceal, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80)])
        mask.color = RGBA(red: 0, green: 0, blue: 0)
        s.add(mask); s.setCrop(CGRect(x: 10, y: 10, width: 20, height: 15))
        let rendered = try ImageRenderer.render(image: s.image, state: s.state)
        try expect(rendered.width == 20); try expect(rendered.height == 15)
        let decoded = try require(NSBitmapImageRep(data: ImageRenderer.png(rendered)))
        let color = try require(decoded.colorAt(x: 10, y: 7)?.usingColorSpace(.sRGB))
        try expect(color.redComponent < 0.01 && color.greenComponent < 0.01 && color.blueComponent < 0.01)
    }
    func blurChangesPixelsInsideMaskAndPreservesOutside() throws {
        let c = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        c.setFillColor(NSColor.black.cgColor); c.fill(CGRect(x: 0, y: 0, width: 50, height: 80))
        let s = EditSession(image: c.makeImage()!)
        var blur = Annotation(tool: .blur, points: [CGPoint(x: 30, y: 0), CGPoint(x: 70, y: 80)])
        blur.strength = 12; s.add(blur)
        let rep = NSBitmapImageRep(cgImage: try ImageRenderer.render(image: s.image, state: s.state))
        let middle = rep.colorAt(x: 49, y: 40)!.usingColorSpace(.sRGB)!
        try expect(middle.redComponent > 0.1 && middle.redComponent < 0.9)
        try expect(rep.colorAt(x: 10, y: 40)!.usingColorSpace(.sRGB)!.redComponent < 0.01)
        try expect(rep.colorAt(x: 90, y: 40)!.usingColorSpace(.sRGB)!.redComponent > 0.99)
    }
    func historyRetainsOnlyFinalImagesAndTrims() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try HistoryStore(directory: dir)
        try store.add(image: image(.red), limit: 2)
        try store.add(image: image(.green), limit: 2)
        try store.add(image: image(.blue), limit: 2)
        try expect(store.entries.count == 2)
        let restored = try HistoryStore(directory: dir)
        try expect(restored.entries.count == 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        try expect(files.filter { $0.hasSuffix(".png") }.count == 4)
        try expect(!files.contains { $0.contains("original") || $0.contains("document") })
        try restored.clear(); try expect(restored.entries.isEmpty)
    }
    func failedHistoryWriteLeavesExistingIndexUntouched() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try HistoryStore(directory: dir)
        try store.add(image: image(), limit: 100)
        let old = store.entries
        try FileManager.default.removeItem(at: dir.appendingPathComponent("index.json"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("index.json"), withIntermediateDirectories: true)
        try expectThrows { try store.add(image: image(), limit: 100) }
        try expect(store.entries == old)
        try expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.count == 2)
    }
    func textBoundsDoNotClipWideGlyphs() throws {
        var a = Annotation(tool: .text,points: [CGPoint(x: 10,y: 10)],text: "WWWWW")
        a.fontSize = 40
        let measured = ("WWWWW" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
        try expect(a.bounds.width >= measured.width)
    }
    func textAndMaskOrientation() throws {
        let s = EditSession(image: image(width: 400,height: 200))
        var text = Annotation(tool: .text,points: [CGPoint(x: 10,y: 5)],text: "Привет WWW")
        text.fontSize = 28; text.color = RGBA(red: 0,green: 0,blue: 0); s.add(text)
        var mask = Annotation(tool: .conceal,points: [CGPoint(x: 350,y: 0),CGPoint(x: 400,y: 40)])
        mask.color = RGBA(red: 1,green: 0,blue: 0); s.add(mask)
        let rendered = try ImageRenderer.render(image: s.image,state: s.state)
        let rep = NSBitmapImageRep(cgImage: rendered)
        var darkPixels = 0
        for y in 5..<45 { for x in 10..<250 {
            if rep.colorAt(x: x,y: y)!.usingColorSpace(.sRGB)!.redComponent < 0.5 { darkPixels += 1 }
        } }
        try expect(darkPixels > 100)
        try expect(rep.colorAt(x: 375,y: 10)!.usingColorSpace(.sRGB)!.greenComponent < 0.3)
        try expect(rep.colorAt(x: 375,y: 180)!.usingColorSpace(.sRGB)!.greenComponent > 0.99)
    }
    func deleteHistorySurvivesReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try HistoryStore(directory: dir); try store.add(image: image(),limit: 100)
        let entry = try require(store.entries.first); try store.delete(entry)
        try expect(try HistoryStore(directory: dir).entries.isEmpty)
        try expect(!FileManager.default.fileExists(atPath: store.imageURL(entry).path))
    }
    func corruptHistoryIsNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("index.json"), bytes = Data("corrupt".utf8)
        try bytes.write(to: url)
        try expectThrows { _ = try HistoryStore(directory: dir) }
        try expect(try Data(contentsOf: url) == bytes)
    }
    func drawingToolsLeaveVisiblePixels() throws {
        for tool in [Tool.pen,.highlighter,.line,.arrow,.rectangle,.ellipse,.step,.text] {
            let s = EditSession(image: image())
            var a = Annotation(tool: tool,points: [CGPoint(x: 10,y: 10),CGPoint(x: 70,y: 60)],text: "Aa")
            a.fontSize = 20; s.add(a)
            let rep = NSBitmapImageRep(cgImage: try ImageRenderer.render(image: s.image,state: s.state))
            var marked = 0
            for y in 0..<80 { for x in 0..<100 { if rep.colorAt(x: x,y: y)!.usingColorSpace(.sRGB)!.redComponent < 0.98 { marked += 1 } } }
            try expect(marked > 10)
        }
    }
    func jpegWhiteBackground() throws {
        let c = CGContext(data: nil,width: 10,height: 10,bitsPerComponent: 8,bytesPerRow: 0,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rep = try require(NSBitmapImageRep(data: ImageRenderer.jpeg(c.makeImage()!)))
        let color = rep.colorAt(x: 5,y: 5)!.usingColorSpace(.sRGB)!
        try expect(color.redComponent > 0.98 && color.greenComponent > 0.98 && color.blueComponent > 0.98)
    }
}
