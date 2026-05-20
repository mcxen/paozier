import SwiftUI
import AppKit
import Darwin
import UniformTypeIdentifiers

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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = L("Paozier 设置")
        w.minSize = NSSize(width: 760, height: 520)
        w.center()
        w.contentView = NSHostingView(rootView: SettingsView())
        w.isReleasedWhenClosed = false
        self.window = w
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Settings View

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case search
    case services
    case external
    case index
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L("通用")
        case .search: return L("搜索")
        case .services: return L("服务")
        case .external: return L("外部源")
        case .index: return L("索引")
        case .data: return L("数据")
        case .about: return L("关于")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return L("语言、预览和快速搜索")
        case .search: return L("结果数量、排序和范围")
        case .services: return L("HTTP 与 MCP 服务")
        case .external: return L("Memos 与外部搜索源")
        case .index: return L("OCR 与索引排除项")
        case .data: return L("历史、报告和本地数据")
        case .about: return L("版本、源码和更新")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .search: return "magnifyingglass"
        case .services: return "network"
        case .external: return "point.3.connected.trianglepath.dotted"
        case .index: return "tray.full"
        case .data: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newExtension = ""
    @State private var showClearConfirm = false
    @State private var clearTarget = ""
    @State private var memosValidationMessages: [String: String] = [:]
    @State private var selectedCategory: SettingsCategory = .general
    @State private var sidebarSearchText = ""
    @State private var usageSnapshot = SystemUsageSnapshot.load(dataDirectory: SettingsView.defaultDataDirectory)
    @State private var updateState: ReleaseCheckState = .idle
    @State private var iconImportError = ""

    var body: some View {
        settingsContent
            .modifier(SettingsPersistenceModifier(settings: settings))
    }

    private var settingsContent: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            VStack(spacing: 0) {
                settingsHeader
                Divider()
                ScrollView {
                    selectedCategoryView
                        .font(.system(size: 13))
                        .controlSize(.small)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 22)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 860, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsSidebar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("搜索"), text: $sidebarSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.06))
            )
            .padding(.top, 10)
            .padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(filteredSidebarCategories) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            settingsSidebarRow(category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 200)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filteredSidebarCategories: [SettingsCategory] {
        let needle = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter { category in
            category.title.lowercased().contains(needle) ||
            category.subtitle.lowercased().contains(needle)
        }
    }

    private func settingsSidebarRow(_ category: SettingsCategory) -> some View {
        let selected = category == selectedCategory
        return HStack(spacing: 9) {
            Image(systemName: category.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selected ? .white : Color.accentColor)
                .frame(width: 22, height: 22)
            Text(category.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private var settingsHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: selectedCategory.systemImage)
                .foregroundStyle(.blue)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedCategory.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(selectedCategory.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("完成")) { NSApp.keyWindow?.close() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedCategoryView: some View {
        switch selectedCategory {
        case .general:
            generalTab
        case .search:
            searchTab
        case .services:
            servicesTab
        case .external:
            externalTab
        case .index:
            indexTab
        case .data:
            dataTab
        case .about:
            aboutTab
        }
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
            Section(L("快速搜索")) {
                Toggle(L("在菜单栏显示快速搜索"), isOn: $settings.quickSearchMenuBarEnabled)
                Toggle(L("快速搜索窗口固定在最前"), isOn: $settings.quickSearchPanelAlwaysOnTop)
                Text(L("开启菜单栏后，可从 macOS 状态栏直接打开快速搜索面板。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                HStack {
                    Text("Tantivy")
                    Slider(value: $settings.searchEngineWeightTantivy, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", settings.searchEngineWeightTantivy)).monospacedDigit().frame(width: 30)
                }
                Text(L("权重决定三引擎结果的融合排序比例")).font(.caption).foregroundStyle(.secondary)
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

    // MARK: - External Sources

    private var externalTab: some View {
        Form {
            Section(L("Memos 搜索源")) {
                if settings.memosSources.isEmpty {
                    Text(L("暂无 Memos 搜索源。添加后，网页端可以选择同时搜索 Memos。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($settings.memosSources) { $source in
                        memosSourceEditor(source: $source)
                    }
                }
                Button {
                    settings.memosSources.append(MemosSourceConfig(name: nextMemosName()))
                } label: {
                    Label(L("添加 Memos 源"), systemImage: "plus.circle")
                }
            }
            Section(L("说明")) {
                Text(L("Token/SK 会按你的要求保存在本地 settings.json。请只在可信设备上使用。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("源名称为空时会按顺序显示为 Memos 1、Memos 2。"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func memosSourceEditor(source: Binding<MemosSourceConfig>) -> some View {
        let sourceID = source.wrappedValue.id
        let index = settings.memosSources.firstIndex { $0.id == sourceID } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: source.isEnabled).labelsHidden()
                Text(source.wrappedValue.displayName(index: index))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(L("测试连接")) {
                    testMemosSource(sourceID: sourceID)
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    settings.memosSources.removeAll { $0.id == sourceID }
                    memosValidationMessages.removeValue(forKey: sourceID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField(L("源名称（可选）"), text: source.name)
                .textFieldStyle(.roundedBorder)
            TextField("https://memos.example.com", text: source.baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("Token / SK", text: source.token)
                .textFieldStyle(.roundedBorder)
            if let message = memosValidationMessages[sourceID] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("✓") ? .green : .red)
            }
        }
        .padding(.vertical, 6)
    }

    private func nextMemosName() -> String {
        "Memos \(settings.memosSources.count + 1)"
    }

    private func testMemosSource(sourceID: String) {
        memosValidationMessages[sourceID] = L("测试中...")
        Task {
            let result = await MemosSearchService.shared.validate(sourceID: sourceID)
            await MainActor.run {
                memosValidationMessages[sourceID] = result.ok ? "✓ \(result.message)" : "✗ \(result.message)"
            }
        }
    }

    // MARK: - Index

    private var indexTab: some View {
        Form {
            Section(L("图片 OCR")) {
                Toggle(L("启用图片 OCR 索引"), isOn: $settings.enableImageOCR)
                if settings.enableImageOCR {
                    Picker(L("OCR 来源"), selection: $settings.imageOCRScope) {
                        ForEach(ImageOCRScope.allCases) { scope in
                            Text(scope.displayName).tag(scope.rawValue)
                        }
                    }
                }
                Text(L("开启后会把图片中的识别文字写入索引，首次索引会更慢。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("仅 Markdown 图片会把 Markdown 引用图像的 OCR 文本并入文档索引；Markdown + 独立图片会额外索引未被 Markdown 引用的图片文件。"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
            Section(L("存储与内存占用")) {
                VStack(alignment: .leading, spacing: 12) {
                    RainbowUsageRow(
                        title: L("应用体积"),
                        valueText: ByteCountFormatter.paozierString(fromByteCount: usageSnapshot.appSizeBytes),
                        detailText: usageSnapshot.appLocation,
                        fraction: usageSnapshot.appSizeFraction
                    )
                    RainbowUsageRow(
                        title: L("本地数据"),
                        valueText: ByteCountFormatter.paozierString(fromByteCount: usageSnapshot.dataSizeBytes),
                        detailText: "~/Library/Application Support/Paozier/",
                        fraction: usageSnapshot.dataSizeFraction
                    )
                    RainbowUsageRow(
                        title: L("当前内存"),
                        valueText: ByteCountFormatter.paozierString(fromByteCount: usageSnapshot.memoryBytes),
                        detailText: LF("物理内存 %@", ByteCountFormatter.paozierString(fromByteCount: usageSnapshot.physicalMemoryBytes)),
                        fraction: usageSnapshot.memoryFraction
                    )
                    HStack {
                        Spacer()
                        Button(L("刷新")) {
                            usageSnapshot = SystemUsageSnapshot.load(dataDirectory: dataDirectory)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            usageSnapshot = SystemUsageSnapshot.load(dataDirectory: dataDirectory)
        }
        .alert(L("确认操作"), isPresented: $showClearConfirm) {
            Button(L("取消"), role: .cancel) {}
            Button(L("确认"), role: .destructive) { performClear() }
        } message: {
            Text(clearMessage)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: AppIconManager.currentIcon(settings: settings, size: 96))
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Paozier")
                            .font(.system(size: 17, weight: .semibold))
                            .fontWeight(.semibold)
                        Text(LF("版本 %@", appVersionText))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Section(L("应用图标")) {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                        ForEach(AppIconPreset.allCases) { preset in
                            appIconPresetButton(preset)
                        }
                    }

                    HStack {
                        Button {
                            importCustomIcon()
                        } label: {
                            Label(L("选择自定义图标"), systemImage: "photo")
                        }
                        .controlSize(.small)

                        if !settings.customAppIconPath.isEmpty {
                            Button(L("在 Finder 中显示")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settings.customAppIconPath)])
                            }
                            .controlSize(.small)
                        }
                    }

                    if !iconImportError.isEmpty {
                        Text(iconImportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text(L("图标会同步用于 Dock、关于页和网页搜索页。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section(L("源码")) {
                HStack {
                    Text("github.com/mcxen/paozier")
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(Self.githubURL)
                    } label: {
                        Label(L("打开 GitHub"), systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
            }
            Section(L("更新")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            checkForUpdates()
                        } label: {
                            Label(L("检查更新"), systemImage: "arrow.clockwise")
                        }
                        .disabled(updateState.isBusy)
                        .controlSize(.small)

                        if updateState.isBusy {
                            ProgressView().controlSize(.small)
                        }
                    }
                    updateStatusView
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appIconPresetButton(_ preset: AppIconPreset) -> some View {
        let selected = settings.appIconPreset == preset.rawValue
        let image = AppIconManager.presetIcon(preset, size: 80)
        return Button {
            if preset == .custom && settings.customAppIconPath.isEmpty {
                importCustomIcon()
            } else {
                settings.appIconPreset = preset.rawValue
                settings.save()
                AppIconManager.applyCurrentIcon(settings: settings)
            }
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: preset == .custom ? AppIconManager.currentIcon(settings: settings, size: 80) : image)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                Text(preset.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func importCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("选择一张方形图片作为 Paozier 图标")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try AppIconManager.importCustomIcon(from: url, settings: settings)
            iconImportError = ""
        } catch {
            iconImportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateState {
        case .idle:
            Text(L("从 GitHub Releases 读取最新版本。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            Text(L("正在检查 GitHub Releases..."))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .installing(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .latest(let release):
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("已是最新版本：%@", release.versionText))
                    .font(.caption)
                    .foregroundStyle(.green)
                installUpdateButton(release)
                releaseLinkButton(release)
            }
        case .available(let release):
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("发现新版本：%@", release.versionText))
                    .font(.caption)
                    .foregroundStyle(.orange)
                installUpdateButton(release)
                releaseLinkButton(release)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func installUpdateButton(_ release: GitHubRelease) -> some View {
        Button {
            installUpdate(release)
        } label: {
            Label(L("一键更新"), systemImage: "arrow.down.app")
        }
        .disabled(!release.hasDMGAsset || updateState.isBusy)
        .controlSize(.small)
        .help(release.hasDMGAsset ? L("下载最新 DMG 并覆盖当前应用") : L("此 Release 未提供 DMG"))
    }

    private func releaseLinkButton(_ release: GitHubRelease) -> some View {
        Button {
            NSWorkspace.shared.open(release.htmlURL)
        } label: {
            Label(L("查看 Release"), systemImage: "safari")
        }
        .controlSize(.small)
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let version, let build {
            return "\(version) (\(build))"
        }
        if let version {
            return version
        }
        return L("开发版")
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            do {
                let release = try await GitHubReleaseClient.latestRelease()
                let state: ReleaseCheckState = release.isNewer(than: appVersionText) ? .available(release) : .latest(release)
                await MainActor.run {
                    updateState = state
                }
            } catch {
                await MainActor.run {
                    updateState = .failed(LF("检查更新失败：%@", error.localizedDescription))
                }
            }
        }
    }

    private func installUpdate(_ release: GitHubRelease) {
        updateState = .installing(L("正在下载更新..."))
        Task {
            do {
                try await PaozierAppUpdater.install(release: release)
            } catch {
                await MainActor.run {
                    updateState = .failed(LF("更新失败：%@", error.localizedDescription))
                }
            }
        }
    }

    private static let githubURL = URL(string: "https://github.com/mcxen/paozier")!

    private static var defaultDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Paozier", isDirectory: true)
    }

    private var dataDirectory: URL {
        Self.defaultDataDirectory
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

private struct SettingsPersistenceModifier: ViewModifier {
    @ObservedObject var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .onReceive(settings.objectWillChange) { _ in
                Task { @MainActor in
                    await Task.yield()
                    settings.save()
                    QuickSearchStatusItemController.shared.sync()
                    QuickSearchPanelController.shared.applySettings()
                    AppIconManager.applyCurrentIcon(settings: settings)
                }
            }
            .onDisappear {
                settings.save()
                QuickSearchStatusItemController.shared.sync()
                QuickSearchPanelController.shared.applySettings()
                AppIconManager.applyCurrentIcon(settings: settings)
            }
    }
}

private struct SystemUsageSnapshot {
    let appSizeBytes: Int64
    let dataSizeBytes: Int64
    let memoryBytes: Int64
    let physicalMemoryBytes: Int64
    let appLocation: String

    var appSizeFraction: Double {
        scaledStorageFraction(appSizeBytes)
    }

    var dataSizeFraction: Double {
        scaledStorageFraction(dataSizeBytes)
    }

    var memoryFraction: Double {
        guard physicalMemoryBytes > 0 else { return 0 }
        return min(Double(memoryBytes) / Double(physicalMemoryBytes), 1)
    }

    static func load(dataDirectory: URL) -> SystemUsageSnapshot {
        let appURL = Bundle.main.bundleURL
        let appSize = FileSystemSizeReader.sizeOfItem(at: appURL)
        let dataSize = FileSystemSizeReader.sizeOfItem(at: dataDirectory)
        let memory = ProcessMemoryReader.currentResidentSize()
        let physicalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
        return SystemUsageSnapshot(
            appSizeBytes: appSize,
            dataSizeBytes: dataSize,
            memoryBytes: memory,
            physicalMemoryBytes: physicalMemory,
            appLocation: appURL.path
        )
    }

    private func scaledStorageFraction(_ bytes: Int64) -> Double {
        guard bytes > 0 else { return 0 }
        let oneGB = 1024.0 * 1024.0 * 1024.0
        return min(Double(bytes) / oneGB, 1)
    }
}

private enum FileSystemSizeReader {
    static func sizeOfItem(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if isDirectory.boolValue {
            return sizeOfDirectory(at: url)
        }
        return sizeOfFile(at: url)
    }

    private static func sizeOfDirectory(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += sizeOfFile(at: fileURL)
        }
        return total
    }

    private static func sizeOfFile(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        guard values.isRegularFile == true else { return 0 }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        return Int64(size)
    }
}

private enum ProcessMemoryReader {
    static func currentResidentSize() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
}

private struct RainbowUsageRow: View {
    let title: String
    let valueText: String
    let detailText: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(valueText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * fraction))
                }
            }
            .frame(height: 8)
            Text(detailText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private enum ReleaseCheckState {
    case idle
    case checking
    case installing(String)
    case latest(GitHubRelease)
    case available(GitHubRelease)
    case failed(String)

    var isBusy: Bool {
        if case .checking = self { return true }
        if case .installing = self { return true }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    var versionText: String {
        if let name, !name.isEmpty, name != tagName {
            return "\(tagName) · \(name)"
        }
        return tagName
    }

    var dmgAsset: GitHubReleaseAsset? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }
    }

    var hasDMGAsset: Bool {
        dmgAsset != nil
    }

    func isNewer(than currentVersion: String) -> Bool {
        VersionComparator.is(tagName, newerThan: currentVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

private enum GitHubReleaseClient {
    static func latestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/mcxen/paozier/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Paozier", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ReleaseCheckError.badResponse
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

private enum ReleaseCheckError: LocalizedError {
    case badResponse
    case noDMGAsset
    case notAppBundle
    case helperScriptFailed

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return L("GitHub 返回了非成功状态")
        case .noDMGAsset:
            return L("此 Release 未提供 DMG")
        case .notAppBundle:
            return L("当前不是 .app 包，不能自动覆盖安装")
        case .helperScriptFailed:
            return L("无法启动更新助手")
        }
    }
}

private enum PaozierAppUpdater {
    static func install(release: GitHubRelease) async throws {
        guard let asset = release.dmgAsset else { throw ReleaseCheckError.noDMGAsset }

        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { throw ReleaseCheckError.notAppBundle }

        let fileManager = FileManager.default
        let updateDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("paozier-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)

        let (downloadedFile, _) = try await URLSession.shared.download(from: asset.downloadURL)
        let dmgURL = updateDirectory.appendingPathComponent(asset.name)
        try fileManager.moveItem(at: downloadedFile, to: dmgURL)

        let scriptURL = updateDirectory.appendingPathComponent("install-paozier-update.sh")
        let script = helperScript(appURL: appURL, dmgURL: dmgURL, updateDirectory: updateDirectory)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        do {
            try process.run()
        } catch {
            throw ReleaseCheckError.helperScriptFailed
        }

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private static func helperScript(appURL: URL, dmgURL: URL, updateDirectory: URL) -> String {
        let appPath = shellQuoted(appURL.path)
        let dmgPath = shellQuoted(dmgURL.path)
        let updatePath = shellQuoted(updateDirectory.path)
        return """
        #!/bin/zsh
        set -euo pipefail

        APP_PATH=\(appPath)
        DMG_PATH=\(dmgPath)
        UPDATE_DIR=\(updatePath)
        MOUNT_DIR="$UPDATE_DIR/mount"

        sleep 1
        mkdir -p "$MOUNT_DIR"

        cleanup() {
            /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
            /bin/rm -rf "$UPDATE_DIR"
        }
        trap cleanup EXIT

        /usr/bin/hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -quiet
        SOURCE_APP="$(/usr/bin/find "$MOUNT_DIR" -maxdepth 3 -name "Paozier.app" -type d | /usr/bin/head -n 1)"
        if [[ -z "$SOURCE_APP" ]]; then
            exit 1
        fi

        if ! /usr/bin/ditto "$SOURCE_APP" "$APP_PATH"; then
            ADMIN_SOURCE="$(/usr/bin/python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$SOURCE_APP")"
            ADMIN_TARGET="$(/usr/bin/python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$APP_PATH")"
            ADMIN_COMMAND="/usr/bin/ditto $ADMIN_SOURCE $ADMIN_TARGET"
            ESCAPED_ADMIN_COMMAND="${ADMIN_COMMAND//\\/\\\\}"
            ESCAPED_ADMIN_COMMAND="${ESCAPED_ADMIN_COMMAND//\\"/\\\\\\"}"
            /usr/bin/osascript -e "do shell script \\"$ESCAPED_ADMIN_COMMAND\\" with administrator privileges"
        fi

        /usr/bin/open "$APP_PATH"
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private enum VersionComparator {
    static func `is`(_ candidate: String, newerThan current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = normalizedVersionParts(lhs)
        let rhsParts = normalizedVersionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue > rhsValue { return .orderedDescending }
            if lhsValue < rhsValue { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func normalizedVersionParts(_ version: String) -> [Int] {
        version
            .lowercased()
            .replacingOccurrences(of: "version", with: "")
            .replacingOccurrences(of: "v", with: "")
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

private extension ByteCountFormatter {
    static func paozierString(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
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
