import SwiftUI
import AppKit

// MARK: - Standalone Window Controller

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = L("Paozier 设置")
        w.center()
        w.contentView = NSHostingView(rootView: SettingsView())
        w.isReleasedWhenClosed = false
        self.window = w
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newExtension = ""
    @State private var showClearConfirm = false
    @State private var clearTarget = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.fill").foregroundStyle(.blue)
                Text(L("设置")).font(.headline)
                Spacer()
                Button(L("完成")) { NSApp.keyWindow?.close() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(12)
            .background(.bar)
            Divider()

            TabView {
                generalTab.tabItem { Label(L("通用"), systemImage: "slider.horizontal.3") }
                searchTab.tabItem { Label(L("搜索"), systemImage: "magnifyingglass") }
                servicesTab.tabItem { Label(L("服务"), systemImage: "network") }
                indexTab.tabItem { Label(L("索引"), systemImage: "tray.full") }
                dataTab.tabItem { Label(L("数据"), systemImage: "externaldrive") }
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .onChange(of: settings.searchResultLimit) { _, _ in settings.save() }
        .onChange(of: settings.searchEngineWeightSK) { _, _ in settings.save() }
        .onChange(of: settings.searchEngineWeightFTS) { _, _ in settings.save() }
        .onChange(of: settings.httpPort) { _, _ in settings.save() }
        .onChange(of: settings.httpAutoStart) { _, _ in settings.save() }
        .onChange(of: settings.mcpPort) { _, _ in settings.save() }
        .onChange(of: settings.mcpAutoStart) { _, _ in settings.save() }
        .onChange(of: settings.defaultPreviewMode) { _, _ in settings.save() }
        .onChange(of: settings.historyMaxItems) { _, _ in settings.save() }
        .onChange(of: settings.excludedExtensions) { _, _ in settings.save() }
        .onChange(of: settings.searchFilenames) { _, _ in settings.save() }
        .onChange(of: settings.languagePreference) { _, _ in settings.save() }
        .onChange(of: settings.matchContextChars) { _, _ in settings.save() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section(L("语言")) {
                Picker(L("界面语言"), selection: $settings.languagePreference) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }
            }
            Section(L("预览")) {
                Picker(L("默认预览模式"), selection: $settings.defaultPreviewMode) {
                    Text("Live Preview").tag("live")
                    Text(L("原文件")).tag("pdf")
                }
            }
            Section(L("历史记录")) {
                Stepper(LF("最大记录数: %d", settings.historyMaxItems), value: $settings.historyMaxItems, in: 10...1000, step: 10)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Search

    private var searchTab: some View {
        Form {
            Section(L("结果")) {
                Stepper(LF("最大结果数: %d", settings.searchResultLimit), value: $settings.searchResultLimit, in: 5...200, step: 5)
                Stepper(LF("命中上下文字符数: %d", settings.matchContextChars), value: $settings.matchContextChars, in: 10...200, step: 5)
            }
            Section(L("引擎权重")) {
                HStack {
                    Text("SearchKit")
                    Slider(value: $settings.searchEngineWeightSK, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", settings.searchEngineWeightSK)).monospacedDigit().frame(width: 30)
                }
                HStack {
                    Text("FTS5")
                    Slider(value: $settings.searchEngineWeightFTS, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", settings.searchEngineWeightFTS)).monospacedDigit().frame(width: 30)
                }
                Text(L("权重决定双引擎结果的融合排序比例")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("范围")) {
                Toggle(L("同时搜索文件名"), isOn: $settings.searchFilenames)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Services

    private var servicesTab: some View {
        Form {
            Section(L("HTTP 搜索服务")) {
                HStack {
                    Text(L("端口"))
                    TextField("", value: $settings.httpPort, format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                }
                Toggle(L("启动时自动开启"), isOn: $settings.httpAutoStart)
            }
            Section(L("MCP AI 工具服务")) {
                HStack {
                    Text(L("端口"))
                    TextField("", value: $settings.mcpPort, format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                }
                Toggle(L("启动时自动开启"), isOn: $settings.mcpAutoStart)
            }
            Section(L("MCP 配置 (复制到 AI 工具)")) {
                MCPConfigView(port: settings.mcpPort)
            }
            Text(L("端口修改需重启应用生效")).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Index

    private var indexTab: some View {
        Form {
            Section(L("排除的文件扩展名")) {
                HStack {
                    TextField(L("扩展名（如 log）"), text: $newExtension).textFieldStyle(.roundedBorder)
                    Button(L("添加")) {
                        let ext = newExtension.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ".", with: "")
                        if !ext.isEmpty && !settings.excludedExtensions.contains(ext) {
                            settings.excludedExtensions.append(ext)
                            newExtension = ""
                        }
                    }.disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if settings.excludedExtensions.isEmpty {
                    Text(L("无排除项 — 所有支持格式均会被索引")).font(.caption).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(settings.excludedExtensions, id: \.self) { ext in
                            HStack(spacing: 2) {
                                Text(".\(ext)").font(.caption)
                                Button { settings.excludedExtensions.removeAll { $0 == ext } } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.1)))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var dataTab: some View {
        Form {
            Section(L("清除数据")) {
                Button(L("清除搜索历史")) { clearTarget = "history"; showClearConfirm = true }
                Button(L("清除报告数据")) { clearTarget = "compendium"; showClearConfirm = true }
                Button(L("重建全部索引")) { clearTarget = "index"; showClearConfirm = true }
                    .foregroundStyle(.red)
            }
            Section(L("存储位置")) {
                HStack {
                    Text("~/Library/Application Support/Paozier/").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("打开")) { NSWorkspace.shared.open(dataDirectory) }.controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .alert(L("确认操作"), isPresented: $showClearConfirm) {
            Button(L("取消"), role: .cancel) {}
            Button(L("确认"), role: .destructive) { performClear() }
        } message: {
            Text(clearMessage)
        }
    }

    private var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Paozier", isDirectory: true)
    }

    private var clearMessage: String {
        switch clearTarget {
        case "history": return L("将清除所有搜索历史记录")
        case "compendium": return L("将清除所有报告数据")
        case "index": return L("将删除并重建全部索引，耗时较长")
        default: return ""
        }
    }

    private func performClear() {
        switch clearTarget {
        case "history": DataManager.shared.clearHistory()
        case "compendium": DataManager.shared.clearCompendium()
        case "index": Task { await IndexManager.shared?.reindexAll() }
        default: break
        }
    }
}

// MARK: - MCP Config View

struct MCPConfigView: View {
    let port: Int
    @State private var copied = false

    private var configJSON: String {
        """
        {
          "mcpServers": {
            "paozier": {
              "command": "nc",
              "args": ["localhost", "\(port)"],
              "env": {}
            }
          }
        }
        """
    }

    private var httpConfigJSON: String {
        """
        {
          "mcpServers": {
            "paozier": {
              "url": "http://localhost:\(port)",
              "transport": "tcp"
            }
          }
        }
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("TCP 连接方式 (Claude Desktop / Cline / Cursor)")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(httpConfigJSON).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                Spacer()
                Button(copied ? L("已复制") : L("复制")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(httpConfigJSON, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .controlSize(.small)
            }
        }
    }
}

// Simple flow layout for extension tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
