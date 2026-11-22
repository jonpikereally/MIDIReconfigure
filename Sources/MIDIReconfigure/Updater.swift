import AppKit
import AppSupport
import Foundation

/// Checks GitHub Releases for a newer build and installs it in place.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo)
        case installing
        case failed(code: String, message: String)
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/jonpikereally/MIDIReconfigure/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/jonpikereally/MIDIReconfigure/releases")!
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?
    @Published var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Keys.checks) }
    }
    @Published var installsAutomatically: Bool {
        didSet { defaults.set(installsAutomatically, forKey: Keys.installs) }
    }

    var onError: ((String, String) -> Void)?

    let currentVersion: String
    /// Updates can only replace a packaged app, not a `swift run` build.
    let canInstall: Bool

    var availableRelease: ReleaseInfo? {
        if case let .available(release) = phase { return release }
        return nil
    }

    private enum Keys {
        static let checks = "updates-check-automatically"
        static let installs = "updates-install-automatically"
        static let lastChecked = "updates-last-checked"
    }

    private let defaults: UserDefaults
    private var timer: Timer?
    private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.checks: true, Keys.installs: false])
        checksAutomatically = defaults.bool(forKey: Keys.checks)
        installsAutomatically = defaults.bool(forKey: Keys.installs)
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Dev"
        canInstall = Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Runs the launch check and schedules background checks.
    func start() {
        if checksAutomatically { check(userInitiated: false, atLaunch: true) }
        let timer = Timer(timeInterval: 60 * 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.periodicCheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check(userInitiated: Bool = true, atLaunch: Bool = false) {
        guard task == nil else { return }
        phase = .checking
        task = Task { [weak self] in
            await self?.performCheck(userInitiated: userInitiated, atLaunch: atLaunch)
            self?.task = nil
        }
    }

    func installAvailableUpdate() {
        guard task == nil, let release = availableRelease else { return }
        task = Task { [weak self] in
            await self?.install(release)
            self?.task = nil
        }
    }

    private func periodicCheck() {
        guard checksAutomatically, task == nil else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        // Periodic checks never install on their own, so a running show is never restarted.
        check(userInitiated: false)
    }

    private func performCheck(userInitiated: Bool, atLaunch: Bool) async {
        var request = URLRequest(url: Self.releasesAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MIDIReconfigure-Updater", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                fail("UPD-002", "No published release was found.", report: userInitiated)
                return
            }
            guard status == 200 else {
                fail("UPD-001", "The update server answered with HTTP \(status).", report: userInitiated)
                return
            }
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Keys.lastChecked)
            guard let release = try ReleaseInfo.parse(data), release.isNewer(than: currentVersion) else {
                phase = .upToDate
                return
            }
            phase = .available(release)
            if atLaunch, installsAutomatically, canInstall, release.downloadURL != nil {
                await install(release)
            }
        } catch is DecodingError {
            fail("UPD-001", "The update information couldn’t be read.", report: userInitiated)
        } catch {
            fail("UPD-001", "Couldn’t reach the update server. Check your internet connection.", report: userInitiated)
        }
    }

    private func install(_ release: ReleaseInfo) async {
        guard canInstall else {
            fail("UPD-005", "Updates install only into a packaged MIDI Reconfigure.app.", report: true)
            return
        }
        guard let downloadURL = release.downloadURL else {
            fail("UPD-003", "Release \(release.tag) has no app download attached.", report: true)
            return
        }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            fail("UPD-004", "Can’t write to \(target.deletingLastPathComponent().path). Move the app to a folder you can edit, such as Applications.", report: true)
            return
        }

        phase = .downloading(release)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIDIReconfigureUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (download, response) = try await URLSession.shared.download(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                fail("UPD-003", "The update download failed.", report: true)
                return
            }
            let zip = work.appendingPathComponent(ReleaseInfo.assetName)
            try FileManager.default.moveItem(at: download, to: zip)
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            guard await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path]) else {
                fail("UPD-003", "The downloaded update couldn’t be unpacked.", report: true)
                return
            }
            guard let newApp = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
                  let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                fail("UPD-004", "The download doesn’t contain MIDI Reconfigure.", report: true)
                return
            }
            guard await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) else {
                fail("UPD-004", "The downloaded app failed its code signature check.", report: true)
                return
            }

            phase = .installing
            let script = work.appendingPathComponent("install.sh")
            try UpdateInstallScript.contents.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, target.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            fail("UPD-003", "The update couldn’t be downloaded or prepared.", report: true)
        }
    }

    private func fail(_ code: String, _ message: String, report: Bool) {
        phase = .failed(code: code, message: message)
        if report { onError?(code, message) }
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
