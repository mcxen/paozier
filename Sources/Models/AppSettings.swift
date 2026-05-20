import Foundation

enum ImageOCRScope: String, CaseIterable, Identifiable, Codable {
    case markdownOnly = "markdown_only"
    case markdownAndStandalone = "markdown_and_standalone"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdownOnly:
            return L("仅 Markdown 图片")
        case .markdownAndStandalone:
            return L("Markdown + 独立图片")
        }
    }
}

@MainActor
class AppSettings: ObservableObject, Codable {
    static let shared = AppSettings()

    @Published var searchResultLimit: Int = 30
    @Published var searchEngineWeightSK: Double = 0.6
    @Published var searchEngineWeightFTS: Double = 0.4
    @Published var httpPort: Int = 9880
    @Published var httpAutoStart: Bool = true
    @Published var mcpPort: Int = 9881
    @Published var mcpAutoStart: Bool = true
    @Published var defaultPreviewMode: String = "live"
    @Published var historyMaxItems: Int = 100
    @Published var excludedExtensions: [String] = []
    @Published var searchFilenames: Bool = true
    @Published var languagePreference: String = AppLanguagePreference.system.rawValue
    @Published var matchContextChars: Int = 40
    @Published var enableImageOCR: Bool = false
    @Published var imageOCRScope: String = ImageOCRScope.markdownOnly.rawValue
    @Published var memosSources: [MemosSourceConfig] = []
    @Published var quickSearchMenuBarEnabled: Bool = false
    @Published var quickSearchPanelAlwaysOnTop: Bool = true
    @Published var appIconPreset: String = AppIconPreset.default.rawValue
    @Published var customAppIconPath: String = ""

    private static var filePath: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Paozier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    enum CodingKeys: String, CodingKey {
        case searchResultLimit, searchEngineWeightSK, searchEngineWeightFTS
        case httpPort, httpAutoStart, mcpPort, mcpAutoStart
        case defaultPreviewMode, historyMaxItems, excludedExtensions, searchFilenames, languagePreference, matchContextChars, enableImageOCR, imageOCRScope, memosSources
        case quickSearchMenuBarEnabled, quickSearchPanelAlwaysOnTop
        case appIconPreset, customAppIconPath
    }

    init() { load() }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchResultLimit = (try? c.decode(Int.self, forKey: .searchResultLimit)) ?? 30
        searchEngineWeightSK = (try? c.decode(Double.self, forKey: .searchEngineWeightSK)) ?? 0.6
        searchEngineWeightFTS = (try? c.decode(Double.self, forKey: .searchEngineWeightFTS)) ?? 0.4
        httpPort = (try? c.decode(Int.self, forKey: .httpPort)) ?? 9880
        httpAutoStart = (try? c.decode(Bool.self, forKey: .httpAutoStart)) ?? true
        mcpPort = (try? c.decode(Int.self, forKey: .mcpPort)) ?? 9881
        mcpAutoStart = (try? c.decode(Bool.self, forKey: .mcpAutoStart)) ?? true
        defaultPreviewMode = (try? c.decode(String.self, forKey: .defaultPreviewMode)) ?? "live"
        historyMaxItems = (try? c.decode(Int.self, forKey: .historyMaxItems)) ?? 100
        excludedExtensions = (try? c.decode([String].self, forKey: .excludedExtensions)) ?? []
        searchFilenames = (try? c.decode(Bool.self, forKey: .searchFilenames)) ?? true
        languagePreference = (try? c.decode(String.self, forKey: .languagePreference)) ?? AppLanguagePreference.system.rawValue
        matchContextChars = (try? c.decode(Int.self, forKey: .matchContextChars)) ?? 40
        enableImageOCR = (try? c.decode(Bool.self, forKey: .enableImageOCR)) ?? false
        imageOCRScope = (try? c.decode(String.self, forKey: .imageOCRScope)) ?? ImageOCRScope.markdownOnly.rawValue
        memosSources = (try? c.decode([MemosSourceConfig].self, forKey: .memosSources)) ?? []
        quickSearchMenuBarEnabled = (try? c.decode(Bool.self, forKey: .quickSearchMenuBarEnabled)) ?? false
        quickSearchPanelAlwaysOnTop = (try? c.decode(Bool.self, forKey: .quickSearchPanelAlwaysOnTop)) ?? true
        appIconPreset = (try? c.decode(String.self, forKey: .appIconPreset)) ?? AppIconPreset.default.rawValue
        customAppIconPath = (try? c.decode(String.self, forKey: .customAppIconPath)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(searchResultLimit, forKey: .searchResultLimit)
        try c.encode(searchEngineWeightSK, forKey: .searchEngineWeightSK)
        try c.encode(searchEngineWeightFTS, forKey: .searchEngineWeightFTS)
        try c.encode(httpPort, forKey: .httpPort)
        try c.encode(httpAutoStart, forKey: .httpAutoStart)
        try c.encode(mcpPort, forKey: .mcpPort)
        try c.encode(mcpAutoStart, forKey: .mcpAutoStart)
        try c.encode(defaultPreviewMode, forKey: .defaultPreviewMode)
        try c.encode(historyMaxItems, forKey: .historyMaxItems)
        try c.encode(excludedExtensions, forKey: .excludedExtensions)
        try c.encode(searchFilenames, forKey: .searchFilenames)
        try c.encode(languagePreference, forKey: .languagePreference)
        try c.encode(matchContextChars, forKey: .matchContextChars)
        try c.encode(enableImageOCR, forKey: .enableImageOCR)
        try c.encode(imageOCRScope, forKey: .imageOCRScope)
        try c.encode(memosSources, forKey: .memosSources)
        try c.encode(quickSearchMenuBarEnabled, forKey: .quickSearchMenuBarEnabled)
        try c.encode(quickSearchPanelAlwaysOnTop, forKey: .quickSearchPanelAlwaysOnTop)
        try c.encode(appIconPreset, forKey: .appIconPreset)
        try c.encode(customAppIconPath, forKey: .customAppIconPath)
    }

    func save() {
        UserDefaults.standard.set(languagePreference, forKey: "languagePreference")
        try? JSONEncoder().encode(self).write(to: Self.filePath)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.filePath),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        searchResultLimit = decoded.searchResultLimit
        searchEngineWeightSK = decoded.searchEngineWeightSK
        searchEngineWeightFTS = decoded.searchEngineWeightFTS
        httpPort = decoded.httpPort
        httpAutoStart = decoded.httpAutoStart
        mcpPort = decoded.mcpPort
        mcpAutoStart = decoded.mcpAutoStart
        defaultPreviewMode = decoded.defaultPreviewMode
        historyMaxItems = decoded.historyMaxItems
        excludedExtensions = decoded.excludedExtensions
        searchFilenames = decoded.searchFilenames
        languagePreference = decoded.languagePreference
        matchContextChars = decoded.matchContextChars
        enableImageOCR = decoded.enableImageOCR
        imageOCRScope = decoded.imageOCRScope
        memosSources = decoded.memosSources
        quickSearchMenuBarEnabled = decoded.quickSearchMenuBarEnabled
        quickSearchPanelAlwaysOnTop = decoded.quickSearchPanelAlwaysOnTop
        appIconPreset = decoded.appIconPreset
        customAppIconPath = decoded.customAppIconPath
        UserDefaults.standard.set(languagePreference, forKey: "languagePreference")
    }
}
