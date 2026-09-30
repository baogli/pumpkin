import Foundation

/// Decides which directory entries are real, finished downloads worth asking about.
public enum DownloadFilter {
    /// Extensions browsers and download managers use while a transfer is still in flight.
    public static let partialExtensions: Set<String> = [
        "download",     // Safari
        "crdownload",   // Chrome, Edge, Brave, Arc, Vivaldi
        "part",         // Firefox
        "partial",
        "opdownload",   // Opera
        "tmp", "temp",
        "!ut",          // uTorrent
        "!qb",          // qBittorrent
        "aria2",
        "filepart",
        "dlpart",
        "fdmdownload",  // Free Download Manager
    ]

    /// Suffixes some browsers append to a final file name while it downloads next to a placeholder.
    static let partialSiblingSuffixes = ["part", "crdownload", "download", "opdownload", "partial"]

    static let ignoredNames: Set<String> = ["Icon\r"]

    /// True for hidden files, system clutter and in-progress downloads.
    public static func isIgnorable(name: String) -> Bool {
        if name.isEmpty || name.hasPrefix(".") || name.hasPrefix("~$") {
            return true
        }
        if ignoredNames.contains(name) {
            return true
        }
        let ext = (name as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }

    /// Firefox creates an empty placeholder with the final name plus a `.part` file
    /// holding the data; the placeholder is only real once the `.part` file is gone.
    public static func hasPartialSibling(_ name: String, among names: Set<String>) -> Bool {
        partialSiblingSuffixes.contains { names.contains("\(name).\($0)") }
    }
}
