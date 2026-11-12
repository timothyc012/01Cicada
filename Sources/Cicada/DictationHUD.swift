import AppKit

/// Completion notices belong to one recording and one deadline, so an old clock
/// cannot dismiss the next recording (or extend a notice on repeated callbacks).
struct DictationHUDState {
    enum Status: Equatable { case hidden, preparing, recording, finishing, result(DictationOutcome) }
    struct Dismissal: Equatable { let generation: Int; let deadline: TimeInterval }
    private(set) var status: Status = .hidden
    private(set) var dismissal: Dismissal?
    private var generation = 0
    private var runID = -1
    private var lastPhase: DictationEngine.Phase = .idle
    private var lastOutcome: DictationOutcome?
    private var recordingSince: TimeInterval?

    mutating func update(phase: DictationEngine.Phase, runID: Int, outcome: DictationOutcome?, now: TimeInterval) {
        guard runID != self.runID || phase != lastPhase || outcome != lastOutcome else { return }
        if runID != self.runID { recordingSince = nil }
        self.runID = runID; lastPhase = phase; lastOutcome = outcome
        generation += 1
        dismissal = nil
        switch phase {
        case .preparing: status = .preparing
        case .recording:
            recordingSince = recordingSince ?? now
            status = .recording
        case .finishing: status = .finishing
        case .idle:
            guard let outcome else { status = .hidden; return }
            status = .result(outcome)
            let duration: TimeInterval
            switch outcome { case .inserted, .cancelled: duration = 2; default: duration = 4 }
            dismissal = Dismissal(generation: generation, deadline: now + duration)
        }
    }
    mutating func dismiss(_ token: Dismissal, now: TimeInterval) {
        guard token == dismissal, now >= token.deadline else { return }
        status = .hidden; dismissal = nil
    }
    func elapsed(at now: TimeInterval) -> Int { max(0, Int(now - (recordingSince ?? now))) }
}

private struct DictationHUDCopy {
    let title: String
    let detail: String
    let symbol: String
    let badge: String
    init(status: DictationHUDState.Status, shortcut: String, elapsed: Int, silent: Bool) {
        badge = status == .recording ? String(format: "%02d:%02d", elapsed / 60, elapsed % 60) : ""
        switch status {
        case .hidden: title = ""; detail = ""; symbol = ""
        case .preparing:
            title = L("正在准备听写"); detail = L("马上就可以说话"); symbol = "mic.badge.plus"
        case .recording:
            title = L("正在听写"); symbol = "waveform"
            detail = silent ? L("暂时没有声音，请检查麦克风") : L("再按 \(shortcut) 完成")
        case .finishing:
            title = L("正在转成文字"); detail = L("请稍等片刻"); symbol = "ellipsis"
        case .result(.inserted):
            title = L("已输入"); detail = L("文字已发送到原来的输入框"); symbol = "checkmark"
        case .result(.copied(let reason)):
            title = L("已复制"); symbol = "doc.on.doc"
            switch reason {
            case "application_changed", "focused_field_changed": detail = L("输入位置变了 · 按 ⌘V 粘贴")
            case "accessibility_denied": detail = L("需要辅助功能权限 · 按 ⌘V 粘贴")
            case "no_destination_app", "destination_missing": detail = L("没有可用的输入框 · 按 ⌘V 粘贴")
            default: detail = L("未能自动输入 · 按 ⌘V 粘贴")
            }
        case .result(.noAudio):
            title = L("没有收到麦克风声音"); detail = L("请检查输入麦克风后重试"); symbol = "mic.slash"
        case .result(.noSpeech):
            title = L("没有听到语音"); detail = L("请再说一次"); symbol = "waveform.slash"
        case .result(.failed(let error)):
            title = L("听写未完成"); detail = error; symbol = "exclamationmark.triangle"
        case .result(.cancelled):
            title = L("已取消听写"); detail = L("没有输入文字"); symbol = "xmark"
        }
    }
}

@MainActor final class DictationHUDController {
    private var state = DictationHUDState()
    private var panel: DictationHUDPanel?
    private var surface: DictationHUDSurface?
    private var clock: Timer?
    private weak var engine: DictationEngine?
    private var shortcut = ""
    private var previewLevels: [Float] = []
    private var previewElapsed: Int?
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func update(engine: DictationEngine, shortcut: Shortcut) {
        self.engine = engine; self.shortcut = shortcut.display
        previewElapsed = nil; previewLevels = []
        state.update(phase: engine.phase, runID: engine.runID, outcome: engine.outcome, now: now)
        refresh()
    }

    private func refresh() {
        if let token = state.dismissal { state.dismiss(token, now: now) }
        guard state.status != .hidden else {
            panel?.orderOut(nil)
            clock?.invalidate(); clock = nil
            return
        }
        if panel == nil {
            let p = DictationHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 368, height: 66),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isReleasedWhenClosed = false
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar; p.hidesOnDeactivate = false; p.becomesKeyOnlyIfNeeded = true
            p.ignoresMouseEvents = true; p.sharingType = .none
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let surface = DictationHUDSurface(frame: NSRect(x: 0, y: 0, width: 368, height: 66))
            p.contentView = surface
            self.surface = surface; panel = p
        }
        let elapsed = previewElapsed ?? state.elapsed(at: now)
        let levels = engine?.audioLevels ?? previewLevels
        let copy = DictationHUDCopy(status: state.status, shortcut: shortcut, elapsed: elapsed,
                                    silent: previewElapsed == nil && elapsed >= 3 && engine?.hasRecentAudio == false)
        guard let panel, let surface else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let width = min(available.width - 32, surface.preferredWidth(copy))
        panel.setFrame(NSRect(x: available.midX - width / 2, y: available.maxY - 12 - 66, width: width, height: 66), display: false)
        surface.update(copy, recording: state.status == .recording, levels: levels)
        if !panel.isVisible { panel.orderFrontRegardless() }
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Read the real native window; these values are never guessed from desired configuration.
    var snapshot: [String: Any] {
        guard let panel else { return ["visible": false, "created": false] }
        return ["visible": panel.isVisible, "created": true, "key": panel.isKeyWindow, "main": panel.isMainWindow,
                "canBecomeKey": panel.canBecomeKey, "canBecomeMain": panel.canBecomeMain,
                "clickThrough": panel.ignoresMouseEvents, "sharingType": panel.sharingType.rawValue,
                "nonactivating": panel.styleMask.contains(.nonactivatingPanel),
                "allSpaces": panel.collectionBehavior.contains(.canJoinAllSpaces),
                "fullScreenAuxiliary": panel.collectionBehavior.contains(.fullScreenAuxiliary),
                "material": surface?.materialName ?? "",
                "backdropOpacity": surface?.backdropOpacity ?? 1, "contentOpacity": surface?.contentOpacity ?? 1, "title": surface?.title.stringValue ?? "",
                "detail": surface?.detail.stringValue ?? "", "width": panel.frame.width, "height": panel.frame.height,
                "status": String(describing: state.status), "clockRunning": clock != nil,
                "labelsFit": surface?.labelsFit ?? false,
                "titleFrame": surface.map { NSStringFromRect($0.title.frame) } ?? "",
                "detailFrame": surface.map { NSStringFromRect($0.detail.frame) } ?? ""]
    }

    /// Synthetic status only: no engine, capture, delivery, clipboard or settings mutation.
    func preview(_ name: String, shortcut: String) -> Bool {
        guard engine?.busy != true else { return false }
        engine = nil; self.shortcut = shortcut; previewElapsed = 12; previewLevels = []
        let phase: DictationEngine.Phase
        let outcome: DictationOutcome?
        switch name {
        case "preparing": phase = .preparing; outcome = nil
        case "recording": phase = .recording; outcome = nil
        case "finishing": phase = .finishing; outcome = nil
        case "inserted": phase = .idle; outcome = .inserted
        case "copied": phase = .idle; outcome = .copied(reason: "application_changed")
        case "permission": phase = .idle; outcome = .copied(reason: "accessibility_denied")
        case "silent": phase = .idle; outcome = .noAudio
        case "error": phase = .idle; outcome = .failed(L("听写超时，请重试"))
        case "cancelled": phase = .idle; outcome = .cancelled
        case "off": phase = .idle; outcome = nil
        default: return false
        }
        state = DictationHUDState()
        state.update(phase: phase, runID: 1, outcome: outcome, now: now)
        refresh()
        return true
    }

    func render(to url: URL) throws {
        guard let surface else { throw CocoaError(.fileWriteUnknown) }
        panel?.displayIfNeeded()
        surface.layoutSubtreeIfNeeded()
        guard let rep = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else { throw CocoaError(.fileWriteUnknown) }
        surface.cacheContent(to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}

private final class DictationHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Native glass owns the backdrop; drawing adds only a restrained gloss highlight.
@MainActor private final class DictationHUDSurface: NSView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let meter = DictationHUDMeter()
    private let content = DictationHUDHighlight()
    private var backdrop: NSView?
    private(set) var materialName = ""
    var backdropOpacity: CGFloat { backdrop?.alphaValue ?? 1 }
    var contentOpacity: CGFloat { content.alphaValue }
    private var reducedTransparency: Bool?
    private var highContrast: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badge.textColor = .secondaryLabelColor; badge.alignment = .right
        for view in [title, detail, badge] { view.lineBreakMode = .byTruncatingTail; view.maximumNumberOfLines = 1; content.addSubview(view) }
        icon.contentTintColor = Self.orange; icon.imageScaling = .scaleProportionallyDown
        content.addSubview(icon); content.addSubview(meter)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    static var orange: NSColor { NSColor(srgbRed: 0.91, green: 0.33, blue: 0.17, alpha: 1) }

    private func updateMaterial() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard backdrop == nil || reducedTransparency != reduce || highContrast != contrast else { return }
        reducedTransparency = reduce; highContrast = contrast
        content.removeFromSuperview(); backdrop?.removeFromSuperview()
        let background: NSView
        if reduce || contrast {
            background = NSView(); background.wantsLayer = true
            background.layer?.cornerRadius = 22
            materialName = "opaqueAccessibility"
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear; glass.cornerRadius = 22
            background = glass; materialName = "NSGlassEffectView.clear"
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = 22; effect.layer?.masksToBounds = true
            background = effect; materialName = "NSVisualEffectView.behindWindow"
        }
        // Keep labels above the backdrop so transparency never fades the text.
        background.alphaValue = reduce || contrast ? 1 : 0.65
        backdrop = background; addSubview(background); addSubview(content)
    }
    func preferredWidth(_ copy: DictationHUDCopy) -> CGFloat {
        let titleWidth = (copy.title as NSString).size(withAttributes: [.font: title.font!]).width
        let detailWidth = (copy.detail as NSString).size(withAttributes: [.font: detail.font!]).width
        let badgeWidth: CGFloat = copy.badge.isEmpty ? 0 : 52
        return max(368, min(560, ceil(max(titleWidth, detailWidth)) + 76 + badgeWidth))
    }
    func update(_ copy: DictationHUDCopy, recording: Bool, levels: [Float]) {
        updateMaterial()
        title.stringValue = copy.title; detail.stringValue = copy.detail; badge.stringValue = copy.badge
        icon.image = NSImage(systemSymbolName: copy.symbol, accessibilityDescription: nil)
        icon.isHidden = recording; meter.isHidden = !recording; meter.levels = levels
        if reducedTransparency == true || highContrast == true {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                backdrop?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
        setAccessibilityLabel([copy.title, copy.detail, copy.badge].filter { !$0.isEmpty }.joined(separator: ". "))
        needsLayout = true; layoutSubtreeIfNeeded(); content.needsDisplay = true
    }
    func cacheContent(to rep: NSBitmapImageRep) {
        // Native glass is composited by WindowServer and does not export its
        // backdrop through cacheDisplay. Export the real text/highlight subtree.
        content.cacheDisplay(in: content.bounds, to: rep)
    }
    var labelsFit: Bool {
        [title, detail, badge].allSatisfy { field in
            (field.stringValue as NSString).size(withAttributes: [.font: field.font!]).width <= field.bounds.width + 1
        }
    }
    override func layout() {
        super.layout()
        backdrop?.frame = bounds; content.frame = bounds
        let right: CGFloat = badge.stringValue.isEmpty ? 18 : 68
        icon.frame = NSRect(x: 18, y: 22, width: 25, height: 23)
        meter.frame = NSRect(x: 18, y: 21, width: 26, height: 24)
        title.frame = NSRect(x: 56, y: 34, width: bounds.width - 56 - right, height: 19)
        detail.frame = NSRect(x: 56, y: 15, width: bounds.width - 56 - right, height: 16)
        badge.frame = NSRect(x: bounds.width - 62, y: 25, width: 44, height: 16)
    }
}

private final class DictationHUDHighlight: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.05 : 0.12),
                   ending: NSColor.white.withAlphaComponent(dark ? 0.005 : 0.015))?.draw(in: bounds, angle: -90)
        NSColor.white.withAlphaComponent(dark ? 0.18 : 0.40).setStroke(); shape.lineWidth = 1; shape.stroke()
        let shine = NSBezierPath(); shine.move(to: NSPoint(x: bounds.width * 0.18, y: bounds.height - 1))
        shine.line(to: NSPoint(x: bounds.width * 0.82, y: bounds.height - 1))
        NSColor.white.withAlphaComponent(dark ? 0.22 : 0.55).setStroke(); shine.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class DictationHUDMeter: NSView {
    var levels: [Float] = [] { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        DictationHUDSurface.orange.setFill()
        let values = Array(levels.suffix(5))
        for index in 0..<5 {
            let level = index < values.count ? CGFloat(values[index]) : 0
            let height = max(2, min(bounds.height, level * bounds.height))
            NSBezierPath(roundedRect: NSRect(x: CGFloat(index) * 5, y: (bounds.height - height) / 2,
                                             width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
