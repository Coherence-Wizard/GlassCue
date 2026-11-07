import AppKit

setbuf(stdout, nil)
MainActor.assumeIsolated {
if CommandLine.arguments.contains("--self-test") {
    runTests()
} else if let index = CommandLine.arguments.firstIndex(of: "--speech-test"), CommandLine.arguments.count > index + 1 {
    Task { @MainActor in
        let result = await runSpeechTest(path: CommandLine.arguments[index + 1])
        exit(result)
    }
    dispatchMain()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
}
