import AppKit
import Foundation

enum AppIconPreset: String, CaseIterable, Identifiable {
    case `default`
    case ocean
    case violet
    case graphite
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return L("默认")
        case .ocean: return L("海蓝")
        case .violet: return L("紫夜")
        case .graphite: return L("石墨")
        case .custom: return L("自定义")
        }
    }

    var accentColor: NSColor? {
        switch self {
        case .default, .custom:
            return nil
        case .ocean:
            return NSColor(calibratedRed: 0.0, green: 0.43, blue: 1.0, alpha: 1)
        case .violet:
            return NSColor(calibratedRed: 0.52, green: 0.22, blue: 1.0, alpha: 1)
        case .graphite:
            return NSColor(calibratedWhite: 0.18, alpha: 1)
        }
    }
}

@MainActor
enum AppIconManager {
    static let githubURL = URL(string: "https://github.com/mcxen/paozier")!

    static func applyCurrentIcon(settings: AppSettings) {
        NSApp.applicationIconImage = currentIcon(settings: settings)
    }

    static func currentIcon(settings: AppSettings, size: CGFloat = 256) -> NSImage {
        let preset = AppIconPreset(rawValue: settings.appIconPreset) ?? .default
        if preset == .custom,
           let custom = customIcon(at: settings.customAppIconPath, size: size) {
            return custom
        }
        return presetIcon(preset, size: size)
    }

    static func presetIcon(_ preset: AppIconPreset, size: CGFloat = 256) -> NSImage {
        let base = bundledAppIcon(size: size)
        guard let accent = preset.accentColor else { return base }
        return tintedIcon(base: base, accent: accent, size: size)
    }

    static func currentIconSVG(settings: AppSettings, size: Int = 128) -> String {
        let image = currentIcon(settings: settings, size: CGFloat(size))
        let base64 = pngData(image)?.base64EncodedString() ?? ""
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)">
          <image href="data:image/png;base64,\(base64)" width="\(size)" height="\(size)" />
        </svg>
        """
    }

    static func importCustomIcon(from sourceURL: URL, settings: AppSettings) throws {
        let fileManager = FileManager.default
        let iconDirectory = appSupportDirectory.appendingPathComponent("Icons", isDirectory: true)
        try fileManager.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

        let destination = iconDirectory.appendingPathComponent("CustomAppIcon.png")
        guard let image = NSImage(contentsOf: sourceURL),
              let data = pngData(fittedImage(image, size: 1024)) else {
            throw AppIconError.invalidImage
        }
        try data.write(to: destination, options: .atomic)
        settings.customAppIconPath = destination.path
        settings.appIconPreset = AppIconPreset.custom.rawValue
        settings.save()
        applyCurrentIcon(settings: settings)
    }

    private static var appSupportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Paozier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func customIcon(at path: String, size: CGFloat) -> NSImage? {
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let image = NSImage(contentsOfFile: path) else { return nil }
        return fittedImage(image, size: size)
    }

    private static func bundledAppIcon(size: CGFloat) -> NSImage {
        let candidates = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("Paozier_Paozier.bundle/Contents/Resources/AppIcon.png"),
            Bundle.main.resourceURL?.appendingPathComponent("Paozier_Paozier.bundle/AppIcon.png"),
            Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png")
        ].compactMap { $0 }

        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                return fittedImage(image, size: size)
            }
        }
        return fittedImage(NSApp.applicationIconImage, size: size)
    }

    private static func tintedIcon(base: NSImage, accent: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.22
        let background = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: radius, yRadius: radius)
        accent.withAlphaComponent(0.22).setFill()
        background.fill()

        let iconRect = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
        base.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

        accent.withAlphaComponent(0.32).setFill()
        NSBezierPath(ovalIn: NSRect(x: size * 0.66, y: size * 0.66, width: size * 0.22, height: size * 0.22)).fill()

        image.unlockFocus()
        return image
    }

    private static func fittedImage(_ source: NSImage, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        return image
    }

    private static func pngData(_ image: NSImage?) -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

enum AppIconError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return L("无法读取所选图片")
        }
    }
}
