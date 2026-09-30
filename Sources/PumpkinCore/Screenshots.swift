import Foundation

/// Finds macOS screenshots and screen recordings.
public enum Screenshots {
    static let captureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// Default names, used only when a file lacks the screen-capture tag.
    static let namePrefixes = ["Screenshot ", "Screen Shot ", "Screen Recording ", "Снимок экрана", "Запись экрана"]

    /// True for files the Screenshot app made. macOS tags them with
    /// `kMDItemIsScreenCapture`, so this works in every language and with
    /// custom names. Other files are never mistaken for screenshots.
    public static func isScreenCapture(_ url: URL) -> Bool {
        if let data = DownloadSource.extendedAttribute(captureAttribute, of: url),
           let value = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            if let flag = value as? Bool { return flag }
            if let number = value as? NSNumber { return number.boolValue }
        }
        return looksLikeScreenshot(name: url.lastPathComponent)
    }

    public static func looksLikeScreenshot(name: String) -> Bool {
        namePrefixes.contains { name.hasPrefix($0) }
    }

    /// Where macOS saves screenshots (Screenshot app › Options › Save to).
    /// Falls back to the Desktop, which is the system default.
    public static func folder(preferences: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture")) -> URL {
        folder(location: preferences?.string(forKey: "location"))
    }

    /// Resolves a Screenshot-app `location` value, falling back to the Desktop
    /// when it's unset or no longer exists.
    public static func folder(location raw: String?) -> URL {
        if let raw, !raw.isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
