import Foundation

struct WindowFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(origin: CGPoint, size: CGSize) {
        self.x = Double(origin.x)
        self.y = Double(origin.y)
        self.width = Double(size.width)
        self.height = Double(size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var origin: CGPoint {
        CGPoint(x: x, y: y)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct WindowSnapshot: Codable, Equatable {
    let bundleId: String
    let windowTitle: String
    let stableTitle: String  // Extracted stable part of title for matching
    let windowIndex: Int     // Window order within the app (fallback matching)
    let frame: WindowFrame

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case windowTitle = "window_title"
        case stableTitle = "stable_title"
        case windowIndex = "window_index"
        case frame
    }

    init(bundleId: String, windowTitle: String, windowIndex: Int, frame: WindowFrame) {
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.stableTitle = Self.extractStableTitle(from: windowTitle)
        self.windowIndex = windowIndex
        self.frame = frame
    }

    /// Extract stable part of title (before dynamic suffixes like dimensions, status)
    static func extractStableTitle(from title: String) -> String {
        // Common separators that precede dynamic content
        let separators = [" — ", " - ", " | ", " – ", " : "]

        var result = title

        // For Terminal: remove dimensions like "194×53" at the end
        if let range = result.range(of: #"\s+\d+×\d+$"#, options: .regularExpression) {
            result = String(result[..<range.lowerBound])
        }

        // Split by separators and take meaningful parts
        for sep in separators {
            let parts = result.components(separatedBy: sep)
            if parts.count > 1 {
                // Keep first part, or first two if first is very short (like app name)
                if parts[0].count < 20 && parts.count > 1 {
                    result = parts.prefix(2).joined(separator: sep)
                } else {
                    result = parts[0]
                }
                break
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}

struct DisplaySnapshot: Codable, Equatable {
    let displayUUID: String
    let windows: [WindowSnapshot]

    enum CodingKeys: String, CodingKey {
        case displayUUID = "display_uuid"
        case windows
    }
}

struct Layout: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let name: String
    let createdAt: Date
    let displays: [DisplaySnapshot]

    enum CodingKeys: String, CodingKey {
        case version
        case name
        case createdAt = "created_at"
        case displays
    }

    init(name: String, displays: [DisplaySnapshot]) {
        self.version = Self.currentVersion
        self.name = name
        self.createdAt = Date()
        self.displays = displays
    }

    init(version: Int, name: String, createdAt: Date, displays: [DisplaySnapshot]) {
        self.version = version
        self.name = name
        self.createdAt = createdAt
        self.displays = displays
    }
}
