import AppKit
import SwiftUI
import Observation
import SnapMarkCore

@Observable final class Settings {
    static let shared = Settings()
    var language: String { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    var theme: String { didSet { UserDefaults.standard.set(theme, forKey: "theme"); applyAppearance() } }
    var historyLimit: Int { didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") } }
    var keyCode: UInt32 { didSet { UserDefaults.standard.set(Int(keyCode), forKey: "keyCode") } }
    var modifiers: UInt32 { didSet { UserDefaults.standard.set(Int(modifiers), forKey: "modifiers") } }
    init() {
        let d = UserDefaults.standard
        language = d.string(forKey: "language") ?? "system"
        theme = d.string(forKey: "theme") ?? "system"
        historyLimit = max(1, d.object(forKey: "historyLimit") as? Int ?? 100)
        keyCode = UInt32(d.object(forKey: "keyCode") as? Int ?? 19)
        modifiers = UInt32(d.object(forKey: "modifiers") as? Int ?? 4608)
    }
    var russian: Bool { language == "ru" || (language == "system" && Locale.preferredLanguages.first?.hasPrefix("ru") == true) }
    func applyAppearance() {
        NSApp.appearance = theme == "dark" ? NSAppearance(named: .darkAqua) : theme == "light" ? NSAppearance(named: .aqua) : nil
    }
}
func tr(_ en: String, _ ru: String) -> String { Settings.shared.russian ? ru : en }

extension Tool {
    var title: String {
        switch self {
        case .select: tr("Select", "Выделение")
        case .pen: tr("Pen", "Перо")
        case .highlighter: tr("Highlighter", "Маркер")
        case .line: tr("Line", "Линия")
        case .arrow: tr("Arrow", "Стрелка")
        case .rectangle: tr("Rectangle", "Прямоугольник")
        case .ellipse: tr("Ellipse", "Эллипс")
        case .text: tr("Text", "Текст")
        case .step: tr("Numbered step", "Номер шага")
        case .blur: tr("Blur", "Блюр")
        case .pixelate: tr("Pixelate", "Пикселизация")
        case .conceal: tr("Conceal", "Закрыть заливкой")
        case .crop: tr("Crop", "Обрезка")
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"; case .pen: "pencil.tip"; case .highlighter: "highlighter"
        case .line: "line.diagonal"; case .arrow: "arrow.up.right"; case .rectangle: "rectangle"
        case .ellipse: "circle"; case .text: "textformat"; case .step: "1.circle"
        case .blur: "drop.halffull"; case .pixelate: "square.grid.3x3.fill"; case .conceal: "rectangle.fill"; case .crop: "crop"
        }
    }
}

@Observable final class EditorModel {
    let session: EditSession
    var tool: Tool = .arrow
    var color: Color = .blue
    var width: Double = 4
    var fontSize: Double = 28
    var strength: Double = 16
    var filled = false
    var bold = false
    var revision = 0
    var selectedID: UUID?
    var ocrBusy = false
    var status = ""
    var onChange: (() -> Void)?
    init(image: CGImage) { session = EditSession(image: image) }
    func annotation(at point: CGPoint) -> Annotation {
        var a = Annotation(tool: tool, points: [point])
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        a.color = RGBA(red: c.redComponent,green: c.greenComponent,blue: c.blueComponent,alpha: c.alphaComponent)
        a.width = width; a.fontSize = fontSize; a.strength = strength; a.filled = filled; a.bold = bold
        a.number = (session.state.annotations.filter { $0.tool == .step }.map(\.number).max() ?? 0)+1
        return a
    }
    func changed() { revision += 1; onChange?() }
    func undo() { session.undo(); selectedID = nil; changed() }
    func redo() { session.redo(); selectedID = nil; changed() }
    func select(_ a: Annotation?) {
        selectedID = a?.id
        if let a { color = Color(nsColor: a.color.nsColor); width = a.width; fontSize = a.fontSize; strength = a.strength; filled = a.filled; bold = a.bold }
        changed()
    }
    func applyStyle() {
        guard let id = selectedID, let i = session.state.annotations.firstIndex(where: { $0.id == id }) else { return }
        var state = session.state
        let style = annotation(at: .zero)
        state.annotations[i].color = style.color; state.annotations[i].width = style.width
        state.annotations[i].fontSize = style.fontSize; state.annotations[i].strength = style.strength
        state.annotations[i].filled = style.filled; state.annotations[i].bold = style.bold
        session.commit(state); changed()
    }
    func deleteSelected() {
        guard let id = selectedID else { return }
        var state = session.state; state.annotations.removeAll { $0.id == id }; session.commit(state); selectedID = nil; changed()
    }
}
