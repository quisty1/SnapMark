import AppKit
import SwiftUI
import SnapMarkCore

final class EditorController {
    let model: EditorModel
    let window: KeyPanel
    let toolbar: NSVisualEffectView
    let canvas: CanvasView
    let tips: ToolbarTips
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
        toolbar = NSVisualEffectView(frame: CGRect(x: 0,y: 0,width: width,height: 104))
        toolbar.material = .popover; toolbar.blendingMode = .withinWindow; toolbar.state = .active
        toolbar.wantsLayer = true; toolbar.layer?.cornerRadius = 14; toolbar.layer?.masksToBounds = true
        toolbar.layer?.borderWidth = 0.5; toolbar.layer?.borderColor = NSColor.separatorColor.cgColor
        tips = ToolbarTips(toolbar: toolbar, window: window)
        let host = NSHostingView(rootView: EditorToolbar(model: model,controller: self))
        host.frame = toolbar.bounds; host.autoresizingMask = [.width,.height]; toolbar.addSubview(host)
        let x = min(screen.frame.width-width-12,max(12,placement.midX-width/2))
        let below = placement.maxY+12
        let y = below+104 < screen.frame.height-40 ? below : max(40,placement.minY-116)
        toolbar.setFrameOrigin(CGPoint(x: x,y: y)); canvas.addSubview(toolbar)
        window.keyHandler = { [weak self] in self?.handle($0) ?? false }
        canvas.copyRequested = { [weak self] in self?.onCopy?() }
        canvas.saveRequested = { [weak self] in self?.onSave?() }
        canvas.action = { [weak self] in self?.handle($0) ?? false }
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas) }
    func close() { canvas.finishText(cancel: true); window.close() }
    func selectTool(_ tool: Tool) { canvas.finishText(); model.selectedID = nil; model.tool = tool; model.changed(); window.makeKey(); window.makeFirstResponder(canvas) }
    func rendered() throws -> CGImage { canvas.finishText(); return try ImageRenderer.render(image: model.session.image,state: model.session.state) }
    func handle(_ event: NSEvent) -> Bool {
        if (window.firstResponder is NSTextView && canvas.textField != nil) { return false }
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
    unowned let controller: EditorController
    func icon(_ symbol: String, _ label: String, selected: Bool = false, tooltip: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14,weight: .medium)).frame(width: 29,height: 29)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear,in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(label).toolbarTip(controller.tips, label, detail: tooltip)
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(Tool.allCases,id: \.self) { tool in icon(tool.symbol,tool.title,selected: model.tool == tool,tooltip: tool.helpText) { controller.selectTool(tool) } }
                Spacer(minLength: 4)
                icon("arrow.uturn.backward",tr("Undo", "Отменить"),tooltip: tr("Undo the last change (⌘Z)", "Отменить последнее изменение (⌘Z)")) { model.undo() }.disabled(!model.session.canUndo)
                icon("arrow.uturn.forward",tr("Redo", "Повторить"),tooltip: tr("Redo the last undone change (⇧⌘Z)", "Вернуть последнее отменённое изменение (⇧⌘Z)")) { model.redo() }.disabled(!model.session.canRedo)
                Divider().frame(height: 20)
                icon("xmark",tr("Cancel", "Отмена"),tooltip: tr("Close the editor without keeping the screenshot (Esc)", "Закрыть редактор без сохранения снимка (Esc)")) { controller.onCancel?() }
            }
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                ColorPicker(tr("Color", "Цвет"),selection: $model.color,supportsOpacity: false).labelsHidden().frame(width: 30)
                    .toolbarTip(controller.tips, tr("Color", "Цвет"),detail: tr("Choose the color for annotations", "Выбрать цвет пометок"))
                if [.text,.step].contains(model.tool) || selectedTool == .text || selectedTool == .step {
                    Text("Aa").font(.system(size: 12)); Slider(value: $model.fontSize,in: 10...100).frame(width: 72).accessibilityLabel(tr("Text size", "Размер текста"))
                        .toolbarTip(controller.tips, tr("Text size", "Размер текста"))
                    Toggle("B",isOn: $model.bold).toggleStyle(.button).fontWeight(.bold).accessibilityLabel(tr("Bold", "Полужирный"))
                        .toolbarTip(controller.tips, tr("Bold", "Полужирный"),detail: tr("Use bold text", "Сделать текст полужирным"))
                } else if [.blur,.pixelate].contains(model.tool) || selectedTool == .blur || selectedTool == .pixelate {
                    Image(systemName: "slider.horizontal.3"); Slider(value: $model.strength,in: 4...60).frame(width: 92).accessibilityLabel(tr("Effect intensity", "Интенсивность эффекта"))
                        .toolbarTip(controller.tips, tr("Blur or pixelation intensity", "Интенсивность размытия или пикселизации"))
                } else {
                    Image(systemName: "lineweight").font(.system(size: 12)); Slider(value: $model.width,in: 1...24).frame(width: 72).accessibilityLabel(tr("Stroke width", "Толщина линии"))
                        .toolbarTip(controller.tips, tr("Stroke width", "Толщина линии"))
                    if [.rectangle,.ellipse].contains(model.tool) || selectedTool == .rectangle || selectedTool == .ellipse {
                        Toggle(tr("Fill", "Заливка"),isOn: $model.filled).toggleStyle(.button).font(.system(size: 11))
                            .toolbarTip(controller.tips, tr("Fill", "Заливка"),detail: tr("Fill the shape with the selected color", "Залить фигуру выбранным цветом"))
                    }
                }
                Spacer(minLength: 2)
                if model.ocrBusy { ProgressView().controlSize(.small) }
                icon("text.viewfinder",tr("Recognize text", "Распознать текст"),tooltip: tr("Extract text from the screenshot", "Извлечь текст из снимка")) { controller.onOCR?() }.disabled(model.ocrBusy)
                icon("pin",tr("Pin above windows", "Закрепить поверх окон"),tooltip: tr("Keep the finished screenshot visible above other windows", "Оставить готовый снимок поверх других окон")) { controller.onPin?() }
                icon("square.and.arrow.down",tr("Save…", "Сохранить…"),tooltip: tr("Save the finished screenshot to a file (⌘S)", "Сохранить готовый снимок в файл (⌘S)")) { controller.onSave?() }
                Button { controller.onCopy?() } label: {
                    Label(tr("Copy", "Копировать"),systemImage: "doc.on.doc").font(.system(size: 12,weight: .semibold)).padding(.horizontal,6).padding(.vertical,4)
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .toolbarTip(controller.tips, tr("Copy", "Копировать"),detail: tr("Copy the finished image and close the editor (⌘C)", "Скопировать готовый снимок и закрыть редактор (⌘C)"))
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
