import AppKit
import SwiftUI
import SnapMarkCore

final class EditorController {
    let model: EditorModel
    let window: KeyPanel
    let toolbar: KeyPanel
    let canvas: CanvasView
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onPin: (() -> Void)?
    var onOCR: (() -> Void)?
    var onCancel: (() -> Void)?
    init(image: CGImage, placement: CGRect, screen: NSScreen, background: DisplaySnapshot?) {
        model = EditorModel(image: image)
        window = KeyPanel(contentRect: screen.frame,styleMask: [.borderless],backing: .buffered,defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue-1)
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        window.isOpaque = true; window.isReleasedWhenClosed = false
        canvas = CanvasView(model: model,frame: CGRect(origin: .zero,size: screen.frame.size),placement: placement,background: background)
        window.contentView = canvas
        let width = min(740,screen.frame.width-24)
        toolbar = KeyPanel(contentRect: CGRect(x: 0,y: 0,width: width,height: 104),styleMask: [.borderless],backing: .buffered,defer: false)
        toolbar.level = .screenSaver; toolbar.isOpaque = false; toolbar.backgroundColor = .clear; toolbar.hasShadow = true
        toolbar.isReleasedWhenClosed = false; toolbar.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        let effect = NSVisualEffectView(frame: CGRect(x: 0,y: 0,width: width,height: 104))
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true; effect.layer?.cornerRadius = 14; effect.layer?.masksToBounds = true
        let host = NSHostingView(rootView: EditorToolbar(model: model,controller: self))
        host.frame = effect.bounds; host.autoresizingMask = [.width,.height]; effect.addSubview(host); toolbar.contentView = effect
        let x = min(screen.frame.maxX-width-12,max(screen.frame.minX+12,screen.frame.minX+placement.midX-width/2))
        let below = screen.frame.maxY-placement.maxY-116
        let y = below >= screen.frame.minY+40 ? below : min(screen.frame.maxY-120,screen.frame.maxY-placement.minY+12)
        toolbar.setFrameOrigin(CGPoint(x: x,y: max(screen.frame.minY+40,y)))
        window.keyHandler = { [weak self] in self?.handle($0) ?? false }
        toolbar.keyHandler = { [weak self] in self?.handle($0) ?? false }
        canvas.action = { [weak self] in self?.handle($0) ?? false }
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); toolbar.orderFrontRegardless() }
    func close() { canvas.finishText(cancel: true); toolbar.close(); window.close() }
    func selectTool(_ tool: Tool) { canvas.finishText(); model.selectedID = nil; model.tool = tool; model.changed(); window.makeKey(); window.makeFirstResponder(canvas) }
    func rendered() throws -> CGImage { canvas.finishText(); return try ImageRenderer.render(image: model.session.image,state: model.session.state) }
    func handle(_ event: NSEvent) -> Bool {
        if (window.firstResponder is NSTextView && canvas.textField != nil) || (toolbar.firstResponder is NSTextView) { return false }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": onCopy?(); return true
            case "s": onSave?(); return true
            case "z": if event.modifierFlags.contains(.shift) { model.redo() } else { model.undo() }; return true
            case "+", "=": canvas.zoom(by: 1.2,at: canvas.imageRect.center); return true
            case "-": canvas.zoom(by: 1/1.2,at: canvas.imageRect.center); return true
            default: return false
            }
        }
        if event.keyCode == 53 { onCancel?(); return true }
        if event.keyCode == 51 || event.keyCode == 117 { model.deleteSelected(); return true }
        return false
    }
}
extension CGRect { var center: CGPoint { CGPoint(x: midX,y: midY) } }
struct EditorToolbar: View {
    @Bindable var model: EditorModel
    let controller: EditorController
    func icon(_ symbol: String, _ label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14,weight: .medium)).frame(width: 29,height: 29)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear,in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(Tool.allCases,id: \.self) { tool in icon(tool.symbol,tool.title,selected: model.tool == tool) { controller.selectTool(tool) } }
                Spacer(minLength: 4)
                icon("arrow.uturn.backward",tr("Undo", "Отменить")) { model.undo() }.disabled(!model.session.canUndo)
                icon("arrow.uturn.forward",tr("Redo", "Повторить")) { model.redo() }.disabled(!model.session.canRedo)
                Divider().frame(height: 20)
                icon("xmark",tr("Cancel", "Отмена")) { controller.onCancel?() }
            }
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                ColorPicker(tr("Color", "Цвет"),selection: $model.color,supportsOpacity: false).labelsHidden().frame(width: 30).help(tr("Color", "Цвет"))
                if [.text,.step].contains(model.tool) || selectedTool == .text || selectedTool == .step {
                    Text("Aa").font(.system(size: 12)); Slider(value: $model.fontSize,in: 10...100).frame(width: 72)
                    Toggle("B",isOn: $model.bold).toggleStyle(.button).fontWeight(.bold).help(tr("Bold", "Полужирный"))
                } else if [.blur,.pixelate].contains(model.tool) || selectedTool == .blur || selectedTool == .pixelate {
                    Image(systemName: "slider.horizontal.3"); Slider(value: $model.strength,in: 4...60).frame(width: 92)
                } else {
                    Image(systemName: "lineweight").font(.system(size: 12)); Slider(value: $model.width,in: 1...24).frame(width: 72)
                    if [.rectangle,.ellipse].contains(model.tool) || selectedTool == .rectangle || selectedTool == .ellipse {
                        Toggle(tr("Fill", "Заливка"),isOn: $model.filled).toggleStyle(.button).font(.system(size: 11))
                    }
                }
                Spacer(minLength: 2)
                if model.ocrBusy { ProgressView().controlSize(.small) }
                icon("text.viewfinder",tr("Recognize text", "Распознать текст")) { controller.onOCR?() }.disabled(model.ocrBusy)
                icon("pin",tr("Pin above windows", "Закрепить поверх окон")) { controller.onPin?() }
                icon("square.and.arrow.down",tr("Save…", "Сохранить…")) { controller.onSave?() }
                Button { controller.onCopy?() } label: {
                    Label(tr("Copy", "Копировать"),systemImage: "doc.on.doc").font(.system(size: 12,weight: .semibold)).padding(.horizontal,6).padding(.vertical,4)
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }.padding(12).frame(maxWidth: .infinity).tint(.blue)
            .onChange(of: model.color) { model.applyStyle() }
            .onChange(of: model.width) { model.applyStyle() }
            .onChange(of: model.fontSize) { model.applyStyle() }
            .onChange(of: model.strength) { model.applyStyle() }
            .onChange(of: model.filled) { model.applyStyle() }
            .onChange(of: model.bold) { model.applyStyle() }
            .onChange(of: model.revision) { _ = model.revision }
    }
    var selectedTool: Tool? { model.session.state.annotations.first { $0.id == model.selectedID }?.tool }
}
