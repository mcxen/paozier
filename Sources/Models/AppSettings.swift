import Foundation

@MainActor
class AppSettings: ObservableObject, @preconcurrency Codable {
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

    private static var filePath: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Paozier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    enum CodingKeys: String, CodingKey {
        case searchResultLimit, searchEngineWeightSK, searchEngineWeightFTS
        case httpPort, httpAutoStart, mcpPort, mcpAutoStart
        case defaultPreviewMode, historyMaxItems, excludedExtensions
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
    }

    func save() {
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
    }
}
