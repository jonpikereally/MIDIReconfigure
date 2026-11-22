import AppKit
import MIDIRouting
import SwiftUI

enum WorkspaceSection: String, CaseIterable {
    case routing = "Routing"
    case functions = "Functions"
    case activity = "Activity"
    case errors = "Errors"

    var icon: String {
        switch self {
        case .routing: "arrow.triangle.branch"
        case .functions: "bolt.circle"
        case .activity: "waveform"
        case .errors: "exclamationmark.circle"
        }
    }
}

let brandTint = Color(nsColor: NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(red: 0.65, green: 0.59, blue: 1, alpha: 1)
    }
    return NSColor(red: 0.34, green: 0.28, blue: 0.76, alpha: 1)
})

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    let openWorkspace: (WorkspaceSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                AppMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MIDI Reconfigure")
                        .font(.headline)
                    OutputStatus(model: model)
                }
                Spacer(minLength: 8)
            }

            Divider()

            Toggle("Route MIDI", isOn: routingBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!model.outputReady)

            HStack(spacing: 7) {
                Label(inputCount, systemImage: "cable.connector")
                Spacer(minLength: 3)
                Label(ruleCount, systemImage: "line.3.horizontal.decrease")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = model.errors.last {
                Button {
                    openWorkspace(.errors)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Label(error.code, systemImage: "exclamationmark.circle")
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                        Text(error.message)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("\(error.message) \(AppModel.errorHelp)")
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    openWorkspace(.routing)
                } label: {
                    Label("Routing", systemImage: WorkspaceSection.routing.icon)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    openWorkspace(.activity)
                } label: {
                    Label("Activity", systemImage: WorkspaceSection.activity.icon)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Function library…") { openWorkspace(.functions) }
                    Button("Errors…") { openWorkspace(.errors) }
                    Divider()
                    Button("Quit MIDI Reconfigure") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More actions")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 324)
        .tint(brandTint)
    }

    private var routingBinding: Binding<Bool> {
        Binding(get: { !model.isPaused }, set: { model.isPaused = !$0 })
    }

    private var inputCount: String {
        let count = model.sources.filter { model.enabledSourceIDs.contains($0.id) }.count
        return count == 1 ? "1 input enabled" : "\(count) inputs enabled"
    }

    private var ruleCount: String {
        let rules = model.rules.filter(\.isEnabled).count
        let functions = model.functionMappings.filter { $0.isEnabled && $0.trigger != nil }.count
        let ruleText = rules == 1 ? "1 rule" : "\(rules) rules"
        let functionText = functions == 1 ? "1 function" : "\(functions) functions"
        return "\(ruleText) · \(functionText)"
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @Binding var selection: WorkspaceSection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch selection {
            case .routing: RoutingView(model: model)
            case .functions: FunctionsView(model: model)
            case .activity: ActivityView(model: model)
            case .errors: ErrorsView(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, idealWidth: 850, minHeight: 450, idealHeight: 570)
        .tint(brandTint)
    }

    private var header: some View {
        HStack(spacing: 13) {
            AppMark(size: 35)
            Text("MIDI Reconfigure")
                .font(.system(size: 15, weight: .semibold))
                .fixedSize()

            Spacer(minLength: 12)
            Picker("Workspace", selection: $selection) {
                ForEach(WorkspaceSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 344)

            Spacer(minLength: 12)
            OutputStatus(model: model)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}

private struct AppMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(.linearGradient(
                        colors: [Color(red: 0.48, green: 0.39, blue: 0.92), brandTint],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            .accessibilityHidden(true)
    }
}

private struct OutputStatus: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(statusHelp)
    }

    private var statusTitle: String {
        if !model.outputReady { return model.errors.last?.code ?? "Starting MIDI" }
        return model.isPaused ? "Routing paused" : "Output available"
    }

    private var statusColor: Color {
        if !model.outputReady { return model.errors.isEmpty ? .secondary : .orange }
        return model.isPaused ? .secondary : .green
    }

    private var statusHelp: String {
        if !model.outputReady, let error = model.errors.last {
            return "\(error.message) \(AppModel.errorHelp)"
        }
        return model.outputReady ? "Choose MIDI Reconfigure as the MIDI input in your DAW." : "Waiting for Core MIDI."
    }
}

private enum RoutingSheet: Identifiable {
    case rule(MIDIRule)
    case mapping(MIDIFunctionMapping, learn: Bool)
    case function(MIDIOutputFunction)

    var id: String {
        switch self {
        case let .rule(rule): "rule-\(rule.id)"
        case let .mapping(mapping, _): "mapping-\(mapping.id)"
        case let .function(function): "function-\(function.id)"
        }
    }
}

private struct RoutingView: View {
    @ObservedObject var model: AppModel
    @State private var sheet: RoutingSheet?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 242)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    functionsSection
                    Divider().padding(.horizontal, 20).padding(.vertical, 6)
                    rulesSection
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $sheet, onDismiss: { model.cancelLearning() }) { sheet in
            Group {
                switch sheet {
                case let .rule(rule):
                    RuleEditor(rule: rule, isNew: !model.rules.contains { $0.id == rule.id }, model: model)
                case let .mapping(mapping, learn):
                    MappingEditor(mapping: mapping, startLearning: learn, model: model)
                case let .function(function):
                    FunctionEditor(function: function, isNew: false, model: model)
                }
            }
            .tint(brandTint)
        }
    }

    private var functionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Functions").font(.title2.weight(.semibold))
                    Text("Mapped inputs send a saved function and skip the rules below.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                LoadFunctionMenu(model: model) { functionID in
                    sheet = .mapping(model.loadFunction(functionID), learn: true)
                }
            }
            .padding(20)

            if model.functionMappings.isEmpty {
                Text("Load a function from the library, such as AbleSet Play or the Quad Cortex tuner, then map a button or pedal to it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(Array(model.functionMappings.enumerated()), id: \.element.id) { index, mapping in
                        mappingRow(mapping, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rules").font(.title2.weight(.semibold))
                    Text("The first enabled rule that matches takes priority.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button {
                    sheet = .rule(MIDIRule())
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            if model.rules.isEmpty {
                EmptyPanel(
                    symbol: WorkspaceSection.routing.icon,
                    title: "No routing rules yet",
                    detail: "Add a rule to remap a note, change channels, or reverse a CC control."
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(Array(model.rules.enumerated()), id: \.element.id) { index, rule in
                        ruleRow(rule, index: index)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func mappingRow(_ mapping: MIDIFunctionMapping, index: Int) -> some View {
        let function = model.function(id: mapping.functionID)
        return HStack(spacing: 12) {
            Toggle(
                "Enable function",
                isOn: Binding(
                    get: { mapping.isEnabled },
                    set: { model.setMappingEnabled(mapping.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help(mapping.isEnabled ? "Disable function" : "Enable function")
            .disabled(function == nil)

            Button {
                if function != nil { sheet = .mapping(mapping, learn: false) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let function {
                        HStack(spacing: 6) {
                            Text(function.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            if function.needsVerification { VerifyBadge() }
                        }
                        Text("\(triggerSummary(mapping.trigger, model: model)) → \(outputSummary(function.output)) · \(model.destinationName(for: function))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if mapping.trigger == nil {
                            Text("Not mapped yet. Click to map an input.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(brandTint)
                        }
                        if model.isDestinationOffline(function) {
                            ErrorText(code: "MIDI-108", message: "Destination offline")
                        }
                    } else {
                        ErrorText(code: "FUNC-003", message: "This function is no longer in the library.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(function == nil ? AppModel.errorHelp : "Map input")

            if let function {
                Button {
                    model.testFunction(function)
                } label: {
                    Image(systemName: "play.circle")
                        .accessibilityLabel("Send \(function.name) now")
                }
                .buttonStyle(.borderless)
                .disabled(!model.outputReady)
                .help("Send this function’s output now")
            }

            Menu {
                if let function {
                    Button("Map input…") { sheet = .mapping(mapping, learn: false) }
                    Button("Map with MIDI Learn") { sheet = .mapping(mapping, learn: true) }
                        .disabled(!model.canLearn)
                    Button("Edit function output…") { sheet = .function(function) }
                    Divider()
                }
                Button("Move up") { model.moveMapping(mapping.id, by: -1) }
                    .disabled(index == 0)
                Button("Move down") { model.moveMapping(mapping.id, by: 1) }
                    .disabled(index == model.functionMappings.count - 1)
                Divider()
                Button("Remove from routing", role: .destructive) { model.deleteMapping(mapping.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Function actions")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(brandTint.opacity(0.35))
                .allowsHitTesting(false)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Inputs").font(.headline)
                Spacer()
                Button {
                    model.refreshSources()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityLabel("Refresh MIDI inputs")
                }
                .buttonStyle(.borderless)
                .help("Refresh MIDI inputs")
            }

            if model.sources.isEmpty {
                Text("Connect a MIDI device or start an app that provides a MIDI source.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.sources) { source in
                            Toggle(
                                isOn: Binding(
                                    get: { model.enabledSourceIDs.contains(source.id) },
                                    set: { model.setSourceEnabled(source.id, enabled: $0) }
                                )
                            ) {
                                Text(source.name).lineLimit(2)
                            }
                            .toggleStyle(.checkbox)
                            .help(source.name)
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text("DAW output").font(.headline)
                Label(AppModel.outputName, systemImage: "arrow.up.right.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Default channel", selection: $model.defaultOutputChannel) {
                    Text("Keep input").tag(nil as Int?)
                    ForEach(1...16, id: \.self) { channel in
                        Text("\(channel)").tag(Optional(channel))
                    }
                }
                .font(.callout)
                .help("Applies to channel messages unless a rule sets an output channel.")
                Toggle(
                    "Route MIDI",
                    isOn: Binding(get: { !model.isPaused }, set: { model.isPaused = !$0 })
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!model.outputReady)
            }
        }
        .padding(18)
    }

    private func ruleRow(_ rule: MIDIRule, index: Int) -> some View {
        HStack(spacing: 12) {
            Toggle(
                "Enable \(rule.type.title) rule",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { model.setRuleEnabled(rule.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help(rule.isEnabled ? "Disable rule" : "Enable rule")

            Button {
                sheet = .rule(rule)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ruleTitle(rule))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(ruleDetail(rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit rule")

            Menu {
                Button("Edit…") { sheet = .rule(rule) }
                Divider()
                Button("Move up") { model.moveRule(rule.id, by: -1) }
                    .disabled(index == 0)
                Button("Move down") { model.moveRule(rule.id, by: 1) }
                    .disabled(index == model.rules.count - 1)
                Divider()
                Button("Delete", role: .destructive) { model.deleteRule(rule.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Rule actions")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
    }

    private func ruleTitle(_ rule: MIDIRule) -> String {
        let input = [rule.type.title, rule.inputNumber.map(String.init)].compactMap { $0 }.joined(separator: " ")
        let actions: [String] = [
            rule.outputChannel.map { "Ch \($0)" },
            rule.outputNumber.map { "\(rule.type.title) \($0)" },
            rule.invertCC ? "Invert value" : nil
        ].compactMap { $0 }
        let output = rule.drop ? "Drop" : actions.isEmpty ? "Default output" : actions.joined(separator: " · ")
        return "\(input) → \(output)"
    }

    private func ruleDetail(_ rule: MIDIRule) -> String {
        let device = rule.deviceID.map { id in
            model.sources.first(where: { $0.id == id })?.name ?? "Offline input"
        } ?? "Any input"
        let channel = rule.inputChannel.map { "Channel \($0)" } ?? "Any channel"
        return "\(device) · \(channel)"
    }
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: MIDIRule
    @State private var inputNumber: String
    @State private var outputNumber: String
    let isNew: Bool

    init(rule: MIDIRule, isNew: Bool, model: AppModel) {
        self.model = model
        _draft = State(initialValue: rule)
        _inputNumber = State(initialValue: rule.inputNumber.map(String.init) ?? "")
        _outputNumber = State(initialValue: rule.outputNumber.map(String.init) ?? "")
        self.isNew = isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(isNew ? "Add routing rule" : "Edit routing rule")
                    .font(.title2.weight(.semibold))
                Spacer()
                learnButton
            }
            if model.isLearning {
                Label("Play a note, turn a MIDI control, or send a Program Change.", systemImage: "waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    formLabel("Match")
                    Picker("Input", selection: $draft.deviceID) {
                        Text("Any input").tag(nil as String?)
                        if let deviceID = draft.deviceID, !model.sources.contains(where: { $0.id == deviceID }) {
                            Text("Saved input (offline)").tag(Optional(deviceID))
                        }
                        ForEach(model.sources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    formLabel("Input channel")
                    channelPicker("Input channel", emptyTitle: "Any channel", value: $draft.inputChannel)
                }
                GridRow {
                    formLabel("Message type")
                    Picker("Message type", selection: Binding(get: { draft.type }, set: setMessageType)) {
                        ForEach(MIDIMessageType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                if draft.type.supportsNumber {
                    GridRow {
                        formLabel(numberLabel)
                        TextField("Any number", text: $inputNumber, prompt: Text("Any number"))
                            .accessibilityLabel("Input \(numberLabel.lowercased())")
                    }
                }
                Divider().gridCellColumns(2)
                GridRow {
                    formLabel("Action")
                    Picker("Action", selection: $draft.drop) {
                        Text("Send to DAW").tag(false)
                        Text("Drop message").tag(true)
                    }
                    .labelsHidden()
                }
                if !draft.drop {
                    GridRow {
                        formLabel("Output channel")
                        channelPicker("Output channel", emptyTitle: "Use default", value: $draft.outputChannel)
                    }
                    if draft.type.supportsNumber {
                        GridRow {
                            formLabel("New number")
                            TextField("Keep number", text: $outputNumber, prompt: Text("Keep number"))
                                .accessibilityLabel("Output \(numberLabel.lowercased())")
                        }
                    }
                    if draft.type == .controlChange {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Toggle("Invert CC value (127 − value)", isOn: $draft.invertCC)
                        }
                    }
                }
            }

            if let validationMessage {
                Label("RULE-001 · \(validationMessage)", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .help(AppModel.errorHelp)
            } else if draft.type.supportsNumber {
                Text("MIDI numbers run from 0 to 127.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.cancelLearning()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLearning || validationMessage != nil)
            }
        }
        .padding(22)
        .frame(width: 434)
    }

    private var learnButton: some View {
        HStack(spacing: 0) {
            Button {
                if model.isLearning {
                    model.cancelLearning()
                } else {
                    model.beginLearning(onLearn: applyLearnedInput)
                }
            } label: {
                Label(
                    model.isLearning ? "Cancel Learn" : "MIDI Learn",
                    systemImage: model.isLearning ? "xmark.circle" : "dot.radiowaves.left.and.right"
                )
            }
            .disabled(!model.isLearning && !model.canLearn)
        }
        .contentShape(Rectangle())
        .help(learningHelp)
    }

    private var learningHelp: String {
        if model.isLearning { return "Stop listening for MIDI." }
        if !model.outputReady { return "Wait for Core MIDI to connect before using MIDI Learn." }
        if model.canLearn { return "Fill the match fields from the next MIDI message." }
        return "Enable a connected MIDI input in Routing to use MIDI Learn."
    }

    private func setMessageType(_ type: MIDIMessageType) {
        guard draft.type != type else { return }
        if !type.supportsNumber {
            inputNumber = ""
            outputNumber = ""
        }
        if type != .controlChange { draft.invertCC = false }
        draft.type = type
    }

    private func applyLearnedInput(_ input: MIDILearnedInput) {
        let noteTypes: [MIDIMessageType] = [.note, .polyphonicPressure]
        if draft.type != input.type, !(noteTypes.contains(draft.type) && noteTypes.contains(input.type)) {
            outputNumber = ""
        }
        setMessageType(input.type)
        draft.deviceID = input.deviceID
        draft.inputChannel = input.channel
        inputNumber = input.number.map(String.init) ?? ""
    }

    private var validationMessage: String? {
        if draft.type.supportsNumber && !isValidNumber(inputNumber) {
            return "Enter an input number from 0 to 127."
        }
        if !draft.drop && draft.type.supportsNumber && !isValidNumber(outputNumber) {
            return "Enter an output number from 0 to 127."
        }
        return nil
    }

    private var numberLabel: String {
        switch draft.type {
        case .note, .polyphonicPressure: "Note number"
        case .controlChange: "CC number"
        case .programChange: "Program number"
        default: "Number"
        }
    }

    private func formLabel(_ label: String) -> some View {
        Text(label).font(.callout.weight(.medium)).padding(.top, 4)
    }

    private func channelPicker(_ label: String, emptyTitle: String, value: Binding<Int?>) -> some View {
        Picker(label, selection: value) {
            Text(emptyTitle).tag(nil as Int?)
            ForEach(1...16, id: \.self) { channel in
                Text("Channel \(channel)").tag(Optional(channel))
            }
        }
        .labelsHidden()
    }

    private func isValidNumber(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty { return true }
        return Int(trimmedValue).map((0...127).contains) ?? false
    }

    private func save() {
        guard validationMessage == nil else { return }
        draft.inputNumber = draft.type.supportsNumber ? Int(inputNumber.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        draft.outputNumber = !draft.drop && draft.type.supportsNumber ? Int(outputNumber.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        if draft.drop {
            draft.outputChannel = nil
            draft.invertCC = false
        }
        model.saveRule(draft)
        dismiss()
    }
}

private struct ActivityView: View {
    private enum DirectionFilter: String, CaseIterable {
        case all = "Both"
        case incoming = "In"
        case outgoing = "Out"

        func includes(_ event: MIDIActivity) -> Bool {
            switch self {
            case .all: true
            case .incoming: event.direction == .incoming
            case .outgoing: event.direction == .outgoing
            }
        }
    }

    private enum ActivityOrder: String, CaseIterable {
        case latest = "Newest first"
        case device = "Device"
        case type = "Message type"

        func compare(_ lhs: MIDIActivity, _ rhs: MIDIActivity) -> Bool {
            let result: ComparisonResult
            switch self {
            case .latest: result = .orderedSame
            case .device: result = lhs.deviceName.localizedStandardCompare(rhs.deviceName)
            case .type: result = lhs.type.localizedStandardCompare(rhs.type)
            }
            if result == .orderedSame { return lhs.timestamp > rhs.timestamp }
            return result == .orderedAscending
        }
    }

    @ObservedObject var model: AppModel
    @AppStorage("midiActivityDirection") private var direction = DirectionFilter.all
    @AppStorage("midiActivitySort") private var order = ActivityOrder.latest

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        let events = model.activity.reversed().filter(direction.includes).sorted(by: order.compare)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("MIDI activity").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.isMonitorPaused.toggle()
                } label: {
                    Label(
                        model.isMonitorPaused ? "Resume capture" : "Pause capture",
                        systemImage: model.isMonitorPaused ? "play.fill" : "pause.fill"
                    )
                }
                .help("Pause or resume adding messages to the monitor.")
                Button {
                    model.clearActivity()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.activity.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack(spacing: 10) {
                Picker("Direction", selection: $direction) {
                    ForEach(DirectionFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                Spacer()
                if model.isMonitorPaused {
                    Text("Capture paused")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Picker("Sort by", selection: $order) {
                    ForEach(ActivityOrder.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()
            activityTable(events)
                .overlay {
                    if events.isEmpty {
                        EmptyPanel(
                            symbol: "waveform",
                            title: model.activity.isEmpty ? "Waiting for MIDI" : "No matching messages",
                            detail: model.activity.isEmpty
                                ? "Messages appear here when an enabled input sends MIDI."
                                : "Select Both to show incoming and outgoing messages together."
                        )
                        .padding(.top, 27)
                        .allowsHitTesting(false)
                    }
                }
        }
    }

    private func activityTable(_ events: [MIDIActivity]) -> some View {
        Table(events) {
            TableColumn("Time") { event in
                Text(Self.timeFormat.string(from: event.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(86)
            TableColumn("Direction") { event in
                let incoming = event.direction == .incoming
                Label(incoming ? "In" : "Out", systemImage: incoming ? "arrow.down.left" : "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(incoming ? Color.teal : brandTint)
                    .accessibilityLabel(incoming ? "Incoming" : "Outgoing")
            }
            .width(63)
            TableColumn("Input device") { event in
                Text(event.deviceName)
                    .lineLimit(1)
                    .help(event.deviceName)
            }
            .width(min: 106, ideal: 156)
            TableColumn("Type") { event in
                Text(event.type).lineLimit(1).help(event.type)
            }
            .width(min: 92, ideal: 123)
            TableColumn("Ch") { event in
                Text(event.channel.map(String.init) ?? "—")
                    .monospacedDigit()
            }
            .width(36)
            TableColumn("Data") { event in
                Text(event.detail)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .help(event.detail)
            }
            .width(min: 130, ideal: 228)
        }
    }
}

private struct ErrorsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Error list").font(.title2.weight(.semibold))
                Spacer()
                Button("Restart MIDI") { model.retryMIDI() }
                    .help("Restart the Core MIDI connection and reconnect enabled inputs.")
                if !model.errors.isEmpty {
                    Button("Clear history") { model.clearErrors() }
                }
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent errors").font(.headline)
                        if model.errors.isEmpty {
                            Label("No errors recorded", systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.errors.reversed()) { error in
                            errorRow(code: error.code, description: error.message, isRecent: true)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Error codes").font(.headline)
                        ForEach(AppModel.errorCatalog, id: \.code) { entry in
                            errorRow(code: entry.code, description: entry.description, isRecent: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            Divider()
            Text(AppModel.buildDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
    }

    private func errorRow(code: String, description: String, isRecent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(code)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(isRecent ? Color.orange : Color.secondary)
                .frame(width: 74, alignment: .leading)
            Text(description)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .help(AppModel.errorHelp)
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(brandTint)
                .frame(width: 52, height: 52)
                .background(brandTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
    }
}
