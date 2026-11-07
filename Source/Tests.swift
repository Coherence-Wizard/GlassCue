import AppKit
import Speech
import AVFoundation

@MainActor func runSpeechTest(path: String) async -> Int32 {
    do {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            print("SPEECH TEST: On-device transcription unavailable"); return 1
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        print("SPEECH TEST: model status \(await AssetInventory.status(forModules: [transcriber]))")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            print("SPEECH TEST: downloading Apple speech model")
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let follower = PhraseFollower(CueModel.sample)
        var finalized = ""
        let results = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                let previous = follower.cursor
                follower.ingest(finalized + " " + text)
                print("SPEECH RESULT: \(result.isFinal ? "final" : "partial") cursor=\(follower.cursor) previous=\(previous) text=\(text)")
                if result.isFinal { finalized += " " + text }
            }
        }
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
        try await results.value
        guard follower.cursor > 45 else { print("FAIL: recognized audio did not reacquire later script"); return 1 }
        print("PASS: real on-device audio transcription reacquired script after a spoken digression, word \(follower.cursor + 1)")
        return 0
    } catch { print("SPEECH TEST ERROR: \(error)"); return 1 }
}

@MainActor func runTests() {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if !condition() { print("FAIL: \(name)"); exit(1) }
        count += 1; print("PASS: \(name)")
    }
    check(ScriptText.plain("---\ntitle: Hidden\n---\n# Hello **world**\n\n[[Some note|Read this]] %% secret %%\n![[image.png]]") == "Hello world\n\nRead this", "Obsidian frontmatter, formatting, aliases, comments, embeds")
    check(ScriptText.plain("- [x] First\n> [!note] Aside\n[Read me](https://example.com)") == "First\nAside\nRead me", "Tasks, callouts, and links")
    check(ScriptText.words("I’m READY—café.").map(\.value) == ["i'm", "ready", "cafe"], "Unicode word normalization")
    let script = "Welcome to this recording. Today we explore the quiet forest beside the river. Take a breath and notice the light. Now I am back on script and ready to continue. Finally we close with a thought about tomorrow."
    let follower = PhraseFollower(script)
    check(follower.ingest("Welcome to this recording") == 3, "Initial phrase acquisition")
    let held = follower.cursor
    check(follower.ingest("by the way my neighbor bought a purple bicycle yesterday") == nil && follower.cursor == held, "Rambling holds position")
    check(follower.ingest("and the") == nil && follower.cursor == held, "Common filler does not advance")
    check(follower.ingest("river") == nil, "A single shared word does not jump")
    check(follower.ingest("anyway now I am back on script") == 25, "Reacquire a later phrase after an off-script digression")
    let resumed = follower.cursor
    check(follower.ingest("anyway now I am back on script") == nil && follower.cursor == resumed, "Repeated partial result does not advance twice")
    check(follower.ingest("now I am back on script and ready to continue") == 29, "Continuous phrase progression")
    check(follower.ingest("welcome to this recording") == nil && follower.cursor == 29, "Earlier repeated material does not pull script backward")
    follower.seek(-1)
    check(follower.ingest("Welcome to this recording") == 3, "Explicit rewind allows repeated takes")
    let imperfect = PhraseFollower("Today we explore the beautiful quiet forest beside the river and watch birds.")
    check(imperfect.ingest("today we explore the quiet forest beside the river") == 9, "Omitted word tolerated in a longer phrase")
    let repeated = PhraseFollower("We begin again. We begin again. We begin again.")
    check(repeated.ingest("we begin again") == 2, "Identical phrases prefer closest occurrence")
    check(repeated.ingest("we begin again we begin again") == 5, "A spoken repeated phrase advances to its next occurrence")
    let suite = "GlassCue.Tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = CueModel(defaults: defaults)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("GlassCue-test-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: temp) }
    try! "# First version".write(to: temp, atomically: true, encoding: .utf8)
    model.link(temp)
    check(model.plain == "First version", "Read linked Markdown")
    try! "# Updated atomically".write(to: temp, atomically: true, encoding: .utf8)
    model.reloadFile()
    check(model.plain == "Updated atomically", "Follow atomic file replacement used by editors")
    try! FileManager.default.removeItem(at: temp); model.reloadFile()
    check(model.plain == "Updated atomically" && model.fileStatus.hasPrefix("Cannot"), "Missing note preserves last script and reports error")
    model.detach(); check(model.linkedPath.isEmpty && model.plain == "Updated atomically", "Detach keeps editable copy")
    _ = NSApplication.shared
    let overlay = OverlayController(model: model)
    check(!overlay.panel.isOpaque && overlay.panel.backgroundColor == .clear && overlay.panel.level == .floating, "Transparent always-on-top native panel")
    model.overlay = overlay; model.positioning = false
    check(overlay.panel.ignoresMouseEvents, "Click-through releases mouse to underlying apps")
    model.positioning = true
    check(!overlay.panel.ignoresMouseEvents, "Position mode restores mouse interaction")
    print("\(count) checks passed.")
}
