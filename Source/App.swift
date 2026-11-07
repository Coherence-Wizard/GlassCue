import AppKit
import SwiftUI
import Carbon
import Combine

struct ControlView: View {
    @ObservedObject var model: CueModel
    private let mint = Color(red: 0.56, green: 0.94, blue: 0.78)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "text.viewfinder").font(.system(size: 30, weight: .light)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlassCue").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Your words. Your pace.").foregroundStyle(.secondary).font(.system(size: 12))
                }
                Spacer()
                Text("ON-DEVICE · PRIVATE").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(mint).padding(10).background(mint.opacity(0.08), in: Capsule())
            }.padding(.horizontal, 28).padding(.vertical, 23)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                scriptPane.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView { settings.padding(24) }.frame(width: 330)
            }
            Divider()
            HStack(spacing: 16) {
                Circle().fill(model.isRunning ? mint : Color.secondary).frame(width: 7, height: 7)
                Text(model.status).font(.system(size: 12)).lineLimit(2)
                Spacer()
                Text("⌃⌥ Space  start / pause").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(Color(red: 0.065, green: 0.08, blue: 0.085))
        .preferredColorScheme(.dark).tint(mint)
        .frame(minWidth: 880, minHeight: 690)
        .alert("GlassCue", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    var scriptPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("YOUR SCRIPT").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.follower.words.count) words").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                Button(action: model.chooseFile) { Label("Link Markdown…", systemImage: "link") }
                if !model.linkedPath.isEmpty {
                    Button("Detach") { model.detach() }.help("Keep a local copy to edit here. Your note is never changed.")
                }
                Spacer()
                if model.linkedPath.isEmpty {
                    Button("Paste") {
                        if let text = NSPasteboard.general.string(forType: .string) { model.source = text }
                    }
                }
            }.buttonStyle(.bordered)
            if !model.linkedPath.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: model.linkedPath).lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(model.fileStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).help(model.linkedPath)
            }
            TextEditor(text: $model.source)
                .font(.system(size: 17)).lineSpacing(6)
                .scrollContentBackground(.hidden).padding(14)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                .disabled(!model.linkedPath.isEmpty)
                .accessibilityLabel("Script editor")
            Text(model.linkedPath.isEmpty ? "Paste or type your script. Markdown formatting is cleaned up in the floating text." : "Edit this note in Obsidian. GlassCue watches for changes and never writes to your vault.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("SCRIPT PROGRESS"); Spacer(); Text("\(Int(model.progress * 100))%") }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                ProgressView(value: model.progress).tint(mint)
                if !model.heard.isEmpty {
                    Text("Heard: “\(model.heard)”").font(.system(size: 12)).foregroundStyle(mint.opacity(0.8)).lineLimit(2).frame(height: 34, alignment: .topLeading)
                }
            }.padding(.top, 4)
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 12) {
                caption("FOLLOW YOUR VOICE")
                Picker("Scrolling", selection: $model.mode) {
                    Text("Voice follow").tag("Voice follow")
                    Text("Auto scroll").tag("Auto scroll")
                }.pickerStyle(.segmented).labelsHidden()
                if model.mode == "Voice follow" {
                    Text("Go off script. Take your time. Scrolling resumes when your words match the script again.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Picker("Language", selection: $model.locale) {
                        Text("English (US)").tag("en-US")
                        Text("English (UK)").tag("en-GB")
                        Text("Español").tag("es-ES")
                        Text("Français").tag("fr-FR")
                        Text("Deutsch").tag("de-DE")
                    }.font(.system(size: 12)).disabled(model.isRunning || model.isPreparing)
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").foregroundStyle(.secondary)
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(mint).frame(width: max(0, g.size.width * CGFloat(model.micLevel)))
                        }.frame(height: 4)
                        Text("System input").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else { slider("Scroll speed", value: $model.speed, range: 10...160, suffix: "pt/s") }
                Button(action: model.toggleRunning) {
                    HStack {
                        Image(systemName: model.isRunning || model.isPreparing ? "pause.fill" : "mic.fill")
                        Text(model.isPreparing ? "Cancel preparation" : model.isRunning ? "Pause" : model.mode == "Voice follow" ? "Start listening" : "Start scrolling")
                    }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.plain).foregroundStyle(.black).background(mint, in: RoundedRectangle(cornerRadius: 10))
                Button(action: model.rewind) { Label("Back to beginning", systemImage: "backward.end") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                caption("FLOATING TEXT")
                slider("Text size", value: $model.fontSize, range: 20...90, suffix: "pt")
                VStack(spacing: 5) {
                    slider("Reading position", value: $model.focusPosition, range: 0.1...0.8, suffix: "%", scale: 100)
                    HStack { Text("Higher"); Spacer(); Text("Lower") }.font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("Move the active line up or down in the floating window.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                slider("Text opacity", value: $model.textOpacity, range: 0.3...1, suffix: "%", scale: 100)
                slider("Background", value: $model.shade, range: 0...0.85, suffix: "%", scale: 100)
                Text(model.shade < 0.01 ? "Fully transparent · only your words are visible" : "A subtle backing for brighter screens")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Button(action: model.toggleOverlay) { Label(model.overlayVisible ? "Hide overlay" : "Show overlay", systemImage: "rectangle.on.rectangle") }
                    Spacer()
                }
                Toggle("Position & resize", isOn: $model.positioning).toggleStyle(.switch).font(.system(size: 12))
                Text(model.positioning ? "Drag the overlay’s top bar or bottom corner. Click a word to set your place." : "Click-through is on. Use the apps beneath your script normally.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                caption("FROM ANY APP")
                shortcut("Start / pause", "⌃⌥ Space")
                shortcut("Show / hide overlay", "⌃⌥ O")
                shortcut("Close overlay", "Esc")
                shortcut("Position / click-through", "⌃⌥ L")
                shortcut("Back to beginning", "⌃⌥ R")
                if !model.hotkeyWarning.isEmpty { Text(model.hotkeyWarning).font(.system(size: 10)).foregroundStyle(.orange) }
            }
        }
    }
    func caption(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary) }
    func shortcut(_ title: String, _ keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)) }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
    func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, scale: Double = 1) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue * scale))\(suffix)").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 12))
            Slider(value: value, in: range)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: CueModel!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hotkeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    var escapeHotkey: EventHotKeyRef?
    var overlaySubscription: AnyCancellable?
    var localEscapeMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = CueModel()
        createMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GlassCue"
        window.contentView = NSHostingView(rootView: ControlView(model: model))
        window.minSize = NSSize(width: 900, height: 730)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); window.setFrameAutosaveName("GlassCueControls")
        showControls()
        registerHotkeys()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControls(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(); hotkeys.forEach { UnregisterEventHotKey($0) }
        if let escapeHotkey { UnregisterEventHotKey(escapeHotkey) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let path = filenames.first { model.link(URL(fileURLWithPath: path)); showControls() }
    }
    @objc func showControls() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggle() { model.toggleRunning() }
    @objc func showOverlay() { model.toggleOverlay() }
    @objc func lock() { model.positioning.toggle() }
    @objc func rewind() { model.rewind() }
    @objc func openFile() { model.chooseFile() }
    func createMenus() {
        let bar = NSMenu()
        let root = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About GlassCue", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit GlassCue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; bar.addItem(root)
        let file = NSMenuItem(); file.title = "File"; file.submenu = NSMenu(title: "File")
        let open = file.submenu!.addItem(withTitle: "Link Markdown…", action: #selector(openFile), keyEquivalent: "o"); open.target = self
        bar.addItem(file)
        let edit = NSMenuItem(); edit.title = "Edit"; edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu!.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        bar.addItem(edit); NSApp.mainMenu = bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "GlassCue")
        let menu = NSMenu()
        for (title, action) in [("GlassCue Controls…", #selector(showControls)), ("Start / Pause", #selector(toggle)), ("Show / Hide Overlay", #selector(showOverlay)), ("Position / Click-through", #selector(lock)), ("Back to Beginning", #selector(rewind))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit GlassCue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }
    func registerHotkeys() {
        // App-local delivery covers focused text editors and accessibility-driven events,
        // which can bypass the system's global-hotkey dispatch.
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.overlayVisible,
                  event.keyCode == UInt16(kVK_Escape),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            self.model.hideOverlay()
            return nil
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            let app = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated {
                switch key.id {
                case 1: app.toggle()
                case 2: app.showOverlay()
                case 3: app.lock()
                case 4: app.rewind()
                case 5: app.model.hideOverlay()
                default: break
                }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        for (index, code) in [kVK_Space, kVK_ANSI_O, kVK_ANSI_L, kVK_ANSI_R].enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x474C4355, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotkeys.append(ref) }
            else { model.hotkeyWarning = "A shortcut is already in use. All actions remain available in the menu bar." }
        }
        // Claim Escape only while the overlay is visible. Once dismissed, other apps
        // receive Escape normally again, including when GlassCue remains running.
        overlaySubscription = model.$overlayVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            if let ref = self.escapeHotkey { UnregisterEventHotKey(ref); self.escapeHotkey = nil }
            guard visible else { return }
            let result = RegisterEventHotKey(UInt32(kVK_Escape), 0,
                EventHotKeyID(signature: 0x474C4355, id: 5),
                GetApplicationEventTarget(), 0, &self.escapeHotkey)
            if result != noErr {
                self.model.hotkeyWarning = "Escape is reserved by another app. Use Control–Option–O or the × button to close the overlay."
            }
        }
    }
}
