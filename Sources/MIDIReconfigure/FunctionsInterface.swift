import MIDIRouting
import SwiftUI

// MARK: Shared pieces

func outputSummary(_ output: MIDIFunctionOutput) -> String {
    let channel = "Ch \(output.channel)"
    switch output.type {
    case .programChange:
        return "PC \(output.number) · \(channel)"
    case .controlChange:
        let value = output.value.map(String.init) ?? "input value"
        return "CC \(output.number) = \(value) · \(channel)"
    case .note:
        let velocity = output.value.map { "vel \($0)" } ?? "input velocity"
        return "Note \(output.number) · \(velocity) · \(channel)"
    }
}

@MainActor
func triggerSummary(_ trigger: MIDITrigger?, model: AppModel) -> String {
    guard let trigger else { return "No input" }
    let type: String
    switch trigger.type {
    case .note: type = "Note"
    case .controlChange: type = "CC"
    case .programChange: type = "PC"
    default: type = trigger.type.title
    }
    let message = trigger.number.map { "\(type) \($0)" } ?? "Any \(type)"
    let device = trigger.deviceID.map { id in
        model.sources.first(where: { $0.id == id })?.name ?? "Offline input"
    } ?? "Any input"
    let channel = trigger.channel.map { "Ch \($0)" } ?? "any ch"
    return "\(message) · \(device) · \(channel)"
}

func groupedFunctions(_ functions: [MIDIOutputFunction]) -> [(name: String, functions: [MIDIOutputFunction])] {
    let groups = Dictionary(grouping: functions) { function -> String in
        let name = function.group.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Other" : name
    }
    return groups.keys.sorted { lhs, rhs in
        if lhs == "Other" { return false }
        if rhs == "Other" { return true }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }.map { ($0, groups[$0] ?? []) }
}

struct VerifyBadge: View {
    var body: some View {
        Text("Verify")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.14), in: Capsule())
            .help("Placeholder message. Edit the function to match your setup, then turn off Placeholder.")
    }
}

/// Error text that always carries its code and points to the Errors page.
struct ErrorText: View {
    let code: String
    let message: String

    var body: some View {
        Label("\(code) · \(message)", systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .help("\(message) \(AppModel.errorHelp)")
    }
}

struct LoadFunctionMenu: View {
    @ObservedObject var model: AppModel
    let onLoad: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(groupedFunctions(model.functions), id: \.name) { group in
                Section(group.name) {
                    ForEach(group.functions) { function in
                        Button(function.name) { onLoad(function.id) }
                    }
                }
            }
            if model.functions.isEmpty {
                Button("Library is empty") {}.disabled(true)
            }
            Divider()
            Button("Open function library…") { model.workspaceSection = .functions }
        } label: {
            Label("Load function", systemImage: "bolt.badge.plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
    }
}

private func formLabel(_ label: String) -> some View {
    Text(label).font(.callout.weight(.medium)).padding(.top, 4)
}

private func isValidMIDINumber(_ value: String, allowEmpty: Bool, range: ClosedRange<Int> = 0...127) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return allowEmpty }
    return Int(trimmed).map(range.contains) ?? false
}

private func parsedNumber(_ value: String) -> Int? {
    Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: Function library

struct FunctionsView: View {
    private struct EditRequest: Identifiable {
        let function: MIDIOutputFunction
        let isNew: Bool
        var id: UUID { function.id }
    }

    @ObservedObject var model: AppModel
    @State private var editing: EditRequest?
    @State private var pendingDelete: MIDIOutputFunction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Function library").font(.title2.weight(.semibold))
                    Text("Saved MIDI commands. Edits apply everywhere a function is loaded.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Menu {
                    Button("Restore missing starter functions") { model.restoreStarterFunctions() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Library actions")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Button {
                    editing = EditRequest(
                        function: MIDIOutputFunction(
                            name: "", output: MIDIFunctionOutput(type: .controlChange, channel: 1, number: 0, value: 127)
                        ),
                        isNew: true
                    )
                } label: {
                    Label("New function", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            if model.functions.isEmpty {
                EmptyPanel(
                    symbol: WorkspaceSection.functions.icon,
                    title: "No functions yet",
                    detail: "Create a function for a command you send often, such as starting playback or opening a tuner."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedFunctions(model.functions), id: \.name) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.name)
                                    .font(.headline)
                                ForEach(group.functions) { function in
                                    functionRow(function)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $editing) { request in
            FunctionEditor(function: request.function, isNew: request.isNew, model: model)
                .tint(brandTint)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "function")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { function in
            Button("Delete", role: .destructive) { model.deleteFunction(function.id) }
        } message: { function in
            let count = model.mappingCount(for: function.id)
            Text(count == 0
                 ? "This can’t be undone."
                 : "It’s loaded \(count == 1 ? "once" : "\(count) times") in Routing. Those entries are removed too.")
        }
    }

    private func functionRow(_ function: MIDIOutputFunction) -> some View {
        let loaded = model.mappingCount(for: function.id)
        return HStack(spacing: 12) {
            Button {
                editing = EditRequest(function: function, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(function.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if function.needsVerification { VerifyBadge() }
                    }
                    Text("\(outputSummary(function.output)) → \(model.destinationName(for: function))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if model.isDestinationOffline(function) {
                        ErrorText(code: "MIDI-108", message: "Destination offline")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit function")

            if loaded > 0 {
                Text(loaded == 1 ? "Loaded" : "Loaded ×\(loaded)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.testFunction(function)
            } label: {
                Image(systemName: "play.circle")
                    .accessibilityLabel("Send \(function.name) now")
            }
            .buttonStyle(.borderless)
            .disabled(!model.outputReady)
            .help("Send this function’s output now")

            Menu {
                Button("Edit…") { editing = EditRequest(function: function, isNew: false) }
                Button("Load into Routing") {
                    model.loadFunction(function.id)
                    model.workspaceSection = .routing
                }
                Button("Duplicate") { model.duplicateFunction(function.id) }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = function }
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
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
    }
}

// MARK: Function editor

struct FunctionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: MIDIOutputFunction
    @State private var number: String
    @State private var value: String
    @State private var usesInputValue: Bool
    let isNew: Bool

    init(function: MIDIOutputFunction, isNew: Bool, model: AppModel) {
        self.model = model
        self.isNew = isNew
        _draft = State(initialValue: function)
        _number = State(initialValue: String(function.output.number))
        _value = State(initialValue: function.output.value.map(String.init) ?? "127")
        _usesInputValue = State(initialValue: function.output.value == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New function" : "Edit function")
                .font(.title2.weight(.semibold))

            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    formLabel("Name")
                    TextField("Name", text: $draft.name, prompt: Text("AbleSet Play"))
                        .labelsHidden()
                }
                GridRow {
                    formLabel("Group")
                    TextField("Group", text: $draft.group, prompt: Text("App or device, such as AbleSet"))
                        .labelsHidden()
                }
                Divider().gridCellColumns(2)
                GridRow {
                    formLabel("Send")
                    Picker("Message type", selection: $draft.output.type) {
                        ForEach(MIDIFunctionOutputType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    formLabel("Channel")
                    Picker("Channel", selection: $draft.output.channel) {
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(channel)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    formLabel(numberLabel)
                    TextField(numberLabel, text: $number, prompt: Text("0–127"))
                        .labelsHidden()
                }
                if draft.output.type.supportsValue {
                    GridRow {
                        formLabel(valueLabel)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(valueLabel, text: $value, prompt: Text(draft.output.type == .note ? "1–127" : "0–127"))
                                .labelsHidden()
                                .disabled(usesInputValue)
                            Toggle(draft.output.type == .note ? "Use the input’s velocity" : "Use the input’s value",
                                   isOn: $usesInputValue)
                                .help("Pass the trigger’s velocity or CC value through instead of a fixed value.")
                        }
                    }
                }
                GridRow {
                    formLabel("Destination")
                    Picker("Destination", selection: $draft.destinationID) {
                        Text("\(AppModel.outputName) (virtual port)").tag(nil as String?)
                        if let id = draft.destinationID, !model.destinations.contains(where: { $0.id == id }) {
                            Text("\(draft.destinationName ?? "Saved destination") (offline)").tag(Optional(id))
                        }
                        if !model.destinations.isEmpty { Divider() }
                        ForEach(model.destinations) { destination in
                            Text(destination.name).tag(Optional(destination.id))
                        }
                    }
                    .labelsHidden()
                    .help("The virtual port reaches apps such as Ableton Live and AbleSet. Choose a device to send to hardware such as the Quad Cortex.")
                }
                Divider().gridCellColumns(2)
                GridRow {
                    formLabel("Notes")
                    TextField("Notes", text: $draft.notes, prompt: Text("Optional"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...4)
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Toggle("Placeholder: verify before use", isOn: $draft.needsVerification)
                        .help("Marks starter functions whose message hasn’t been checked against your setup yet.")
                }
            }

            if let validationMessage {
                ErrorText(code: "FUNC-001", message: validationMessage)
                    .font(.callout)
            } else if let id = draft.destinationID, !model.destinations.contains(where: { $0.id == id }) {
                ErrorText(code: "MIDI-108", message: "This destination is offline. Messages to it are skipped.")
            } else {
                Text("Changes apply everywhere this function is loaded.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack {
                Button {
                    if let function = parsedFunction { model.testFunction(function) }
                } label: {
                    Label("Send test", systemImage: "play.circle")
                }
                .disabled(parsedFunction == nil || !model.outputReady)
                .help("Send this output once, without saving")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add function" : "Save function") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(validationMessage != nil)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private var numberLabel: String {
        switch draft.output.type {
        case .note: "Note number"
        case .controlChange: "CC number"
        case .programChange: "Program number"
        }
    }

    private var valueLabel: String {
        draft.output.type == .note ? "Velocity" : "Value"
    }

    private var validationMessage: String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a name for this function."
        }
        if !isValidMIDINumber(number, allowEmpty: false) {
            return "Enter a \(numberLabel.lowercased()) from 0 to 127."
        }
        if draft.output.type.supportsValue, !usesInputValue,
           !isValidMIDINumber(value, allowEmpty: false, range: draft.output.type.valueRange) {
            return draft.output.type == .note ? "Enter a velocity from 1 to 127." : "Enter a value from 0 to 127."
        }
        return nil
    }

    private var parsedFunction: MIDIOutputFunction? {
        guard validationMessage == nil, let number = parsedNumber(number) else { return nil }
        var function = draft
        function.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        function.group = draft.group.trimmingCharacters(in: .whitespacesAndNewlines)
        function.output.number = number
        if !draft.output.type.supportsValue {
            function.output.value = nil
        } else {
            function.output.value = usesInputValue ? nil : parsedNumber(value)
        }
        return function.output.isValid ? function : nil
    }

    private func save() {
        guard let function = parsedFunction else { return }
        model.saveFunction(function)
        dismiss()
    }
}

// MARK: Mapping editor

struct MappingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: MIDIFunctionMapping
    @State private var trigger: MIDITrigger
    @State private var number: String
    let startLearning: Bool

    init(mapping: MIDIFunctionMapping, startLearning: Bool, model: AppModel) {
        self.model = model
        self.startLearning = startLearning
        _draft = State(initialValue: mapping)
        let trigger = mapping.trigger ?? MIDITrigger()
        _trigger = State(initialValue: trigger)
        _number = State(initialValue: trigger.number.map(String.init) ?? "")
    }

    var body: some View {
        let function = model.function(id: draft.functionID)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Map input").font(.title2.weight(.semibold))
                    Text(function?.name ?? "Missing function")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                learnButton
            }

            if let function {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Sends \(outputSummary(function.output)) to \(model.destinationName(for: function))")
                            .font(.callout)
                        if function.needsVerification { VerifyBadge() }
                    }
                    Text("Edit the output in the function library. Changes apply wherever this function is loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brandTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ErrorText(code: "FUNC-003", message: "This function is no longer in the library.")
            }

            if model.isLearning {
                Label("Press a pad, footswitch, or key, or send a Program Change.", systemImage: "waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    formLabel("Input")
                    Picker("Input", selection: $trigger.deviceID) {
                        Text("Any input").tag(nil as String?)
                        if let deviceID = trigger.deviceID, !model.sources.contains(where: { $0.id == deviceID }) {
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
                    Picker("Input channel", selection: $trigger.channel) {
                        Text("Any channel").tag(nil as Int?)
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(Optional(channel))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    formLabel("Message type")
                    Picker("Message type", selection: $trigger.type) {
                        ForEach(MIDITrigger.supportedTypes) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    formLabel(numberLabel)
                    TextField(numberLabel, text: $number, prompt: Text("Any number"))
                        .labelsHidden()
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }
            }

            if let validationMessage {
                ErrorText(code: "FUNC-002", message: validationMessage)
                    .font(.callout)
            } else {
                Text("A matched input sends this function and isn’t passed to the rules.")
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
                Button("Save mapping") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLearning || validationMessage != nil || function == nil)
            }
        }
        .padding(22)
        .frame(width: 450)
        .onAppear {
            if startLearning, model.canLearn { model.beginLearning(onLearn: applyLearnedInput) }
        }
    }

    private var learnButton: some View {
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
        .help(model.isLearning ? "Stop listening for MIDI."
              : model.canLearn ? "Fill the input fields from the next MIDI message."
              : "Enable a connected MIDI input in Routing to use MIDI Learn.")
    }

    private var numberLabel: String {
        switch trigger.type {
        case .controlChange: "CC number"
        case .programChange: "Program number"
        default: "Note number"
        }
    }

    private var validationMessage: String? {
        isValidMIDINumber(number, allowEmpty: true) ? nil : "Enter an input number from 0 to 127, or leave it empty for any."
    }

    private func applyLearnedInput(_ input: MIDILearnedInput) {
        trigger.deviceID = input.deviceID
        trigger.channel = input.channel
        trigger.type = input.type
        number = input.number.map(String.init) ?? ""
    }

    private func save() {
        guard validationMessage == nil else { return }
        trigger.number = parsedNumber(number)
        draft.trigger = trigger
        model.saveMapping(draft)
        dismiss()
    }
}
