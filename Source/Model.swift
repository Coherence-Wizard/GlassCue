import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor final class CueModel: ObservableObject {
    static let sample = """
    Welcome to GlassCue.

    This teleprompter follows the words I say, at my own pace.

    I can pause, take a breath, or wander off script. The text will hold its place until I return to a matching phrase.

    Now I am back on script, and the teleprompter can follow me again.

    I can paste my own text here, or link a Markdown note from my Obsidian vault.

    My script floats over my recording software, so I can keep an eye on the camera while I speak.

    There is no hurry. Just one thought at a time.
    """
    @Published var source: String { didSet { updateScript(); save() } }
    @Published var linkedPath: String { didSet { save() } }
    @Published var fontSize: Double { didSet { overlay?.refresh(); save() } }
    @Published var focusPosition: Double { didSet { overlay?.refresh(); save() } }
    @Published var shade: Double { didSet { overlay?.refresh(); save() } }
    @Published var textOpacity: Double { didSet { overlay?.refresh(); save() } }
    @Published var speed: Double { didSet { save() } }
    @Published var mode = "Voice follow" { didSet { stop() } }
    @Published var locale = "en-US" { didSet { stop(); save() } }
    @Published var isRunning = false
    @Published var isPreparing = false
    @Published var overlayVisible = false
    @Published var positioning = true { didSet { overlay?.refresh() } }
    @Published var status = "Ready when you are"
    @Published var fileStatus = ""
    @Published var heard = ""
    @Published var micLevel: Float = 0
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var hotkeyWarning = ""
    private(set) var plain = ""
    let follower = PhraseFollower("")
    let voice = VoiceEngine()
    var overlay: OverlayController?
    private var fileTimer: Timer?
    private var startup: Task<Void, Never>?
    private var lastFileContent: String?
    private let defaults: UserDefaults
    private var lastMatch = Date.distantPast

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        source = defaults.string(forKey: "script") ?? Self.sample
        linkedPath = defaults.string(forKey: "linkedPath") ?? ""
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 38
        focusPosition = min(0.8, max(0.1, defaults.object(forKey: "focusPosition") as? Double ?? 0.28))
        shade = defaults.object(forKey: "shade") as? Double ?? 0
        textOpacity = defaults.object(forKey: "textOpacity") as? Double ?? 1
        speed = defaults.object(forKey: "speed") as? Double ?? 38
        locale = defaults.string(forKey: "locale") ?? "en-US"
        updateScript()
        voice.onText = { [weak self] text in self?.handleTranscript(text) }
        voice.onStatus = { [weak self] text in self?.status = text }
        voice.onError = { [weak self] text in self?.stop(); self?.errorMessage = text }
        voice.onLevel = { [weak self] level in self?.micLevel = level }
        fileTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadFile()
                if let self, self.isRunning, self.mode == "Voice follow", Date().timeIntervalSince(self.lastMatch) > 3 {
                    self.status = "Listening · holding your place"
                }
            }
        }
        reloadFile()
    }
    func save() {
        defaults.set(source, forKey: "script"); defaults.set(linkedPath, forKey: "linkedPath")
        defaults.set(fontSize, forKey: "fontSize"); defaults.set(shade, forKey: "shade")
        defaults.set(focusPosition, forKey: "focusPosition")
        defaults.set(textOpacity, forKey: "textOpacity"); defaults.set(speed, forKey: "speed"); defaults.set(locale, forKey: "locale")
    }
    func updateScript() {
        let cleaned = ScriptText.plain(source)
        guard cleaned != plain else { return }
        if isRunning || isPreparing { stop() }
        plain = cleaned; follower.reset(plain); progress = 0
        overlay?.refresh(reset: true)
    }
    func handleTranscript(_ text: String) {
        guard isRunning, mode == "Voice follow" else { return }
        heard = text.split(separator: " ").suffix(16).joined(separator: " ")
        if let word = follower.ingest(text) {
            lastMatch = Date()
            progress = Double(word + 1) / Double(max(1, follower.words.count))
            status = word == follower.words.count - 1 ? "End of script · listening" : "Following your words"
            overlay?.follow(word: word)
        } else if Date().timeIntervalSince(lastMatch) > 2 {
            status = "Listening · holding your place"
        }
    }
    func toggleRunning() {
        if isRunning || isPreparing { stop(); return }
        guard !plain.isEmpty else { errorMessage = "Add a script first."; return }
        showOverlay()
        follower.newUtterance(); heard = ""; errorMessage = nil
        if mode == "Voice follow" {
            isPreparing = true
            startup = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.voice.start(localeIdentifier: self.locale)
                    guard !Task.isCancelled else { return }
                    self.isPreparing = false; self.isRunning = true
                } catch {
                    guard !Task.isCancelled else { return }
                    self.stop(); self.errorMessage = error.localizedDescription
                }
            }
        } else { isRunning = true; status = "Auto scroll · steady pace" }
    }
    func stop() {
        startup?.cancel(); startup = nil; voice.stop()
        isRunning = false; isPreparing = false; status = "Paused · your place is saved"
    }
    func rewind() {
        follower.seek(-1); progress = 0; heard = ""; overlay?.rewind()
    }
    func seek(word: Int) {
        follower.seek(word - 1)
        progress = Double(max(0, word)) / Double(max(1, follower.words.count))
        overlay?.follow(word: max(0, word), immediate: true)
    }
    func showOverlay() {
        if overlay == nil { overlay = OverlayController(model: self) }
        overlayVisible = true; overlay?.show()
    }
    func toggleOverlay() {
        if overlayVisible { hideOverlay() }
        else { showOverlay() }
    }
    func hideOverlay() { stop(); overlayVisible = false; overlay?.panel.orderOut(nil) }
    func chooseFile() {
        let picker = NSOpenPanel()
        picker.title = "Link a Markdown script"
        picker.prompt = "Link script"
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .text, UTType(filenameExtension: "markdown") ?? .text]
        picker.allowsMultipleSelection = false
        let vault = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Vault")
        picker.directoryURL = linkedPath.isEmpty ? vault : URL(fileURLWithPath: linkedPath).deletingLastPathComponent()
        if picker.runModal() == .OK, let url = picker.url { link(url) }
    }
    func link(_ url: URL) {
        do {
            let text = try Self.readScript(url)
            stop(); linkedPath = url.path; lastFileContent = text; source = text
            fileStatus = "Linked · changes in your note appear automatically"
        } catch { errorMessage = error.localizedDescription }
    }
    static func readScript(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2_000_000 else { throw VoiceError.message("Please use a script smaller than 2 MB.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    func reloadFile() {
        guard !linkedPath.isEmpty else { return }
        do {
            let text = try Self.readScript(URL(fileURLWithPath: linkedPath))
            if text != lastFileContent {
                let wasRunning = isRunning || isPreparing
                lastFileContent = text; source = text
                fileStatus = wasRunning ? "Note changed · paused and reset to the beginning" : "Linked · updated from your note"
            } else if fileStatus.hasPrefix("Cannot") { fileStatus = "Linked · file available again" }
        } catch { fileStatus = "Cannot read linked note · keeping the last loaded script" }
    }
    func detach() { linkedPath = ""; lastFileContent = nil; fileStatus = "" }
}
