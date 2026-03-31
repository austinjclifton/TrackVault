import Foundation

enum AudioFileResolverError: Error {
    case fileNotFound
    case invalidPath
}

struct AudioFileResolver {

    private static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var documentsPathPrefix: String {
        documentsDir.standardizedFileURL.path.hasSuffix("/")
            ? documentsDir.standardizedFileURL.path
            : documentsDir.standardizedFileURL.path + "/"
    }

    static func audioURL(for storedPath: String) throws -> URL {
        let normalized = normalizeStoredPath(storedPath)
        guard !normalized.isEmpty else { throw AudioFileResolverError.invalidPath }

        let url = documentsDir.appendingPathComponent(normalized)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileResolverError.fileNotFound
        }

        return url
    }

    static func relativePath(from absoluteURL: URL) -> String {
        normalizeStoredPath(absoluteURL.path)
    }

    /// Canonical storage format: relative path under Documents, like "Audio/<uuid>.m4a"
    /// Accepts:
    /// - "Audio/<uuid>.m4a"
    /// - "/var/.../Documents/Audio/<uuid>.m4a"
    /// - "file:///var/.../Documents/Audio/<uuid>.m4a"
    static func normalizeStoredPath(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // file:// URL string
        if trimmed.hasPrefix("file://"), let u = URL(string: trimmed) {
            return normalizeStoredPath(u.path)
        }

        // absolute path
        if trimmed.hasPrefix("/") {
            let abs = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            if abs.hasPrefix(documentsPathPrefix) {
                return String(abs.dropFirst(documentsPathPrefix.count))
            }
            // If it’s absolute but not inside Documents, keep it (cleanup should treat as “in use”)
            return abs
        }

        // already relative
        return trimmed
    }
}
