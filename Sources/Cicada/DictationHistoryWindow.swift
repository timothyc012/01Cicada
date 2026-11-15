import AppKit
import Combine
import SwiftUI

@MainActor
final class DictationHistoryModel: ObservableObject {
    @Published private(set) var entries: [DictationHistoryEntry] = []
    @Published var query = ""
    @Published private(set) var copiedID: String?
    @Published private(set) var errorMessage: String?
    private let store: DictationHistoryStore

    init(store: DictationHistoryStore) { self.store = store }

    var filteredEntries: [DictationHistoryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func reload() {
        do {
            entries = try store.entries()
            errorMessage = nil
        } catch {
            // Keep already loaded text available for copying if the disk becomes unavailable.
            errorMessage = L("无法读取听写历史，请稍后刷新。")
        }
    }

    @discardableResult
    func copy(_ entry: DictationHistoryEntry, to board: NSPasteboard = .general) -> Bool {
        board.clearContents()
        guard board.setString(entry.text, forType: .string) else {
            copiedID = nil
            errorMessage = L("复制失败，请选中文字后重试。")
            return false
        }
        copiedID = entry.id
        errorMessage = nil
        return true
    }
}

@MainActor
final class DictationHistoryWindowController: NSObject, NSWindowDelegate {
    let model = DictationHistoryModel(store: DictationHistoryStore())
    private(set) var window: NSWindow?
    var visibilityChanged: ((NSWindow?) -> Void)?

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = L("听写历史")
            w.minSize = NSSize(width: 520, height: 320)
            w.isReleasedWhenClosed = false
            w.sharingType = .none
            w.backgroundColor = .white
            w.delegate = self
            w.contentView = NSHostingView(rootView: DictationHistoryView(model: model))
            if !w.setFrameUsingName("CicadaDictationHistory") { w.center() }
            w.setFrameAutosaveName("CicadaDictationHistory")
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        visibilityChanged?(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshIfVisible() {
        if window?.isVisible == true { model.reload() }
    }

    func windowWillClose(_ notification: Notification) {
        visibilityChanged?(window)
    }
}

struct DictationHistoryView: View {
    @ObservedObject var model: DictationHistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("听写历史")).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(String(format: L("%lld 条听写"), Int64(model.entries.count)))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Button(L("刷新记录")) { model.reload() }
            }
            TextField(L("搜索听写文字"), text: $model.query).textFieldStyle(.roundedBorder)
            if let error = model.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.error)
            }
            if model.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble").font(.system(size: 28)).foregroundStyle(Palette.tertiary)
                    Text(model.entries.isEmpty ? L("还没有听写记录") : L("没有找到匹配的听写"))
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                    if model.entries.isEmpty {
                        Text(L("成功识别的听写会保存在这里；没有文字的尝试不会保存。"))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.filteredEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)).formatted(date: .abbreviated, time: .shortened))
                                    Text(Locale.current.localizedString(forIdentifier: entry.language) ?? entry.language)
                                    Spacer()
                                    Button(model.copiedID == entry.id ? L("已复制") : L("复制")) { model.copy(entry) }
                                }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                Text(entry.text).font(.system(size: 14)).foregroundStyle(Palette.ink)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        }
                    }.padding(.trailing, 8)
                }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
    }
}
