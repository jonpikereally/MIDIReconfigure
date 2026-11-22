import Foundation

/// The kind of message an output function sends.
public enum MIDIFunctionOutputType: String, CaseIterable, Identifiable, Codable, Sendable {
    case note
    case controlChange
    case programChange

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .note: "Note"
        case .controlChange: "Control Change"
        case .programChange: "Program Change"
        }
    }

    public var shortTitle: String {
        switch self {
        case .note: "Note"
        case .controlChange: "CC"
        case .programChange: "PC"
        }
    }

    public var supportsValue: Bool { self != .programChange }

    /// Note velocity must be at least 1 because a Note On with velocity 0 is a release.
    public var valueRange: ClosedRange<Int> { self == .note ? 1...127 : 0...127 }
}

/// The MIDI message a function sends when its trigger fires.
public struct MIDIFunctionOutput: Codable, Equatable, Sendable {
    public var type: MIDIFunctionOutputType
    /// Output channel, 1–16.
    public var channel: Int
    /// Note, CC, or program number, 0–127.
    public var number: Int
    /// Velocity or CC value. Nil sends the trigger's own value. Ignored for Program Change.
    public var value: Int?

    public init(type: MIDIFunctionOutputType, channel: Int, number: Int, value: Int? = 127) {
        self.type = type
        self.channel = channel
        self.number = number
        self.value = value
    }

    public var isValid: Bool {
        (1...16).contains(channel) && (0...127).contains(number)
            && (value.map { !type.supportsValue || type.valueRange.contains($0) } ?? true)
    }
}

/// A named, reusable MIDI command such as "AbleSet Play" or "Quad Cortex Tuner".
public struct MIDIOutputFunction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Free-text grouping such as the target app or device.
    public var group: String
    public var output: MIDIFunctionOutput
    /// CoreMIDI destination unique ID. Nil sends to the MIDI Reconfigure virtual port.
    public var destinationID: String?
    /// Last known destination name, shown while the destination is offline.
    public var destinationName: String?
    /// Set for starter functions whose messages are placeholders.
    public var needsVerification: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        group: String = "",
        output: MIDIFunctionOutput,
        destinationID: String? = nil,
        destinationName: String? = nil,
        needsVerification: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.output = output
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.needsVerification = needsVerification
        self.notes = notes
    }

    /// Placeholder functions created on first launch. Their messages must be edited to match the target setup.
    public static let starterLibrary: [MIDIOutputFunction] = [
        MIDIOutputFunction(
            name: "AbleSet Play", group: "AbleSet",
            output: MIDIFunctionOutput(type: .controlChange, channel: 16, number: 20, value: 127),
            needsVerification: true,
            notes: "Placeholder. Set this to the message mapped to Play in AbleSet’s MIDI settings."
        ),
        MIDIOutputFunction(
            name: "AbleSet Stop", group: "AbleSet",
            output: MIDIFunctionOutput(type: .controlChange, channel: 16, number: 21, value: 127),
            needsVerification: true,
            notes: "Placeholder. Set this to the message mapped to Stop in AbleSet’s MIDI settings."
        ),
        MIDIOutputFunction(
            name: "AbleSet Next Song", group: "AbleSet",
            output: MIDIFunctionOutput(type: .controlChange, channel: 16, number: 22, value: 127),
            needsVerification: true,
            notes: "Placeholder. Set this to the message mapped to Next Song in AbleSet’s MIDI settings."
        ),
        MIDIOutputFunction(
            name: "AbleSet Previous Song", group: "AbleSet",
            output: MIDIFunctionOutput(type: .controlChange, channel: 16, number: 23, value: 127),
            needsVerification: true,
            notes: "Placeholder. Set this to the message mapped to Previous Song in AbleSet’s MIDI settings."
        ),
        MIDIOutputFunction(
            name: "Quad Cortex Tuner", group: "Neural DSP Quad Cortex Mini",
            output: MIDIFunctionOutput(type: .controlChange, channel: 1, number: 45, value: 127),
            needsVerification: true,
            notes: "Placeholder. Confirm the tuner CC and MIDI channel in the Quad Cortex MIDI settings, "
                + "then choose the Quad Cortex as the destination."
        )
    ]
}

/// The input that fires a function.
public struct MIDITrigger: Codable, Equatable, Sendable {
    public var deviceID: String?
    public var channel: Int?
    /// Note, Control Change, or Program Change.
    public var type: MIDIMessageType
    public var number: Int?

    public init(deviceID: String? = nil, channel: Int? = nil, type: MIDIMessageType = .note, number: Int? = nil) {
        self.deviceID = deviceID
        self.channel = channel
        self.type = type
        self.number = number
    }

    public static let supportedTypes: [MIDIMessageType] = [.note, .controlChange, .programChange]

    func matches(_ message: MIDIMessage, from deviceID: String) -> Bool {
        (self.deviceID == nil || self.deviceID == deviceID)
            && (channel == nil || channel == message.channel)
            && type == message.type
            && (number == nil || number == message.number)
    }
}

/// A function loaded into the routing configuration with its input mapping.
public struct MIDIFunctionMapping: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var functionID: UUID
    public var isEnabled: Bool
    /// Nil until the input is mapped.
    public var trigger: MIDITrigger?

    public init(id: UUID = UUID(), functionID: UUID, isEnabled: Bool = true, trigger: MIDITrigger? = nil) {
        self.id = id
        self.functionID = functionID
        self.isEnabled = isEnabled
        self.trigger = trigger
    }
}

/// One outgoing message produced by a function.
public struct MIDIFunctionEmission: Equatable, Sendable {
    /// Nil is the virtual port.
    public let destinationID: String?
    public let functionName: String
    public let message: MIDIMessage
}

/// Turns incoming trigger messages into function output. Mappings run before routing rules.
public struct MIDIFunctionEngine: Sendable {
    private struct NoteKey: Hashable, Sendable {
        let deviceID: String
        let group: UInt32
        let channel: Int
        let number: Int
    }

    public var functions: [MIDIOutputFunction] = [] {
        didSet { functionsByID = Dictionary(functions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    public var mappings: [MIDIFunctionMapping] = []

    private var functionsByID: [UUID: MIDIOutputFunction] = [:]
    // Note-offs owed for each held trigger note, oldest press first.
    private var heldNotes: [NoteKey: [[MIDIFunctionEmission]]] = [:]

    public init() {}

    /// Returns the messages to send, or nil when no mapping claims the message.
    /// An empty array means a mapping consumed the message without sending anything, such as a trigger release.
    public mutating func handle(_ message: MIDIMessage, from deviceID: String) -> [MIDIFunctionEmission]? {
        let noteKey = message.type == .note
            ? message.number.map { NoteKey(deviceID: deviceID, group: message.group, channel: message.channel, number: $0) }
            : nil
        if let noteKey, message.isNoteRelease, var pending = heldNotes.removeValue(forKey: noteKey) {
            // Finish the earlier press with the output it produced, even after the library changes.
            let releases = pending.removeFirst()
            if !pending.isEmpty { heldNotes[noteKey] = pending }
            return releases
        }

        guard let mapping = mappings.first(where: { mapping in
            mapping.isEnabled && mapping.trigger?.matches(message, from: deviceID) == true
                && functionsByID[mapping.functionID] != nil
        }), let function = functionsByID[mapping.functionID] else { return nil }

        let output = function.output
        let isPress = Self.isPress(message)
        func emit(_ message: MIDIMessage) -> MIDIFunctionEmission {
            MIDIFunctionEmission(destinationID: function.destinationID, functionName: function.name, message: message)
        }

        switch output.type {
        case .programChange:
            guard isPress else { return [] }
            return [emit(.programChange(channel: output.channel, program: output.number, group: message.group))]
        case .controlChange:
            if let value = output.value {
                guard isPress else { return [] }
                return [emit(.controlChange(channel: output.channel, number: output.number, value: value, group: message.group))]
            }
            return [emit(.controlChange(
                channel: output.channel, number: output.number, value: Self.triggerValue(message), group: message.group
            ))]
        case .note:
            guard isPress else { return [] }
            let velocity = output.value ?? Self.triggerValue(message)
            let on = emit(.noteOn(channel: output.channel, number: output.number, velocity: velocity, group: message.group))
            let off = emit(.noteOff(channel: output.channel, number: output.number, group: message.group))
            if let noteKey {
                heldNotes[noteKey, default: []].append([off])
                return [on]
            }
            return [on, off]
        }
    }

    /// Whether a note release would finish a press a function is still holding.
    public func isHoldingNote(_ message: MIDIMessage, from deviceID: String) -> Bool {
        guard message.type == .note, let number = message.number else { return false }
        return heldNotes[NoteKey(deviceID: deviceID, group: message.group, channel: message.channel, number: number)] != nil
    }

    /// Generates the note-offs owed for held trigger notes and forgets them.
    public mutating func releaseNotes(from deviceID: String? = nil) -> [MIDIFunctionEmission] {
        let keys = heldNotes.keys.filter { deviceID == nil || $0.deviceID == deviceID }
        return keys.flatMap { heldNotes.removeValue(forKey: $0)?.flatMap { $0 } ?? [] }
    }

    /// The messages sent when a function is tested from the library.
    public static func testEmissions(for function: MIDIOutputFunction) -> [MIDIFunctionEmission] {
        let output = function.output
        func emit(_ message: MIDIMessage) -> MIDIFunctionEmission {
            MIDIFunctionEmission(destinationID: function.destinationID, functionName: function.name, message: message)
        }
        switch output.type {
        case .programChange:
            return [emit(.programChange(channel: output.channel, program: output.number))]
        case .controlChange:
            return [emit(.controlChange(channel: output.channel, number: output.number, value: output.value ?? 127))]
        case .note:
            return [
                emit(.noteOn(channel: output.channel, number: output.number, velocity: output.value ?? 100)),
                emit(.noteOff(channel: output.channel, number: output.number))
            ]
        }
    }

    private static func isPress(_ message: MIDIMessage) -> Bool {
        switch message.type {
        case .note: !message.isNoteRelease
        case .controlChange: (message.value ?? 0) > 0
        default: true
        }
    }

    private static func triggerValue(_ message: MIDIMessage) -> Int {
        switch message.type {
        case .note: message.isNoteRelease ? 0 : message.value ?? 127
        case .controlChange: message.value ?? 0
        default: 127
        }
    }
}
