import AppKit
import Carbon
import Vision
import UniformTypeIdentifiers
import SnapMarkCore

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: (UInt32, UInt32)?
    var action: (() -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(code: UInt32, modifiers: UInt32) -> OSStatus {
        if let registered, registered.0 == code && registered.1 == modifiers { return noErr }
        var newReference: EventHotKeyRef?
        let result = RegisterEventHotKey(code,modifiers,EventHotKeyID(signature: 0x534E4150,id: 1),GetApplicationEventTarget(),0,&newReference)
        if result == noErr {
            if let reference { UnregisterEventHotKey(reference) }
            reference = newReference; registered = (code,modifiers)
        }
        return result
    }
}
struct OCRResult: Sendable { let text: String; let russianAvailable: Bool }
enum OCRService {
    @concurrent static func recognize(_ image: CGImage) async throws -> OCRResult {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = supported.filter { $0.hasPrefix("en") || $0.hasPrefix("ru") }
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image,options: [:]).perform([request])
        try Task.checkCancellation()
        let lines = (request.results ?? []).sorted {
            if abs($0.boundingBox.midY-$1.boundingBox.midY) < 0.01 { return $0.boundingBox.minX < $1.boundingBox.minX }
            return $0.boundingBox.midY > $1.boundingBox.midY
        }.compactMap { $0.topCandidates(1).first?.string }
        return OCRResult(text: lines.joined(separator: "\n"),russianAvailable: supported.contains { $0.hasPrefix("ru") })
    }
}
final class ExportFormat: NSObject {
    let panel: NSSavePanel
    let popup = NSPopUpButton(frame: CGRect(x: 80,y: 0,width: 130,height: 26))
    init(panel: NSSavePanel) {
        self.panel = panel; super.init()
        popup.toolTip = tr("Choose the exported image format", "Выбрать формат сохраняемого изображения")
        popup.addItems(withTitles: ["PNG", "JPEG"]); popup.target = self; popup.action = #selector(change)
        let view = NSView(frame: CGRect(x: 0,y: 0,width: 240,height: 30))
        let label = NSTextField(labelWithString: tr("Format:", "Формат:")); label.frame = CGRect(x: 0,y: 4,width: 76,height: 20)
        view.addSubview(label); view.addSubview(popup); panel.accessoryView = view
        panel.allowedContentTypes = [.png]
    }
    @objc func change() {
        panel.allowedContentTypes = [popup.indexOfSelectedItem == 0 ? .png : .jpeg]
        let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = stem + (popup.indexOfSelectedItem == 0 ? ".png" : ".jpg")
    }
    var jpeg: Bool { popup.indexOfSelectedItem == 1 }
}
func copyImage(_ image: CGImage) throws {
    let data = try ImageRenderer.png(image)
    let pasteboard = NSPasteboard.general; pasteboard.clearContents()
    guard pasteboard.setData(data,forType: .png) else { throw CocoaError(.fileWriteUnknown) }
}
