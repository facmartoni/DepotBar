import AppKit

// MARK: - User config
//
// `~/.config/depotbar/config.json` (all keys optional):
//
//   { "theme": "system" }   // "system" (default) | "black" | "glass"
//
// The `DEPOTBAR_THEME` env var wins over the file. A missing or unreadable
// file (or an unknown theme name) silently falls back to `system`, keeping
// the zero-setup promise: DepotBar works with no config at all.

enum Theme: String, Sendable {
    case system
    case black
    case glass

    /// Case-insensitive parse; anything unknown (or blank/missing) is `system`.
    static func parse(_ value: String?) -> Theme {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty, let theme = Theme(rawValue: raw)
        else { return .system }
        return theme
    }

    /// Forced menu appearance (nil = follow the system). Both dark themes use
    /// the native dark menu: black chrome, white text, system frosted material.
    /// `glass` additionally swaps the menu-bar icon for a frosted capsule
    /// (see `StatusIconArt`).
    var menuAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .black, .glass:
            return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppConfig: Sendable {
    var theme: Theme = .system
    var notifyOnFailure: Bool = true

    struct FileBody: Codable {
        var theme: String?
        var notifyOnFailure: Bool?
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/depotbar/config.json")
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileURL: URL? = nil
    ) -> AppConfig {
        if let override = environment["DEPOTBAR_THEME"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return AppConfig(theme: Theme.parse(override))
        }
        let url = fileURL ?? Self.fileURL
        guard let data = try? Data(contentsOf: url),
              let body = try? JSONDecoder().decode(FileBody.self, from: data)
        else { return AppConfig() }
        return AppConfig(
            theme: Theme.parse(body.theme),
            notifyOnFailure: body.notifyOnFailure ?? true
        )
    }
}
