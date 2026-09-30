import Foundation

/// Where a download came from, read from the metadata browsers attach to it.
/// Purely local: nothing here touches the network.
public enum DownloadSource {
    static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"
    static let quarantineAttribute = "com.apple.quarantine"

    /// "github.com", "Safari", or nil when the file carries no origin metadata.
    public static func describe(_ url: URL) -> String? {
        let hosts = whereFroms(of: url)
            .compactMap(URL.init(string:))
            .filter { ["http", "https", "ftp"].contains($0.scheme?.lowercased() ?? "") }
            .compactMap(\.host)
        // Browsers record [download URL, referring page]. The page is what people
        // recognise ("github.com" rather than a CDN host), so prefer it.
        if let host = hosts.count > 1 ? hosts[1] : hosts.first {
            return displayHost(host)
        }
        return quarantineAgent(of: url)
    }

    public static func whereFroms(of url: URL) -> [String] {
        guard let data = extendedAttribute(whereFromsAttribute, of: url),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return [] }
        return list
    }

    /// The app that downloaded the file, e.g. "Safari" or "Google Chrome".
    public static func quarantineAgent(of url: URL) -> String? {
        guard let data = extendedAttribute(quarantineAttribute, of: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let agent = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        return agent.isEmpty ? nil : agent
    }

    static func displayHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func extendedAttribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, length, 0, XATTR_NOFOLLOW)
            }
            return read > 0 ? data.prefix(read) : nil
        }
    }
}
