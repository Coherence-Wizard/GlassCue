import AppKit

final class CuePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class OverlayController {
    let panel: CuePanel
    let canvas: CueCanvas
    weak var model: CueModel?
    private var timer: Timer?
    init(model: CueModel) {
        self.model = model
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel = CuePanel(contentRect: NSRect(x: screen.midX - 360, y: screen.maxY - 410, width: 720, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "GlassCue — Floating Script"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        canvas = CueCanvas(model: model)
        canvas.autoresizingMask = [.width, .height]; panel.contentView = canvas
        if let frame = UserDefaults.standard.string(forKey: "overlayFrame") {
            let rect = NSRectFromString(frame)
            if rect.width >= 320, rect.height >= 180, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { panel.setFrame(rect, display: false) }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.canvas.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func show() { refresh(); panel.orderFrontRegardless() }
    func refresh(reset: Bool = false) {
        guard let model else { return }
        panel.ignoresMouseEvents = !model.positioning
        canvas.rebuild(reset: reset)
    }
    func follow(word: Int, immediate: Bool = false) { canvas.follow(word: word, immediate: immediate) }
    func rewind() { canvas.offset = 0; canvas.targetOffset = 0; canvas.activeWord = -1; canvas.rebuild(reset: true) }
}

@MainActor final class CueCanvas: NSView {
    weak var model: CueModel?
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
    let closeButton = NSButton()
    var offset: CGFloat = 0
    var targetOffset: CGFloat = 0
    var activeWord = -1
    private var textHeight: CGFloat = 0
    private var draggingResize = false
    private var dragPoint = NSPoint.zero
    private var dragFrame = NSRect.zero
    private var lastTick = ProcessInfo.processInfo.systemUptime
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    var insetY: CGFloat {
        // Keep the reading line clear of the positioning bar and lower edge, even
        // with large type in a short window. A higher percentage sits lower down.
        let bottomLimit = max(44, bounds.height - (model?.fontSize ?? 38) * 1.4 - 24)
        return min(bottomLimit, max(44, bounds.height * (model?.focusPosition ?? 0.28)))
    }
    var maxOffset: CGFloat { max(0, textHeight - 20) }
    init(model: CueModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 360))
        storage.addLayoutManager(layoutManager); layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close floating script")
        closeButton.title = ""; closeButton.isBordered = false; closeButton.contentTintColor = .white
        closeButton.target = self; closeButton.action = #selector(closeOverlay)
        closeButton.toolTip = "Close overlay and pause listening (Escape or Control–Option–O)"
        closeButton.setAccessibilityLabel("Close floating script")
        addSubview(closeButton)
        setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel("Floating teleprompter script")
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func closeOverlay() { model?.hideOverlay() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); rebuild() }
    func rebuild(reset: Bool = false) {
        guard let model else { return }
        closeButton.frame = NSRect(x: bounds.width - 33, y: 5, width: 26, height: 26)
        closeButton.isHidden = !model.positioning
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = model.fontSize * 0.3
        paragraph.paragraphSpacing = model.fontSize * 0.36
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: model.fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(model.textOpacity),
            .paragraphStyle: paragraph, .shadow: shadow,
            .strokeColor: NSColor.black.withAlphaComponent(0.5), .strokeWidth: -1.5
        ]
        storage.setAttributedString(NSAttributedString(string: model.plain, attributes: attributes))
        container.containerSize = NSSize(width: max(240, bounds.width - 64), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        textHeight = layoutManager.usedRect(for: container).height
        if reset { offset = 0; targetOffset = 0; activeWord = -1 }
        else if activeWord >= 0 { follow(word: activeWord, immediate: true) }
        setAccessibilityValue(model.plain)
        needsDisplay = true
    }
    func follow(word: Int, immediate: Bool = false) {
        guard let model, model.follower.words.indices.contains(word) else { return }
        activeWord = word
        storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(model.textOpacity), range: NSRange(location: 0, length: storage.length))
        let range = model.follower.words[word].range
        storage.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.58, green: 1, blue: 0.84, alpha: model.textOpacity), range: range)
        let glyph = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        targetOffset = max(0, min(maxOffset, layoutManager.boundingRect(forGlyphRange: glyph, in: container).minY))
        if immediate { offset = targetOffset }
        needsDisplay = true
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, now - lastTick); lastTick = now
        guard let model, model.overlayVisible else { return }
        if model.isRunning && model.mode == "Auto scroll" {
            targetOffset = min(maxOffset, targetOffset + model.speed * dt)
            if targetOffset >= maxOffset { model.stop(); model.status = "End of script" }
        }
        if abs(offset - targetOffset) > 0.1 {
            offset += (targetOffset - offset) * min(1, dt * 9); needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        NSGraphicsContext.saveGraphicsState()
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        if model.shade > 0 { NSColor.black.withAlphaComponent(model.shade).setFill(); shape.fill() }
        if model.positioning {
            NSColor.systemMint.withAlphaComponent(0.6).setStroke(); shape.lineWidth = 1; shape.stroke()
            let header = NSRect(x: 1, y: 1, width: bounds.width - 2, height: 36)
            NSColor(calibratedWhite: 0.09, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: header, xRadius: 14, yRadius: 14).fill()
            let label = bounds.width > 600 ? "GLASSCUE   ·   Drag to move   ·   Click a word to set your place" : "GLASSCUE   ·   Drag to move"
            label.draw(at: NSPoint(x: 16, y: 11), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            "↘".draw(at: NSPoint(x: bounds.width - 25, y: bounds.height - 29), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.systemMint])
        }
        NSBezierPath(rect: NSRect(x: 24, y: model.positioning ? 40 : 0, width: bounds.width - 48, height: bounds.height - (model.positioning ? 65 : 0))).addClip()
        let origin = NSPoint(x: 32, y: insetY - offset)
        let glyphs = layoutManager.glyphRange(forBoundingRect: NSRect(x: 0, y: max(0, offset - insetY), width: container.size.width, height: bounds.height + insetY), in: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x > bounds.width - 38 && point.y <= 36 { model?.hideOverlay(); return }
        dragPoint = NSEvent.mouseLocation; dragFrame = window?.frame ?? .zero
        draggingResize = point.x > bounds.width - 35 && point.y > bounds.height - 35
        if point.y <= 38 { window?.performDrag(with: event); saveFrame(); return }
        if draggingResize { return }
        let textPoint = NSPoint(x: point.x - 32, y: point.y - insetY + offset)
        let character = layoutManager.characterIndex(for: textPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        if let model, let word = model.follower.words.firstIndex(where: { NSMaxRange($0.range) > character }) { model.seek(word: word) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard draggingResize, let window else { return }
        let point = NSEvent.mouseLocation
        let width = max(320, dragFrame.width + point.x - dragPoint.x)
        let height = max(180, dragFrame.height - point.y + dragPoint.y)
        window.setFrame(NSRect(x: dragFrame.minX, y: dragFrame.maxY - height, width: width, height: height), display: true)
    }
    override func mouseUp(with event: NSEvent) { draggingResize = false; saveFrame() }
    override func scrollWheel(with event: NSEvent) {
        targetOffset = min(maxOffset, max(0, targetOffset - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)))
        offset = targetOffset; needsDisplay = true
    }
    private func saveFrame() { if let window { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "overlayFrame") } }
}
