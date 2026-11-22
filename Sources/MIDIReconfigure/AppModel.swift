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
        ("MIDI-107", "The hardware MIDI output port could not be created, so functions can only use the virtual port. Try Restart MIDI."),
        ("MIDI-108", "A function’s hardware destination is offline. Reconnect the device, or edit the function and choose another destination."),
        ("MIDI-109", "A message could not be sent to a hardware destination. Reconnect the device and try Restart MIDI."),
        ("MIDI-201", "Saved routing settings could not be read. The app loaded defaults. Changing a routing setting saves a new configuration."),
        ("MIDI-202", "Changes could not be saved. Try again before quitting the app."),
        ("MIDI-203", "The function library could not be read. The starter library was loaded and the unreadable copy was kept as a backup."),
        ("MIDI-204", "Function library changes could not be saved. Try again before quitting the app."),
        ("RULE-001", "A rule’s input or output number must be a whole number from 0 to 127."),
        ("FUNC-001", "A function’s number must be 0–127, its value 0–127 (velocity 1–127), and its channel 1–16."),
        ("FUNC-002", "A function mapping’s input number must be a whole number from 0 to 127."),
        ("FUNC-003", "A loaded function is no longer in the library. Remove it from Routing or load it again from the library."),
        ("UPD-001", "Updates couldn’t be checked. Check your internet connection, then click Check for Updates in Settings."),
        ("UPD-002", "No published release was found. Download releases from the project’s GitHub Releases page."),
        ("UPD-003", "The update couldn’t be downloaded or unpacked. Try again, or download it from GitHub Releases."),
        ("UPD-004", "The update couldn’t be installed. Move MIDI Reconfigure.app to a folder you can edit, such as Applications, and try again."),
        ("UPD-005", "Updates install only into a packaged MIDI Reconfigure.app. Build the app with scripts/build-app.sh."),
        ("APP-001", "The Dock icon and menu bar icon can’t both be hidden. One stays on so you can reach the app.")
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
    @Published private(set) var functions: [MIDIOutputFunction] = []
    @Published private(set) var functionMappings: [MIDIFunctionMapping] = []
    @Published private(set) var destinations: [MIDIOutputDestination] = []
    @Published private(set) var activity: [MIDIActivity] = []
    @Published private(set) var errors: [MIDITransportError] = []
    @Published private(set) var outputReady = false
    @Published private var learningRequestID: UUID?
    @Published var isMonitorPaused = false
    @Published private(set) var visibilityNotice: String?

    /// Shows the app in the Dock with a main menu. At least one of Dock or menu bar stays on.
    @Published var showInDock: Bool {
        didSet {
            guard oldValue != showInDock else { return }
            defaults.set(showInDock, forKey: Self.showInDockKey)
            if !showInDock && !showInMenuBar {
                showInMenuBar = true
                visibilityNotice = "APP-001"
            } else {
                visibilityNotice = nil
            }
        }
    }

    @Published var showInMenuBar: Bool {
        didSet {
            guard oldValue != showInMenuBar else { return }
            defaults.set(showInMenuBar, forKey: Self.showInMenuBarKey)
            if !showInMenuBar && !showInDock {
                showInDock = true
                visibilityNotice = "APP-001"
            } else {
                visibilityNotice = nil
            }
        }
    }

    let updater: Updater
    private static let showInDockKey = "show-in-dock"
    private static let showInMenuBarKey = "show-in-menu-bar"
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
    private let libraryKey = "function-library-v1"
    private let activityLimit = 600
    private var isLoading = true

    private lazy var transport = MIDITransport(
        defaults: defaults,
        onSources: { [weak self] in self?.sources = $0 },
        onDestinations: { [weak self] in self?.destinations = $0 },
        onActivity: { [weak self] in self?.receiveActivity($0) },
        onStatus: { [weak self] in self?.outputReady = $0 },
        onError: { [weak self] in self?.recordError($0) }
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.showInDockKey: true, Self.showInMenuBarKey: true])
        let dock = defaults.bool(forKey: Self.showInDockKey)
        showInDock = dock
        showInMenuBar = dock ? defaults.bool(forKey: Self.showInMenuBarKey) : true
        updater = Updater(defaults: defaults)
        defer { isLoading = false }
        updater.onError = { [weak self] code, message in
            self?.recordError(MIDITransportError(code: code, message: message))
        }
        loadLibrary()
        guard let data = defaults.data(forKey: settingsKey) else { return }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            enabledSourceIDs = settings.enabledSourceIDs
            defaultOutputChannel = settings.defaultOutputChannel
            isPaused = settings.isPaused
            rules = settings.rules
            functionMappings = settings.functionMappings ?? []
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

    // MARK: Function library

    func function(id: UUID) -> MIDIOutputFunction? {
        functions.first { $0.id == id }
    }

    func mappingCount(for functionID: UUID) -> Int {
        functionMappings.filter { $0.functionID == functionID }.count
    }

    func destinationName(for function: MIDIOutputFunction) -> String {
        guard let id = function.destinationID else { return Self.outputName }
        return destinations.first(where: { $0.id == id })?.name ?? "\(function.destinationName ?? "Saved destination") (offline)"
    }

    func isDestinationOffline(_ function: MIDIOutputFunction) -> Bool {
        guard let id = function.destinationID else { return false }
        return !destinations.contains { $0.id == id }
    }

    func saveFunction(_ function: MIDIOutputFunction) {
        var function = function
        if let id = function.destinationID, let destination = destinations.first(where: { $0.id == id }) {
            function.destinationName = destination.name
        } else if function.destinationID == nil {
            function.destinationName = nil
        }
        if let index = functions.firstIndex(where: { $0.id == function.id }) {
            functions[index] = function
        } else {
            functions.append(function)
        }
        libraryDidChange()
    }

    func duplicateFunction(_ id: UUID) {
        guard var copy = function(id: id) else { return }
        copy.id = UUID()
        copy.name += " copy"
        functions.append(copy)
        libraryDidChange()
    }

    /// Removes a function from the library and from the routing configuration.
    func deleteFunction(_ id: UUID) {
        functions.removeAll { $0.id == id }
        libraryDidChange()
        let before = functionMappings.count
        functionMappings.removeAll { $0.functionID == id }
        if functionMappings.count != before { settingsDidChange() }
    }

    func restoreStarterFunctions() {
        let names = Set(functions.map(\.name))
        let missing = MIDIOutputFunction.starterLibrary.filter { !names.contains($0.name) }.map { starter in
            var copy = starter
            copy.id = UUID()
            return copy
        }
        guard !missing.isEmpty else { return }
        functions += missing
        libraryDidChange()
    }

    func testFunction(_ function: MIDIOutputFunction) {
        transport.sendTest(function)
    }

    // MARK: Loaded functions

    /// Adds a library function to the routing configuration and returns the new, unmapped entry.
    @discardableResult
    func loadFunction(_ functionID: UUID) -> MIDIFunctionMapping {
        let mapping = MIDIFunctionMapping(functionID: functionID)
        functionMappings.append(mapping)
        settingsDidChange()
        return mapping
    }

    func saveMapping(_ mapping: MIDIFunctionMapping) {
        if let index = functionMappings.firstIndex(where: { $0.id == mapping.id }) {
            functionMappings[index] = mapping
        } else {
            functionMappings.append(mapping)
        }
        settingsDidChange()
    }

    func deleteMapping(_ id: UUID) {
        guard let index = functionMappings.firstIndex(where: { $0.id == id }) else { return }
        functionMappings.remove(at: index)
        settingsDidChange()
    }

    func moveMapping(_ id: UUID, by offset: Int) {
        guard let index = functionMappings.firstIndex(where: { $0.id == id }),
              functionMappings.indices.contains(index + offset) else { return }
        let mapping = functionMappings.remove(at: index)
        functionMappings.insert(mapping, at: index + offset)
        settingsDidChange()
    }

    func setMappingEnabled(_ id: UUID, enabled: Bool) {
        guard let index = functionMappings.firstIndex(where: { $0.id == id }) else { return }
        functionMappings[index].isEnabled = enabled
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
                            defaultOutputChannel: defaultOutputChannel, isPaused: isPaused,
                            functions: functions, functionMappings: functionMappings)
    }

    private func settingsDidChange() {
        guard !isLoading else { return }
        configureTransport()
        let settings = Settings(enabledSourceIDs: enabledSourceIDs, defaultOutputChannel: defaultOutputChannel,
                                isPaused: isPaused, rules: rules, functionMappings: functionMappings)
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
        } catch {
            recordError(MIDITransportError(code: "MIDI-202", message: "Could not save routing changes."))
        }
    }

    private func loadLibrary() {
        guard let data = defaults.data(forKey: libraryKey) else {
            // Save the starter library right away so its IDs stay stable for loaded mappings.
            functions = MIDIOutputFunction.starterLibrary
            persistLibrary()
            return
        }
        do {
            functions = try JSONDecoder().decode([MIDIOutputFunction].self, from: data)
        } catch {
            // Keep the unreadable library so a later save can't destroy it.
            defaults.set(data, forKey: "\(libraryKey).unreadable")
            functions = MIDIOutputFunction.starterLibrary
            persistLibrary()
            recordError(MIDITransportError(code: "MIDI-203", message: "Could not read the function library. Loaded the starter library."))
        }
    }

    private func libraryDidChange() {
        guard !isLoading else { return }
        configureTransport()
        persistLibrary()
    }

    private func persistLibrary() {
        do {
            defaults.set(try JSONEncoder().encode(functions), forKey: libraryKey)
        } catch {
            recordError(MIDITransportError(code: "MIDI-204", message: "Could not save function library changes."))
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
        /// Optional so settings saved before functions existed still decode.
        var functionMappings: [MIDIFunctionMapping]?
    }
}
