import AppKit
import SnapMarkCore

struct NativeFailure: Error, CustomStringConvertible { let description: String }
@MainActor func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NativeFailure(description: message) }
}
actor PausedRecognition {
    var requests: [CheckedContinuation<OCRResult,any Error>] = []
    func run() async throws -> OCRResult { try await withCheckedThrowingContinuation { requests.append($0) } }
    var count: Int { requests.count }
    func complete(_ index: Int) { requests[index].resume(returning: OCRResult(text: "Test",russianAvailable: true)) }
}
@MainActor @main struct NativeChecks {
    static func editor() -> EditorController {
        let screen = NSScreen.main!
        return EditorController(image: DemoImage.make(),placement: CGRect(x: 40,y: 60,width: 800,height: 500),screen: screen,background: nil)
    }
    static func main() async {
        _ = NSApplication.shared; NSApp.finishLaunching()
        var failures = 0
        func run(_ name: String,_ body: () throws -> Void) {
            do { try body(); print("PASS \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        run("capture configuration preserves Retina pixels") {
            let config = CaptureCoordinator.imageConfiguration(pointSize: CGSize(width: 1920,height: 1243),pixelScale: 2)
            try check(config.width == 3840 && config.height == 2486,"Capture configuration downsampled the Retina display")
        }
        run("reopening app preserves the active editor") {
            let delegate = AppDelegate(), e = editor(); delegate.editor = e
            defer { delegate.closeEditor(); delegate.welcomeWindow?.close() }
            _ = delegate.applicationShouldHandleReopen(NSApp,hasVisibleWindows: true)
            try check(delegate.welcomeWindow == nil,"Reopen replaced an active editor with the welcome window")
        }
        run("closed editor releases screenshot session") {
            weak var released: EditorController?
            autoreleasepool { var e: EditorController? = editor(); released = e; e?.close(); e = nil }
            try check(released == nil,"Editor retain cycle keeps original screenshot in memory")
        }
        run("visible resize handle starts resize") {
            let e = editor(); defer { e.close() }
            let a = Annotation(tool: .rectangle,points: [CGPoint(x: 20,y: 20),CGPoint(x: 120,y: 120)])
            e.model.session.add(a); e.model.tool = .select; e.model.selectedID = a.id; e.canvas.refresh()
            let r = e.canvas.rectOnView(a.bounds), p = CGPoint(x: r.maxX+4,y: r.maxY+4)
            let event = NSEvent.mouseEvent(with: .leftMouseDown,location: e.canvas.convert(p,to: nil),modifierFlags: [],timestamp: 0,windowNumber: e.window.windowNumber,context: nil,eventNumber: 1,clickCount: 1,pressure: 1)!
            e.canvas.mouseDown(with: event)
            try check(e.canvas.resize,"Visible handle selected move instead of resize")
        }
        run("clearing existing text removes object") {
            let e = editor(); defer { e.close() }
            let a = Annotation(tool: .text,points: [CGPoint(x: 20,y: 20)],text: "Remove me")
            e.show(); e.model.session.add(a); e.canvas.beginText(a)
            guard let live = e.canvas.textField?.currentEditor() else { throw NativeFailure(description: "Text editor inactive; field=\(String(describing: e.canvas.textField)), responder=\(String(describing: e.window.firstResponder)), key=\(e.window.isKeyWindow)") }
            live.string = ""; e.canvas.finishText()
            try check(e.model.session.state.annotations.isEmpty,"Empty text retained old annotation")
        }
        run("live Cyrillic text is committed before export") {
            let e = editor(); defer { e.close() }; e.show()
            let a = Annotation(tool: .text,points: [CGPoint(x: 20,y: 20)],text: "")
            e.canvas.beginText(a)
            guard let live = e.canvas.textField?.currentEditor() else { throw NativeFailure(description: "Text editor inactive; field=\(String(describing: e.canvas.textField)), responder=\(String(describing: e.window.firstResponder)), key=\(e.window.isKeyWindow)") }
            live.string = "Новый WWW"; _ = try e.rendered()
            try check(e.model.session.state.annotations.first?.text == "Новый WWW","Export discarded uncommitted input")
        }
        run("menu selectors request copy and save directly") {
            let e = editor(); defer { e.close() }; var copies = 0, saves = 0
            e.onCopy = { copies += 1 }; e.onSave = { saves += 1 }
            e.canvas.copy(nil); e.canvas.saveDocument(nil)
            try check(copies == 1 && saves == 1,"Native menu command was ignored")
        }
        run("native OCR close cancels the request lifecycle") {
            let delegate = AppDelegate(); let e = editor(); delegate.editor = e
            defer { delegate.closeEditor() }
            delegate.ocrGeneration = UUID(); e.model.ocrBusy = true
            delegate.showOCR(text: "Pending",busy: true)
            let originalWindow = delegate.ocrWindow
            delegate.showOCR(text: "Result",busy: false,copyText: "Result")
            try check(delegate.ocrWindow === originalWindow,"OCR result replaced its native window")
            delegate.ocrWindow?.close()
            try check(delegate.ocrGeneration == nil && !e.model.ocrBusy && delegate.ocrWindow == nil,"Native close did not cancel OCR")
        }
        do {
            let gate = PausedRecognition(), delegate = AppDelegate(), e = editor()
            delegate.editor = e
            delegate.recognizeImage = { _ in try await gate.run() }
            delegate.recognizeText(); let first = delegate.ocrTask
            for _ in 0..<1000 { if await gate.count >= 1 { break }; await Task.yield() }
            let firstCount = await gate.count; try check(firstCount == 1,"First recognition did not start")
            delegate.dismissOCR(); delegate.recognizeText(); let second = delegate.ocrTask
            let generation = delegate.ocrGeneration
            for _ in 0..<1000 { if await gate.count >= 2 { break }; await Task.yield() }
            let secondCount = await gate.count; try check(secondCount == 2,"Second recognition did not start")
            await gate.complete(0); await first?.value
            try check(delegate.ocrGeneration == generation && delegate.ocrTask != nil && e.model.ocrBusy,"Cancelled task cleared a newer recognition")
            await gate.complete(1); await second?.value
            try check(!e.model.ocrBusy,"Completed recognition stayed busy")
            delegate.closeEditor(); print("PASS cancelled OCR cannot clear a newer request")
        } catch { failures += 1; print("FAIL OCR generation lifecycle: \(error)") }
        do {
            let result = try await OCRService.recognize(DemoImage.make())
            try check(result.text.contains("clearer") && result.text.contains("Get started"),"Vision did not recognize the English fixture")
            if result.russianAvailable { try check(result.text.contains("Скриншоты"),"Vision did not recognize Cyrillic fixture") }
            print("PASS real Vision OCR (Russian supported: \(result.russianAvailable))")
        } catch { failures += 1; print("FAIL real Vision OCR: \(error)") }
        print("Native failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
