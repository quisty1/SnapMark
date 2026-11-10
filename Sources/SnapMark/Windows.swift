import AppKit
import SwiftUI
import Carbon
import SnapMarkCore

struct WelcomeView: View {
    let capture: () -> Void
    let sample: () -> Void
    let history: () -> Void
    let settings: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "viewfinder").font(.system(size: 48,weight: .light)).foregroundStyle(.blue).padding(.top,10)
            VStack(spacing: 6) {
                Text("SnapMark").font(.system(size: 30,weight: .semibold,design: .rounded))
                Text(tr("Capture. Mark. Share.", "Сними. Отметь. Поделись.")).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Text(tr("Capture an area, annotate it and copy the result.\nYour screenshots and recognized text stay on this Mac.", "Выдели область, добавь пометки и скопируй результат.\nСкриншоты и распознанный текст остаются на этом Mac."))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false,vertical: true)
            Button(action: capture) { Label(tr("Take a screenshot", "Сделать скриншот"),systemImage: "plus").padding(.horizontal,14).padding(.vertical,5) }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing: 24) { Button(tr("Try the editor", "Попробовать редактор"),action: sample); Button(tr("History", "История"),action: history); Button(tr("Settings", "Настройки"),action: settings) }.buttonStyle(.link).font(.system(size: 12))
            Text(tr("Available in the menu bar · Esc cancels capture", "Всегда в строке меню · Esc отменяет захват")).font(.system(size: 11)).foregroundStyle(.tertiary)
        }.padding(30).frame(width: 520,height: 410).tint(.blue)
    }
}
struct SettingsView: View {
    @Bindable var settings = Settings.shared
    let languageChanged: () -> Void
    let recordShortcut: () -> Void
    let resetShortcut: () -> Void
    let trim: () -> Void
    let shortcutLabel: () -> String
    var body: some View {
        Form {
            Section(tr("Appearance", "Внешний вид")) {
                Picker(tr("Language", "Язык"),selection: $settings.language) {
                    Text(tr("System", "Системный")).tag("system"); Text("Русский").tag("ru"); Text("English").tag("en")
                }
                Picker(tr("Theme", "Тема"),selection: $settings.theme) {
                    Text(tr("System", "Системная")).tag("system"); Text(tr("Light", "Светлая")).tag("light"); Text(tr("Dark", "Тёмная")).tag("dark")
                }
            }
            Section(tr("Capture", "Захват")) {
                HStack {
                    Text(tr("Global shortcut", "Горячая клавиша")); Spacer()
                    Button(shortcutLabel(),action: recordShortcut).font(.system(.body,design: .monospaced))
                    Button(tr("Reset", "Сбросить"),action: resetShortcut)
                }
                Text(tr("Click the shortcut and press a new combination with Control, Option or Command.", "Нажми на сочетание и введи новое с Control, Option или Command.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("Local history", "Локальная история")) {
                Stepper(value: $settings.historyLimit,in: 1...1000,step: 10) {
                    Text(tr("Keep up to \(settings.historyLimit) screenshots", "Хранить до \(settings.historyLimit) снимков"))
                }.onChange(of: settings.historyLimit) { trim() }
                Text(tr("Only finished images are saved. Original pixels and editable annotations are not retained. Older images are removed when the limit is reached.", "Сохраняются только готовые картинки. Исходники и редактируемые объекты не хранятся. При достижении лимита старые снимки удаляются.")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8).frame(width: 530,height: 410).onChange(of: settings.language) { languageChanged() }
    }
}
final class ShortcutRecorder: NSView {
    var onRecord: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        guard !event.modifierFlags.intersection([.control,.option,.command]).isEmpty else { NSSound.beep(); return }
        onRecord?(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
}
struct HistoryView: View {
    let store: HistoryStore
    @State var selected: UUID?
    let copy: (HistoryEntry) -> Void
    let save: (HistoryEntry) -> Void
    let edit: (HistoryEntry) -> Void
    let pin: (HistoryEntry) -> Void
    let delete: (HistoryEntry) -> Void
    let clear: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("History", "История")).font(.title2.weight(.semibold))
                Text("\(store.entries.count)").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button(tr("Clear history…", "Очистить историю…"),action: clear).disabled(store.entries.isEmpty)
            }.padding(18)
            Divider()
            if store.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 38,weight: .light)).foregroundStyle(.secondary)
                    Text(tr("Your finished screenshots will appear here", "Здесь появятся готовые снимки")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selected) {
                        ForEach(store.entries) { e in
                            HStack(spacing: 10) {
                                if let image = NSImage(contentsOf: store.thumbnailURL(e)) { Image(nsImage: image).resizable().scaledToFit().frame(width: 66,height: 48).clipShape(RoundedRectangle(cornerRadius: 4)) }
                                VStack(alignment: .leading,spacing: 4) {
                                    Text(e.date,format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 12,weight: .medium))
                                    Text("\(e.width) × \(e.height)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical,4).tag(e.id)
                        }
                    }.frame(minWidth: 230,idealWidth: 250,maxWidth: 300)
                    if let e = store.entries.first(where: { $0.id == selected }) ?? store.entries.first {
                        VStack(spacing: 16) {
                            if let image = NSImage(contentsOf: store.imageURL(e)) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity,maxHeight: .infinity).padding(18)
                            }
                            HStack {
                                Button { edit(e) } label: { Label(tr("Annotate", "Пометки"),systemImage: "pencil") }
                                Button { pin(e) } label: { Image(systemName: "pin") }.help(tr("Pin", "Закрепить"))
                                Button { save(e) } label: { Image(systemName: "square.and.arrow.down") }.help(tr("Save", "Сохранить"))
                                Button(role: .destructive) { delete(e) } label: { Image(systemName: "trash") }.help(tr("Delete", "Удалить"))
                                Spacer()
                                Button { copy(e) } label: { Label(tr("Copy", "Копировать"),systemImage: "doc.on.doc") }.buttonStyle(.borderedProminent)
                            }.controlSize(.small).padding([.horizontal,.bottom],18)
                        }.frame(minWidth: 420,maxWidth: .infinity,maxHeight: .infinity)
                    }
                }
            }
        }.frame(minWidth: 740,minHeight: 450).tint(.blue)
    }
}
struct PinnedView: View {
    let image: NSImage
    let copy: () -> Void
    let close: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity,maxHeight: .infinity)
            HStack(spacing: 6) {
                Button(action: copy) { Image(systemName: "doc.on.doc") }.help(tr("Copy", "Копировать"))
                Button(action: close) { Image(systemName: "xmark") }.help(tr("Close", "Закрыть"))
            }.buttonStyle(.bordered).controlSize(.small).padding(8)
        }
    }
}
