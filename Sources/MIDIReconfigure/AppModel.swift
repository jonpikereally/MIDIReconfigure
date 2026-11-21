import Foundation
import MIDIRouting
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let outputName = MIDITransport.outputName
    static let errorHelp = "Check the Errors page for this error code."
    static let errorCatalog: [(code: String, description: String)] = [
        ("MIDI-101", "CoreMIDI could not start. Try Restart MIDI. If it persists, restart macOS."),
        ("MIDI-102", "The virtual output could not be created. Try Restart MIDI, then look for MIDI Reconfigure in your DAW again."),
        ("MIDI-103", "The MIDI input port could not be created. Try Restart MIDI."),
        ("MIDI-104", "The selected input could not be connected. Reconnect the device and click Refresh Inputs."),
        ("MIDI-105", "An event could not be sent to the virtual output. Try Restart MIDI and reselect the port in your DAW."),
        ("MIDI-106", "The virtual output's persistent identity could not be assigned. If your DAW lost its selection, reselect MIDI Reconfigure."),
        ("MIDI-201", "Saved routing settings could not be read. The app loaded defaults. Changing a routing setting saves a new configuration."),
        ("MIDI-202", "Changes could not be saved. Try again before quitting the app."),
        ("RULE-001", "A rule’s input or output number must be a whole number from 0 to 127.")
    ]

    static var buildDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Dev"
        let build = info["CFBundleVersion"] as? String ?? "local"
        guard let date = info["MRCBuildDate"] as? String else { return "\(version) · Build \(build)" }
        return "\(version) · Build \(build) · \(date)"
    }

    @Published private(set) var sources: [MIDIInputSource] = []
    @Published private(set) var enabledSourceIDs: Set<String> = []
    @Published private(set) var rules: [MIDIRule] = []
    @Published private(set) var activity: [MIDIActivity] = []
    @Published private(set) var errors: [MIDITransportError] = []
    @Published private(set) var outputReady = false
    @Published private var learningRequestID: UUID?
    @Published var isMonitorPaused = false
    @Published var workspaceSection: WorkspaceSection = .routing

    @Published var defaultOutputChannel: Int? {
        didSet { if oldValue != defaultOutputChannel { settingsDidChange() } }
    }

    @Published var isPaused = false {
        didSet { if oldValue != isPaused { settingsDidChange() } }
    }

    var isLearning: Bool { learningRequestID != nil }

    var canLearn: Bool {
        outputReady && sources.contains { enabledSourceIDs.contains($0.id) }
    }

    private let defaults: UserDefaults
    private let settingsKey = "routing-settings-v1"
    private let activityLimit = 600
    private var isLoading = true

    private lazy var transport = MIDITransport(
        defaults: defaults,
        onSources: { [weak self] in self?.sources = $0 },
        onActivity: { [weak self] in self?.receiveActivity($0) },
        onStatus: { [weak self] in self?.outputReady = $0 },
        onError: { [weak self] in self?.recordError($0) }
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defer { isLoading = false }
        guard let data = defaults.data(forKey: settingsKey) else { return }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            enabledSourceIDs = settings.enabledSourceIDs
            defaultOutputChannel = settings.defaultOutputChannel
            isPaused = settings.isPaused
            rules = settings.rules
        } catch {
            recordError(MIDITransportError(code: "MIDI-201", message: "Could not read saved routing settings. Using defaults."))
        }
    }

    func start() {
        configureTransport()
        transport.start()
    }

    func stop() {
        cancelLearning()
        transport.stop()
    }

    func retryMIDI() {
        cancelLearning()
        outputReady = false
        transport.restart()
    }

    func refreshSources() {
        transport.refreshSources()
    }

    func setSourceEnabled(_ id: String, enabled: Bool) {
        if enabled {
            guard enabledSourceIDs.insert(id).inserted else { return }
        } else {
            guard enabledSourceIDs.remove(id) != nil else { return }
        }
        settingsDidChange()
    }

    func beginLearning(onLearn: @escaping (MIDILearnedInput) -> Void) {
        guard canLearn, learningRequestID == nil else { return }
        let requestID = UUID()
        learningRequestID = requestID
        transport.armLearn(requestID) { [weak self] completedID, input in
            guard let self, self.learningRequestID == completedID else { return }
            self.learningRequestID = nil
            onLearn(input)
        }
    }

    func cancelLearning() {
        guard learningRequestID != nil else { return }
        learningRequestID = nil
        transport.cancelLearn()
    }

    func saveRule(_ rule: MIDIRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        settingsDidChange()
    }

    func deleteRule(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules.remove(at: index)
        settingsDidChange()
    }

    func moveRule(_ id: UUID, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == id }),
              rules.indices.contains(index + offset) else { return }
        let rule = rules.remove(at: index)
        rules.insert(rule, at: index + offset)
        settingsDidChange()
    }

    func setRuleEnabled(_ id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        settingsDidChange()
    }

    func clearActivity() {
        activity.removeAll(keepingCapacity: true)
    }

    func clearErrors() {
        errors.removeAll(keepingCapacity: true)
    }

    private func configureTransport() {
        transport.configure(enabledSourceIDs: enabledSourceIDs, rules: rules,
                            defaultOutputChannel: defaultOutputChannel, isPaused: isPaused)
    }

    private func settingsDidChange() {
        guard !isLoading else { return }
        configureTransport()
        let settings = Settings(enabledSourceIDs: enabledSourceIDs, defaultOutputChannel: defaultOutputChannel,
                                isPaused: isPaused, rules: rules)
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
        } catch {
            recordError(MIDITransportError(code: "MIDI-202", message: "Could not save routing changes."))
        }
    }

    private func receiveActivity(_ events: [MIDIActivity]) {
        guard !isMonitorPaused, !events.isEmpty else { return }
        activity = Array((activity + events).suffix(activityLimit))
    }

    private func recordError(_ error: MIDITransportError) {
        guard !errors.contains(where: { $0.code == error.code && $0.message == error.message }) else { return }
        errors = Array((errors + [error]).suffix(30))
    }

    private struct Settings: Codable {
        var enabledSourceIDs: Set<String>
        var defaultOutputChannel: Int?
        var isPaused: Bool
        var rules: [MIDIRule]
    }
}
