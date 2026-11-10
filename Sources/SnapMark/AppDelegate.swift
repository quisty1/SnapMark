import AppKit
import SwiftUI
import Carbon
import SnapMarkCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let capture = CaptureCoordinator()
    let hotKey = HotKey()
    var statusItem: NSStatusItem!
    var history: HistoryStore?
    var editor: EditorController?
    var captureTask: Task<Void,Never>?
    var ocrTask: Task<Void,Never>?
    var recognizeImage: @Sendable (CGImage) async throws -> OCRResult = { try await OCRService.recognize($0) }
    var ocrGeneration: UUID?
    var ocrWindow: OCRPanel?
    var welcomeWindow: NSWindow?
    var settingsWindow: NSWindow?
    var historyWindow: NSWindow?
    var recorderWindow: NSWindow?
    var pinned: [NSWindow] = []
    var previousApp: NSRunningApplication?
    var pendingHistoryImage: CGImage?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Settings.shared.applyAppearance(); setupMainMenu()
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,in: .userDomainMask,appropriateFor: nil,create: true).appendingPathComponent("SnapMark",isDirectory: true)
            history = try HistoryStore(directory: directory)
        } catch { showError(error,title: tr("History could not be opened. Existing files were preserved.", "Не удалось открыть историю. Существующие файлы сохранены.")) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder",accessibilityDescription: "SnapMark")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        hotKey.action = { [weak self] in self?.requestCapture() }
        let result = hotKey.register(code: Settings.shared.keyCode,modifiers: Settings.shared.modifiers)
        if result != noErr { showMessage(tr("Shortcut unavailable", "Сочетание недоступно"),tr("Choose another shortcut in Settings. Capture is still available from the menu bar.", "Выбери другое сочетание в настройках. Захват доступен через строку меню.")) }
        capture.onError = { [weak self] error in self?.showError(error,title: tr("Could not capture the window", "Не удалось снять окно")) }
        capture.onImage = { [weak self] image, placement, snapshot in self?.openEditor(image: image,placement: placement,screen: snapshot.screen,background: snapshot) }
        if ProcessInfo.processInfo.arguments.contains("--demo") { openDemo() }
        else { showWelcome() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let editor { editor.show(); return false }
        if let panel = capture.panels.first { panel.makeKeyAndOrderFront(nil); return false }
        if flag { return true }
        showWelcome(); return false
    }
    func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        let quit = NSMenuItem(title: tr("Quit SnapMark", "Завершить SnapMark"),action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q"); appMenu.addItem(quit)
        let file = NSMenuItem(title: tr("File", "Файл"),action: nil,keyEquivalent: ""); let fm = NSMenu(); file.submenu = fm; main.addItem(file)
        let captureItem = NSMenuItem(title: tr("Take a screenshot", "Сделать скриншот"),action: #selector(captureArea),keyEquivalent: "n"); captureItem.target = self; fm.addItem(captureItem)
        fm.addItem(NSMenuItem(title: tr("Close window", "Закрыть окно"),action: #selector(NSWindow.performClose(_:)),keyEquivalent: "w"))
        fm.addItem(NSMenuItem(title: tr("Save…", "Сохранить…"),action: NSSelectorFromString("saveDocument:"),keyEquivalent: "s"))
        let edit = NSMenuItem(title: tr("Edit", "Правка"),action: nil,keyEquivalent: ""); main.addItem(edit)
        let em = NSMenu(); edit.submenu = em
        for (en,ru,selector,key) in [("Undo","Отменить","undo:","z"),("Redo","Повторить","redo:","Z"),("Cut","Вырезать","cut:","x"),("Copy","Копировать","copy:","c"),("Paste","Вставить","paste:","v"),("Select All","Выделить всё","selectAll:","a")] {
            em.addItem(NSMenuItem(title: tr(en,ru),action: NSSelectorFromString(selector),keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ selector: Selector) { let i = NSMenuItem(title: title,action: selector,keyEquivalent: ""); i.target = self; menu.addItem(i) }
        add(tr("Capture area", "Снять область") + "   " + shortcutLabel(),#selector(captureArea))
        add(tr("Capture window", "Снять окно"),#selector(captureWindow))
        add(tr("Capture display", "Снять экран"),#selector(captureDisplay))
        menu.addItem(.separator())
        add(tr("History…", "История…"),#selector(showHistory))
        if (history?.pendingDeletionCount ?? 0) > 0 { add(tr("Retry deleting history files", "Повторить удаление файлов истории"),#selector(retryDeletion)) }
        if pendingHistoryImage != nil { add(tr("Retry saving to history", "Повторить запись в историю"),#selector(retryHistory)) }
        add(tr("Settings…", "Настройки…"),#selector(showSettings))
        add(tr("About SnapMark", "О SnapMark"),#selector(showWelcome))
        menu.addItem(.separator()); add(tr("Quit SnapMark", "Завершить SnapMark"),#selector(quit))
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func captureArea() { requestCapture() }
    @objc func captureWindow() { requestCapture(windowMode: true) }
    @objc func captureDisplay() { requestCapture(fullDisplay: true) }
    func requestCapture(fullDisplay: Bool = false, windowMode: Bool = false) {
        guard captureTask == nil, capture.panels.isEmpty else { return }
        if let editor {
            editor.show()
            let alert = NSAlert(); alert.messageText = tr("A screenshot is being edited", "Снимок уже открыт")
            alert.informativeText = tr("Finish this screenshot or discard it before taking another.", "Заверши текущий снимок или отмени его перед новым захватом.")
            alert.addButton(withTitle: tr("Continue editing", "Продолжить правки")); alert.addButton(withTitle: tr("Discard and capture", "Отменить и снять новый")); alert.addButton(withTitle: tr("Copy and capture", "Скопировать и снять новый"))
            alert.window.level = .screenSaver
            switch alert.runModal() {
            case .alertSecondButtonReturn: closeEditor()
            case .alertThirdButtonReturn: copyEditor(); if self.editor != nil { return }
            default: return
            }
        }
        guard CGPreflightScreenCaptureAccess() else { requestPermission(fullDisplay: fullDisplay,windowMode: windowMode); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        welcomeWindow?.orderOut(nil); historyWindow?.orderOut(nil); settingsWindow?.orderOut(nil)
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { captureTask = nil }
            do { try await capture.start(fullDisplay: fullDisplay,windowMode: windowMode) }
            catch { capture.close(); showError(error,title: tr("Could not capture the screen", "Не удалось снять экран")) }
        }
        capture.onCancel = { [weak self] in self?.restoreFocus() }
    }
    func requestPermission(fullDisplay: Bool,windowMode: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = tr("Allow screen capture", "Разреши захват экрана")
        alert.informativeText = tr("SnapMark needs Screen Recording permission to take screenshots. Images are processed only on this Mac. After enabling permission, return to SnapMark and try again; macOS may ask you to relaunch the app.", "Для скриншотов SnapMark нужен доступ к записи экрана. Изображения обрабатываются только на этом Mac. После выдачи доступа вернись и повтори захват; macOS может попросить перезапустить приложение.")
        alert.addButton(withTitle: tr("Grant access", "Предоставить доступ")); alert.addButton(withTitle: tr("Cancel", "Отмена"))
        if alert.runModal() == .alertFirstButtonReturn {
            if CGRequestScreenCaptureAccess() { requestCapture(fullDisplay: fullDisplay,windowMode: windowMode) }
            else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
        }
    }
    func openEditor(image: CGImage, placement: CGRect, screen: NSScreen, background: DisplaySnapshot?) {
        let e = EditorController(image: image,placement: placement,screen: screen,background: background)
        e.onCopy = { [weak self] in self?.copyEditor() }
        e.onSave = { [weak self] in self?.saveEditor() }
        e.onPin = { [weak self] in self?.pinEditor() }
        e.onOCR = { [weak self] in self?.recognizeText() }
        e.onCancel = { [weak self] in self?.closeEditor(); self?.restoreFocus() }
        e.canvas.onError = { [weak self] error in self?.showError(error) }
        editor = e; e.show()
    }
    func closeEditor() {
        dismissOCR()
        editor?.close(); editor = nil
    }
    func restoreFocus() {
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp.activate(options: []) }
    }
    func copyEditor() {
        guard let editor else { return }
        do { let image = try editor.rendered(); try copyImage(image); closeEditor(); record(image); restoreFocus() }
        catch { showError(error,title: tr("Could not copy the image", "Не удалось скопировать снимок")) }
    }
    func saveEditor() {
        guard let editor else { return }
        do {
            let image = try editor.rendered()
            editor.window.orderOut(nil)
            if save(image) { closeEditor(); record(image); restoreFocus() }
            else { editor.show() }
        } catch { showError(error) }
    }
    func pinEditor() {
        guard let editor else { return }
        do { let image = try editor.rendered(); closeEditor(); pin(image); record(image); restoreFocus() }
        catch { showError(error) }
    }
    @discardableResult func save(_ image: CGImage) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel(); panel.canCreateDirectories = true; panel.isExtensionHidden = false
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "SnapMark \(formatter.string(from: Date())).png"
        let format = ExportFormat(panel: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try (format.jpeg ? ImageRenderer.jpeg(image) : ImageRenderer.png(image)).write(to: url,options: .atomic); return true }
        catch { showError(error,title: tr("Could not save the image", "Не удалось сохранить снимок")); return false }
    }
    func record(_ image: CGImage) {
        guard let history else {
            pendingHistoryImage = image
            showMessage(tr("Image completed; history unavailable", "Снимок готов; история недоступна"),tr("The image was copied, saved or pinned, but could not be added to history. Your existing files were preserved.", "Снимок скопирован, сохранён или закреплён, но не добавлен в историю. Существующие файлы сохранены.")); return
        }
        do { try history.add(image: image,limit: Settings.shared.historyLimit); pendingHistoryImage = nil }
        catch { pendingHistoryImage = image; showError(error,title: tr("Image completed, but history was not saved. Retry from the menu bar.", "Снимок готов, но история не записана. Повтори запись через строку меню.")) }
    }
    @objc func retryDeletion() { do { try history?.retryPendingDeletions() } catch { showError(error) } }
    @objc func retryHistory() {
        guard let image = pendingHistoryImage else { return }
        if history == nil {
            do {
                let dir = try FileManager.default.url(for: .applicationSupportDirectory,in: .userDomainMask,appropriateFor: nil,create: true).appendingPathComponent("SnapMark")
                history = try HistoryStore(directory: dir)
            } catch { showError(error); return }
        }
        record(image)
    }
    func pin(_ image: CGImage) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let factor = min(1,min(560/CGFloat(image.width),420/CGFloat(image.height)))
        let size = CGSize(width: max(160,CGFloat(image.width)*factor),height: max(100,CGFloat(image.height)*factor))
        let window = PinnedWindow(contentRect: CGRect(origin: screen.visibleFrame.center,size: size),styleMask: [.titled,.closable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
        window.title = "SnapMark"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        window.isMovableByWindowBackground = true; window.minSize = CGSize(width: 120,height: 90)
        window.contentView = NSHostingView(rootView: PinnedView(image: NSImage(cgImage: image,size: CGSize(width: image.width,height: image.height)),copy: { [weak self] in
            do { try copyImage(image) } catch { self?.showError(error) }
        },close: { [weak self, weak window] in
            window?.close(); self?.pinned.removeAll { $0 === window }
        }))
        pinned.append(window); window.center(); window.orderFrontRegardless()
        window.didClose = { [weak self, weak window] in self?.pinned.removeAll { $0 === window } }
    }
    func recognizeText() {
        guard let e = editor, !e.model.ocrBusy else { return }
        do {
            let image = try e.rendered(); let generation = UUID(); ocrGeneration = generation; e.model.ocrBusy = true
            showOCR(text: tr("Recognizing text…", "Распознавание текста…"),busy: true)
            ocrTask = Task { [weak self, weak e] in
                guard let self, let e else { return }
                defer { if ocrGeneration == generation { e.model.ocrBusy = false; ocrTask = nil } }
                do {
                    let result = try await recognizeImage(image)
                    guard !Task.isCancelled, editor === e, ocrGeneration == generation else { return }
                    var text = result.text.isEmpty ? tr("No text found.", "Текст не найден.") : result.text
                    if !result.russianAvailable { text += "\n\n" + tr("Russian recognition is unavailable in this system version.", "Распознавание русского недоступно в этой версии системы.") }
                    showOCR(text: text,busy: false,copyText: result.text)
                } catch is CancellationError {} catch { if !Task.isCancelled && ocrGeneration == generation { showOCR(text: tr("Recognition failed: ", "Не удалось распознать текст: ")+error.localizedDescription,busy: false) } }
            }
        } catch { showError(error) }
    }
    func showOCR(text: String,busy: Bool,copyText: String = "") {
        let creating = ocrWindow == nil
        let window = ocrWindow ?? OCRPanel(contentRect: CGRect(x: 0,y: 0,width: 460,height: 300),styleMask: [.titled,.closable,.resizable],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false; window.level = .screenSaver; window.title = tr("Recognized text", "Распознанный текст")
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: OCRView(text: text,busy: busy,copyText: copyText,close: { [weak self] in
            self?.dismissOCR()
        }))
        window.didClose = { [weak self] in self?.dismissOCR() }
        ocrWindow = window; if creating { window.center() }; window.makeKeyAndOrderFront(nil)
    }
    func dismissOCR() {
        ocrGeneration = nil; ocrTask?.cancel(); ocrTask = nil; editor?.model.ocrBusy = false
        let old = ocrWindow; ocrWindow = nil; old?.didClose = nil; old?.close()
    }
    @objc func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = hostedWindow(title: "SnapMark",size: CGSize(width: 520,height: 410),view: WelcomeView(capture: { [weak self] in self?.requestCapture() },sample: { [weak self] in self?.openDemo() },history: { [weak self] in self?.showHistory() },settings: { [weak self] in self?.showSettings() }))
        }
        NSApp.activate(ignoringOtherApps: true); welcomeWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings() {
        let root = SettingsView(languageChanged: { [weak self] in self?.setupMainMenu(); self?.settingsWindow?.title = tr("Settings", "Настройки"); self?.historyWindow?.title = tr("History", "История") },recordShortcut: { [weak self] in self?.recordShortcut() },resetShortcut: { [weak self] in self?.setShortcut(code: 19,modifiers: 4608,label: "2") },trim: { [weak self] in
            do { try self?.history?.trim(limit: Settings.shared.historyLimit) } catch { self?.showError(error) }
        },shortcutLabel: { [weak self] in self?.shortcutLabel() ?? "" })
        if settingsWindow == nil { settingsWindow = hostedWindow(title: tr("Settings", "Настройки"),size: CGSize(width: 530,height: 410),view: root) }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func shortcutLabel() -> String {
        let mods = Settings.shared.modifiers
        return (mods & UInt32(controlKey) != 0 ? "⌃" : "") + (mods & UInt32(optionKey) != 0 ? "⌥" : "") + (mods & UInt32(shiftKey) != 0 ? "⇧" : "") + (mods & UInt32(cmdKey) != 0 ? "⌘" : "") + (UserDefaults.standard.string(forKey: "keyLabel") ?? "2")
    }
    func recordShortcut() {
        let window = KeyPanel(contentRect: CGRect(x: 0,y: 0,width: 420,height: 140),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        window.title = tr("Press a new shortcut · Esc cancels", "Новое сочетание · Esc отменяет")
        window.isReleasedWhenClosed = false
        let view = ShortcutRecorder(frame: CGRect(x: 0,y: 0,width: 420,height: 140))
        let label = NSTextField(labelWithString: tr("Press a key with ⌃, ⌥ or ⌘", "Нажми клавишу вместе с ⌃, ⌥ или ⌘")); label.frame = CGRect(x: 24,y: 55,width: 380,height: 25); view.addSubview(label)
        view.onCancel = { [weak window] in window?.close() }
        view.onRecord = { [weak self, weak window] event in
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            let label = event.charactersIgnoringModifiers?.uppercased() ?? String(event.keyCode)
            if self?.setShortcut(code: UInt32(event.keyCode),modifiers: modifiers,label: label) == true { window?.close() }
        }
        window.contentView = view; recorderWindow = window; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
    }
    @discardableResult func setShortcut(code: UInt32,modifiers: UInt32,label: String) -> Bool {
        guard hotKey.register(code: code,modifiers: modifiers) == noErr else {
            showMessage(tr("Shortcut unavailable", "Сочетание недоступно"),tr("This combination could not be registered. Choose another one. Your previous shortcut is unchanged.", "Не удалось зарегистрировать сочетание. Выбери другое. Предыдущее сочетание сохранено.")); return false
        }
        Settings.shared.keyCode = code; Settings.shared.modifiers = modifiers; UserDefaults.standard.set(label,forKey: "keyLabel"); return true
    }
    @objc func showHistory() {
        guard let history else { showMessage(tr("History unavailable", "История недоступна"),tr("Existing files were preserved. Try restarting SnapMark.", "Существующие файлы сохранены. Попробуй перезапустить SnapMark.")); return }
        if historyWindow == nil {
            let root = HistoryView(store: history,copy: { [weak self] e in self?.withHistoryImage(e) { try copyImage($0) } },save: { [weak self] e in self?.withHistoryImage(e) { _ = self?.save($0) } },edit: { [weak self] e in self?.editHistory(e) },pin: { [weak self] e in self?.withHistoryImage(e) { self?.pin($0) } },delete: { [weak self] e in
                do { try history.delete(e) } catch { self?.showError(error) }
            },clear: { [weak self] in
                let a = NSAlert(); a.messageText = tr("Delete all history?", "Удалить всю историю?"); a.informativeText = tr("Saved screenshots in SnapMark history will be permanently deleted. Exported files are kept.", "Снимки в истории SnapMark будут удалены безвозвратно. Экспортированные файлы сохранятся."); a.addButton(withTitle: tr("Cancel", "Отмена")); a.addButton(withTitle: tr("Delete", "Удалить"))
                if a.runModal() == .alertSecondButtonReturn { do { try history.clear() } catch { self?.showError(error) } }
            })
            historyWindow = hostedWindow(title: tr("History", "История"),size: CGSize(width: 900,height: 620),view: root,resizable: true)
        }
        NSApp.activate(ignoringOtherApps: true); historyWindow?.makeKeyAndOrderFront(nil)
    }
    func withHistoryImage(_ e: HistoryEntry,action: (CGImage) throws -> Void) {
        do {
            guard let url = history?.imageURL(e), let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil,context: nil,hints: nil) else { throw CocoaError(.fileReadCorruptFile) }
            try action(image)
        } catch { showError(error) }
    }
    func editHistory(_ e: HistoryEntry) {
        if let editor { editor.show(); return }
        withHistoryImage(e) { image in
            guard let screen = NSScreen.main else { return }
            historyWindow?.orderOut(nil)
            let factor = min(1,min((screen.frame.width-140)/CGFloat(image.width),(screen.frame.height-240)/CGFloat(image.height)))
            let size = CGSize(width: CGFloat(image.width)*factor,height: CGFloat(image.height)*factor)
            let r = CGRect(x: (screen.frame.width-size.width)/2,y: (screen.frame.height-size.height)/2,width: size.width,height: size.height)
            openEditor(image: image,placement: r,screen: screen,background: nil)
        }
    }
    func hostedWindow<V: View>(title: String,size: CGSize,view: V,resizable: Bool = false) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled,.closable,.miniaturizable]
        if resizable { style.insert(.resizable) }
        let w = NSWindow(contentRect: CGRect(origin: .zero,size: size),styleMask: style,backing: .buffered,defer: false)
        w.title = title; w.isReleasedWhenClosed = false; w.contentView = NSHostingView(rootView: view); w.center(); return w
    }
    func showError(_ error: Error,title: String? = nil) { showMessage(title ?? tr("Something went wrong", "Не удалось выполнить действие"),error.localizedDescription) }
    func showMessage(_ title: String,_ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: tr("OK", "Понятно")); alert.window.level = .screenSaver
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func openDemo() {
        guard editor == nil, let screen = NSScreen.main else { editor?.show(); return }
        welcomeWindow?.orderOut(nil)
        let image = DemoImage.make()
        openEditor(image: image,placement: CGRect(x: 160,y: 170,width: 800,height: 500),screen: screen,background: nil)
    }
}
final class PinnedWindow: NSWindow {
    var didClose: (() -> Void)?
    override func close() { super.close(); didClose?() }
}
final class OCRPanel: KeyPanel {
    var didClose: (() -> Void)?
    override func close() { super.close(); didClose?() }
}
struct OCRView: View {
    let text: String
    let busy: Bool
    let copyText: String
    let close: () -> Void
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            if busy { ProgressView().controlSize(.small) }
            ScrollView { Text(text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity,alignment: .leading).padding(4) }.frame(maxWidth: .infinity,maxHeight: .infinity)
            HStack {
                Button(tr(busy ? "Cancel" : "Close",busy ? "Отмена" : "Закрыть"),action: close)
                Spacer()
                if !copyText.isEmpty {
                    Button(tr(copied ? "Copied" : "Copy text",copied ? "Скопировано" : "Скопировать текст")) {
                        NSPasteboard.general.clearContents(); copied = NSPasteboard.general.setString(copyText,forType: .string)
                    }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(20).frame(minWidth: 350,minHeight: 220).tint(.blue)
    }
}
enum DemoImage {
    static func make() -> CGImage {
        let image = NSImage(size: CGSize(width: 1600,height: 1000))
        image.lockFocus()
        NSColor(srgbRed: 0.96,green: 0.97,blue: 0.99,alpha: 1).setFill(); CGRect(x: 0,y: 0,width: 1600,height: 1000).fill()
        NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: 110,y: 130,width: 1380,height: 740),xRadius: 30,yRadius: 30).fill()
        ("A clearer way to share." as NSString).draw(at: CGPoint(x: 190,y: 690),withAttributes: [.font: NSFont.systemFont(ofSize: 64,weight: .semibold),.foregroundColor: NSColor.black])
        ("Capture an idea. Make your point.\nСкриншоты с понятными пометками." as NSString).draw(in: CGRect(x: 195,y: 500,width: 1200,height: 150),withAttributes: [.font: NSFont.systemFont(ofSize: 36),.foregroundColor: NSColor.darkGray])
        NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: CGRect(x: 195,y: 340,width: 350,height: 92),xRadius: 20,yRadius: 20).fill()
        ("Get started" as NSString).draw(at: CGPoint(x: 248,y: 366),withAttributes: [.font: NSFont.systemFont(ofSize: 32,weight: .medium),.foregroundColor: NSColor.white])
        ("Email: example@sample.test" as NSString).draw(at: CGPoint(x: 195,y: 220),withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 25,weight: .regular),.foregroundColor: NSColor.gray])
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil,context: nil,hints: nil)!
    }
}
