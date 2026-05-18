import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case zh
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

enum AppLanguage {
    case zh
    case en
}

enum L10n {
    static var currentLanguage: AppLanguage {
        let preference = AppLanguagePreference(rawValue: UserDefaults.standard.string(forKey: "languagePreference") ?? AppLanguagePreference.system.rawValue) ?? .system
        switch preference {
        case .zh:
            return .zh
        case .en:
            return .en
        case .system:
            let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()
            return identifier.hasPrefix("zh") ? .zh : .en
        }
    }

    static func text(_ key: String) -> String {
        switch currentLanguage {
        case .zh:
            return key
        case .en:
            return en[key] ?? key
        }
    }

    private static let en: [String: String] = [
        "跟随系统": "Follow System",
        "设置": "Settings",
        "完成": "Done",
        "通用": "General",
        "搜索": "Search",
        "服务": "Services",
        "索引": "Index",
        "数据": "Data",
        "语言": "Language",
        "界面语言": "Display language",
        "预览": "Preview",
        "默认预览模式": "Default preview mode",
        "原文件": "Original",
        "历史记录": "History",
        "最大记录数: %d": "Max records: %d",
        "结果": "Results",
        "最大结果数: %d": "Max results: %d",
        "命中上下文字符数: %d": "Match context chars: %d",
        "引擎权重": "Engine weights",
        "权重决定双引擎结果的融合排序比例": "Weights control blended ranking across the two indexed engines.",
        "范围": "Scope",
        "同时搜索文件名": "Search filenames too",
        "HTTP 搜索服务": "HTTP search service",
        "端口": "Port",
        "启动时自动开启": "Start automatically",
        "MCP AI 工具服务": "MCP AI tool service",
        "MCP 配置 (复制到 AI 工具)": "MCP config (copy to AI tools)",
        "端口修改需重启应用生效": "Port changes take effect after restarting the app.",
        "排除的文件扩展名": "Excluded file extensions",
        "图片 OCR": "Image OCR",
        "启用图片 OCR 索引": "Enable image OCR indexing",
        "OCR 来源": "OCR source",
        "仅 Markdown 图片": "Markdown images only",
        "Markdown + 独立图片": "Markdown + standalone images",
        "开启后会把图片中的识别文字写入索引，首次索引会更慢。": "When enabled, recognized text from images is written into the index. Initial indexing will be slower.",
        "仅 Markdown 图片会把 Markdown 引用图像的 OCR 文本并入文档索引；Markdown + 独立图片会额外索引未被 Markdown 引用的图片文件。": "Markdown images only merges OCR text from Markdown-linked images into the document index. Markdown + standalone images also indexes image files not referenced by Markdown.",
        "扩展名（如 log）": "Extension, e.g. log",
        "添加": "Add",
        "无排除项 — 所有支持格式均会被索引": "No exclusions. All supported formats will be indexed.",
        "清除数据": "Clear data",
        "清除搜索历史": "Clear search history",
        "清除报告数据": "Clear report data",
        "重建全部索引": "Rebuild all indexes",
        "存储位置": "Storage location",
        "打开": "Open",
        "确认操作": "Confirm action",
        "取消": "Cancel",
        "确认": "Confirm",
        "将清除所有搜索历史记录": "All search history will be cleared.",
        "将清除所有报告数据": "All report data will be cleared.",
        "将删除并重建全部索引，耗时较长": "All indexes will be deleted and rebuilt. This can take a while.",
        "TCP 连接方式 (Claude Desktop / Cline / Cursor)": "TCP connection (Claude Desktop / Cline / Cursor)",
        "已复制": "Copied",
        "复制": "Copy",
        "复制全文": "Copy Text",
        "索引管理": "Index Management",
        "重建全部": "Rebuild All",
        "索引任务运行中": "Indexing in progress",
        "索引就绪": "Index ready",
        "%d 个文档": "%d documents",
        "资源占用": "Resource Usage",
        "当前进程内存 / 物理内存": "Current process memory / physical memory",
        "索引结果": "Indexed Folders",
        "%d 个文件夹": "%d folders",
        "刷新文件数量": "Refresh file count",
        "路径": "Path",
        "文件数": "Files",
        "上次索引": "Last indexed",
        "尚未完成": "Not completed",
        "查看文件": "View Files",
        "查看文件列表": "View file list",
        "重新索引": "Reindex",
        "清理索引": "Clear Index",
        "移除文件夹": "Remove Folder",
        "在 Finder 中显示": "Show in Finder",
        "暂无索引文件夹": "No indexed folders",
        "会清除该文件夹在搜索引擎里的索引记录，文件夹本身和原文件不会被删除。": "This clears this folder's index records only. The folder and source files are not deleted.",
        "会移除该文件夹并清理对应索引，原文件不会被删除。": "This removes the folder from Paozier and clears its index records. Source files are not deleted.",
        "确认清理索引？": "Clear this index?",
        "确认移除文件夹？": "Remove this folder?",
        "引擎": "Engine",
        "文件夹": "Folders",
        "添加文件夹": "Add Folder",
        "打开网页搜索": "Open Web Search",
        "支持格式": "Supported Formats",
        "代码文件": "Code files",
        "就绪": "Ready",
        "初始化": "Initializing",
        "索引中": "Indexing",
        "队列中": "Queued",
        "扫描中": "Scanning",
        "已完成": "Completed",
        "需关注": "Needs attention",
        "空闲": "Idle",
        "管理": "Manage",
        "查看索引详情": "View index details",
        "索引详情": "Index details",
        "OCR 文件": "OCR files",
        "OCR 模式": "OCR mode",
        "已开启": "Enabled",
        "未开启": "Disabled",
        "%d 个 OCR 文件": "%d OCR files",
        "队列中 %d 个文件夹": "%d folders queued",
        "排队中 · 第 %d 个": "Queued · #%d",
        "第 %d 个": "#%d",
        "等待前方 %d 个任务": "Waiting for %d jobs ahead",
        "该文件夹正在索引中": "This folder is currently being indexed",
        "正在索引的文件夹暂时不能移除": "The folder being indexed cannot be removed right now",
        "正在排队重建全部索引...": "Queueing a full rebuild...",
        "索引已清理": "Index cleared",
        "该文件不支持图片 OCR": "This file doesn't support image OCR",
        "图片 OCR 模式未开启": "Image OCR mode is disabled",
        "正在提取图片文字...": "Recognizing text from image...",
        "图片 OCR 索引完成": "Image OCR indexing complete",
        "图片 OCR 索引失败": "Image OCR indexing failed",
        "执行图片 OCR 索引": "Run image OCR indexing",
        "仅图片文件支持该操作": "Only image files support this action",
        "索引完成 · %d/%d · %d 个失败": "Indexed %d/%d · %d failed",
        "加载更多文件夹": "Load more folders",
        "状态": "Status",
        "索引进度": "Index progress",
        "失败数": "Failures",
        "开始时间": "Started",
        "结束时间": "Finished",
        "当前文件": "Current file",
        "最近文件": "Recent file",
        "最近错误": "Recent error",
        "%d 个文件失败": "%d files failed",
        "%d 文件": "%d files",
        "重新索引全部": "Reindex all",
        "搜索文档内容...": "Search document content...",
        "正在搜索...": "Searching...",
        "支持 PDF、Word、Excel、TXT、Markdown 等格式": "Supports PDF, Word, Excel, TXT, Markdown, and more.",
        "索引搜索": "Indexed",
        "快速检索": "Grep",
        "搜索条件": "Search filters",
        "快速搜索面板": "Quick search panel",
        "已找到 %d 个结果...": "Found %d results...",
        "%d 个结果": "%d results",
        "当前文档 %d 个命中": "%d matches in this document",
        "展开命中列表": "Expand match list",
        "收起命中列表": "Collapse match list",
        "报告": "Report",
        "搜索历史": "Search history",
        "输入关键词搜索全部文档": "Enter keywords to search all documents",
        "无匹配结果": "No matching results",
        "快速检索会直接扫描已添加文件夹": "Grep scans added folders directly.",
        "SearchKit + SQLite FTS5 双引擎 · 支持中英文": "SearchKit + SQLite FTS5 dual engines. Chinese and English supported.",
        "打开文件": "Open File",
        "添加到报告": "Add to Report",
        "导出高亮文档": "Export Highlighted Document",
        "收藏搜索": "Bookmark Search",
        "选择结果查看 Live Preview": "Select a result to view Live Preview",
        "高亮搜索词 · 直接复制文本 · 无需打开原文件": "Highlighted terms. Copy text directly. No need to open the original file.",
        "跳转搜索词高亮": "Jump between highlighted terms",
        "全部类型": "All types",
        "全部文件夹": "All folders",
        "指定文件夹": "Selected folders",
        "全部已添加文件夹": "All added folders",
        "正则": "Regex",
        "空格模糊": "Fuzzy spaces",
        "预览内查找": "Find in preview",
        "PDF": "PDF",
        "全部": "All",
        "代码": "Code",
        "报告名称": "Report name",
        "%d 条摘录": "%d excerpts",
        "导出": "Export",
        "关闭": "Close",
        "搜索时点击「添加到报告」收集摘录": "Use Add to Report while searching to collect excerpts.",
        "搜索: %@": "Search: %@",
        "移除": "Remove",
        "历史": "History",
        "书签": "Bookmarks",
        "清空历史": "Clear History",
        "%d 结果": "%d results",
        "%d 个支持文件": "%d supported files",
        "刷新": "Refresh",
        "没有可预览文件": "No previewable files",
        "选择文件预览": "Select a file to preview",
        "无法加载文件": "Unable to load file",
        "无法读取文件内容": "Unable to read file content",
        "无法识别文本编码": "Unable to detect text encoding",
        "无法读取文档": "Unable to read document",
        "全局搜索文档...": "Search documents globally...",
        "输入关键词搜索已索引文档": "Enter keywords to search indexed documents",
        "↑↓ 选择": "↑↓ Select",
        "⏎ 打开": "⏎ Open",
        "⎋ 关闭": "⎋ Close",
        "搜索...": "Search...",
        "输入关键词快速搜索": "Enter keywords for quick search",
        "无结果": "No results",
        "快速搜索": "Quick Search",
        "邻近搜索": "Proximity Search",
        "词语 1": "Term 1",
        "词语 2": "Term 2",
        "词距": "Distance",
        "%d 词": "%d words",
        "文件名匹配: %@": "Filename match: %@",
        "行%d: %@": "Line %d: %@",
        "Paozier 设置": "Paozier Settings",
        "就绪 · %d 个文档": "Ready · %d documents",
        "初始化搜索引擎...": "Initializing search engines...",
        "已有索引任务正在运行...": "An indexing task is already running...",
        "等待搜索引擎初始化...": "Waiting for search engines to initialize...",
        "扫描文件...": "Scanning files...",
        "未找到支持的文件": "No supported files found",
        "索引中 %d/%d": "Indexing %d/%d",
        "索引完成 · %d 个文档": "Index complete · %d documents",
        "索引完成 · %d 个文档 · %d 个失败": "Index complete · %d documents · %d failed",
        "已清理文件夹索引": "Folder index cleared",
        "已移除文件夹": "Folder removed"
    ]
}

func L(_ key: String) -> String {
    L10n.text(key)
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}
