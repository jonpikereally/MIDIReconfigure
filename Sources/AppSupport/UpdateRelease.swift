import Foundation

/// A dotted numeric version such as 1.3.0. A leading "v" and any "-beta" or "+build" suffix are ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let end = text.firstIndex(where: { $0 == "-" || $0 == "+" }) { text = String(text[..<end]) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The parts of a GitHub release the updater uses.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    public let notes: String
    public let pageURL: URL?
    /// Nil when the release has no app ZIP attached.
    public let downloadURL: URL?

    public static let assetName = "MIDI-Reconfigure.zip"

    public static func == (lhs: ReleaseInfo, rhs: ReleaseInfo) -> Bool {
        lhs.tag == rhs.tag && lhs.downloadURL == rhs.downloadURL
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL?
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    /// Parses the GitHub "latest release" response. Returns nil for drafts, prereleases, and tags that aren't versions.
    public static func parse(_ data: Data) throws -> ReleaseInfo? {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name) else { return nil }
        let asset = payload.assets?.first { $0.name == assetName }
            ?? payload.assets?.first { $0.name.lowercased().hasSuffix(".zip") }
        return ReleaseInfo(
            version: version,
            tag: payload.tag_name,
            notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            pageURL: payload.html_url,
            downloadURL: asset?.browser_download_url
        )
    }

    public func isNewer(than current: String) -> Bool {
        guard let current = AppVersion(current) else { return true }
        return current < version
    }
}

/// The shell script that swaps in the new app after the running copy quits, then relaunches it.
public enum UpdateInstallScript {
    public static let contents = """
    #!/bin/bash
    # Usage: install.sh <pid> <new app> <installed app>
    pid="$1"; new_app="$2"; target="$3"
    for _ in $(seq 1 300); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    backup="${target}.previous-$$"
    mv "$target" "$backup" || { open "$target"; exit 1; }
    if mv "$new_app" "$target"; then
        rm -rf "$backup"
    else
        mv "$backup" "$target"
    fi
    xattr -dr com.apple.quarantine "$target" 2>/dev/null
    open "$target"
    """
}
