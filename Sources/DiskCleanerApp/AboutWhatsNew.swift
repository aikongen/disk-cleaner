import Foundation

/// Reads the "What's new" line for a version from the bundled CHANGELOG.md.
enum AboutWhatsNew {
    /// The first bullet of the section headed `## <version>` (for example `## 0.1.0 - 2026-11-04`),
    /// with inline Markdown marks removed. Nil when the version has no section or no bullet.
    static func line(for version: String, in changelog: String) -> String? {
        var inSection = false
        for raw in changelog.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if inSection { return nil }
                let head = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                inSection = head == version || head.hasPrefix(version + " ")
            } else if inSection, line.hasPrefix("- ") {
                return plain(String(line.dropFirst(2)))
            }
        }
        return nil
    }

    static func plain(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Reads the CHANGELOG.md copied into the app bundle; nil outside a packaged app.
    static func bundled(version: String?) -> String? {
        guard let version, let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return line(for: version, in: text)
    }
}
