import AppKit
import ApplicationServices
import SwiftUI

struct DictationPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DictationEngine
    @ObservedObject var settings: AppSettings

    private var phase: String {
        switch engine.phase {
        case .idle: L("按快捷键开始听写")
        case .preparing: L("正在准备听写…")
        case .recording: L("正在听写，再按快捷键输入")
        case .finishing: L("正在整理听写…")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("听写输入"), systemImage: "keyboard").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Button(L("听写历史")) { model.dictationHistoryWindow.show() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Button(L("设置")) { model.openSettings(.dictation) }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            HStack {
                Circle().fill(engine.busy ? Palette.accent : Palette.tertiary).frame(width: 6, height: 6)
                Text(phase).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                KeyCap(settings.dictationKey.display)
            }
            if !engine.text.isEmpty && engine.busy {
                Text(engine.text).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
            }
            if engine.busy {
                HStack {
                    if engine.phase == .recording { SoftButton(L("停止并输入"), dark: true) { engine.stop() } }
                    SoftButton(L("取消听写")) { engine.cancel() }
                }
            }
            if !engine.message.isEmpty {
                Text(engine.message).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let historyError = engine.historyError {
                Text(historyError).font(.system(size: 12)).foregroundStyle(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !engine.lastText.isEmpty && !engine.busy {
                Button(L("复制上次听写")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(engine.lastText, forType: .string)
                }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            if model.dictationKeyTaken {
                Text("听写快捷键已被占用，请在设置中更换").font(.system(size: 12)).foregroundStyle(Palette.error)
            }
        }
    }
}

struct DictationSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("在输入框按快捷键开始，再按一次输入；最长两分钟。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            SettingsCard {
                SettingsRow(title: L("听写语言")) {
                    Picker(L("听写语言"), selection: $settings.dictationLanguage) {
                        ForEach(sourceLanguages, id: \.locale) { language in
                            Text(language.name).tag(language.locale)
                        }
                    }.labelsHidden().fixedSize()
                }
                SettingsRow(title: L("听写快捷键")) {
                    ShortcutField(model: model, role: .dictation)
                }
                SettingsRow(title: L("启动时监听电脑声音"), divider: false) {
                    Toggle(L("启动时监听电脑声音"), isOn: $settings.listenOnLaunch).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard {
                SettingsRow(title: L("自动粘贴"), detail: L("允许辅助功能后，听写会输入到原来的输入框。"), divider: false) {
                    Button(AXIsProcessTrusted() ? L("已允许") : L("允许辅助功能")) { DictationPaste.requestAccess() }
                        .disabled(AXIsProcessTrusted())
                }
            }
            Text("切换应用或输入框后，只复制文字，不会自动输入。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            if Recognition.cloudOnly {
                Text("当前语音识别使用云端服务，需要已配置的 AI 服务。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }
}
