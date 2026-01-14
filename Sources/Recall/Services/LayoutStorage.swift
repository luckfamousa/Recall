import Foundation

class LayoutStorage {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var layoutsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Recall/layouts", isDirectory: true)
    }

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(at: layoutsDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for name: String) -> URL {
        let sanitizedName = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return layoutsDirectory.appendingPathComponent("\(sanitizedName).json")
    }

    func save(_ layout: Layout) throws {
        let data = try encoder.encode(layout)
        let url = fileURL(for: layout.name)
        try data.write(to: url, options: .atomic)
    }

    func loadAll() -> [Layout] {
        ensureDirectoryExists()

        guard let urls = try? fileManager.contentsOfDirectory(
            at: layoutsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Layout? in
                guard let data = try? Data(contentsOf: url),
                      let layout = try? decoder.decode(Layout.self, from: data) else {
                    return nil
                }
                return layout
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ layout: Layout) throws {
        let url = fileURL(for: layout.name)
        try fileManager.removeItem(at: url)
    }

    func exists(_ name: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: name).path)
    }

    func url(for layout: Layout) -> URL {
        fileURL(for: layout.name)
    }
}
