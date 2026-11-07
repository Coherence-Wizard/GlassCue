import AppKit
import AVFoundation
import Speech

enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Runs Apple's macOS 26 continuous, on-device transcriber. Audio is never written to disk.
@MainActor final class VoiceEngine {
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var generation = UUID()
    private var finalized = ""
    var onText: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    func start(localeIdentifier: String) async throws {
        stop()
        let token = generation
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation else { throw CancellationError() }
        guard granted else { throw VoiceError.message("Microphone access is off. Enable GlassCue in System Settings → Privacy & Security → Microphone.") }
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            throw VoiceError.message("On-device speech is not available for this language on this Mac.")
        }
        guard token == generation else { throw CancellationError() }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        onStatus?("Preparing on-device speech…")
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?("Downloading Apple’s speech model. First use can take a few minutes…")
            try await installation.downloadAndInstall()
        }
        guard token == generation else { throw CancellationError() }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: nativeFormat),
              let converter = AVAudioConverter(from: nativeFormat, to: format) else {
            throw VoiceError.message("No usable microphone input. Choose a microphone in System Settings → Sound → Input, then try again.")
        }
        guard token == generation else { throw CancellationError() }
        try await analyzer.prepareToAnalyze(in: format)
        guard token == generation else { throw CancellationError() }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        finalized = ""
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    let text = String(result.text.characters)
                    self.onText?(self.finalized + " " + text)
                    if result.isFinal {
                        // Keep only recent context. Partial results replace the unfinished segment.
                        self.finalized = (self.finalized + " " + text).split(separator: " ").suffix(24).joined(separator: " ")
                    }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onError?(error.localizedDescription)
            }
        }
        analysisTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onError?(error.localizedDescription)
            }
        }
        // The tap supplies owned, converted buffers to the analyzer; no network or recording file.
        let levelHandler = onLevel
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / nativeFormat.sampleRate)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if conversionError == nil, converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
            if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var square: Float = 0
                for i in 0..<Int(buffer.frameLength) { square += channel[i] * channel[i] }
                let level = min(1, sqrt(square / Float(buffer.frameLength)) * 8)
                DispatchQueue.main.async { levelHandler?(level) }
            }
        }
        engine.prepare()
        try engine.start()
        onStatus?("Listening · waiting for a matching phrase")
    }
    func stop() {
        generation = UUID()
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        continuation?.finish(); continuation = nil
        resultTask?.cancel(); resultTask = nil
        analysisTask?.cancel(); analysisTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil; finalized = ""; onLevel?(0)
    }
}
