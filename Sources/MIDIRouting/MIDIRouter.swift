import Foundation

public struct MIDIRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var deviceID: String?
    public var inputChannel: Int?
    public var type: MIDIMessageType
    public var inputNumber: Int?
    public var outputChannel: Int?
    public var outputNumber: Int?
    public var invertCC: Bool
    public var drop: Bool

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        deviceID: String? = nil,
        inputChannel: Int? = nil,
        type: MIDIMessageType = .any,
        inputNumber: Int? = nil,
        outputChannel: Int? = nil,
        outputNumber: Int? = nil,
        invertCC: Bool = false,
        drop: Bool = false
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.deviceID = deviceID
        self.inputChannel = inputChannel
        self.type = type
        self.inputNumber = inputNumber
        self.outputChannel = outputChannel
        self.outputNumber = outputNumber
        self.invertCC = invertCC
        self.drop = drop
    }

    func matches(_ message: MIDIMessage, from deviceID: String) -> Bool {
        isEnabled && (self.deviceID == nil || self.deviceID == deviceID)
            && (inputChannel == nil || inputChannel == message.channel)
            && (type == .any || type == message.type)
            && (inputNumber == nil || inputNumber == message.number)
    }
}

public struct MIDIRouter: Sendable {
    public var rules: [MIDIRule] = []
    public var defaultOutputChannel: Int?

    private struct NoteKey: Hashable, Sendable {
        let deviceID: String
        let group: UInt32
        let channel: Int
        let number: Int
    }

    private struct OutputChannel: Hashable, Sendable {
        let group: UInt32
        let channel: Int
    }

    private struct SustainAssignment: Sendable {
        let deviceID: String
        let message: MIDIMessage
    }

    // A nil assignment stands for a press that produced no sounding note.
    private var activeNotes: [NoteKey: [MIDIMessage?]] = [:]
    private var activeSustain: [OutputChannel: SustainAssignment] = [:]

    public init() {}

    public mutating func route(_ message: MIDIMessage, from deviceID: String) -> MIDIMessage? {
        if message.type == .note, let number = message.number {
            let key = NoteKey(deviceID: deviceID, group: message.group, channel: message.channel, number: number)
            if message.isNoteRelease {
                // Finish earlier presses in order, even after the rules change.
                if var presses = activeNotes.removeValue(forKey: key) {
                    let press = presses.removeFirst()
                    if !presses.isEmpty { activeNotes[key] = presses }
                    return press.map { message.remapped(channel: $0.channel, number: $0.number) }
                }
            } else {
                let output = transform(message, from: deviceID)
                activeNotes[key, default: []].append(output)
                return output
            }
        }

        let output = transform(message, from: deviceID)
        if let output, output.type == .controlChange {
            updateSustain(output, from: deviceID)
            if output.silencesChannelNotes { clearMutedNotes(output: output, input: message, from: deviceID) }
        }
        return output
    }

    /// Whether a note release would finish a press this router already sent.
    public func isHoldingNote(_ message: MIDIMessage, from deviceID: String) -> Bool {
        guard message.type == .note, let number = message.number else { return false }
        return activeNotes[NoteKey(deviceID: deviceID, group: message.group, channel: message.channel, number: number)] != nil
    }

    /// Generates note-offs for sounding notes and discards their stored assignments.
    public mutating func releaseNotes(from deviceID: String? = nil) -> [MIDIMessage] {
        let keys = activeNotes.keys.filter { deviceID == nil || $0.deviceID == deviceID }
        let notes = keys.flatMap { key in
            activeNotes.removeValue(forKey: key)?.compactMap { $0?.noteOff() } ?? []
        }
        return notes.sorted { $0.word < $1.word }
    }

    /// Releases down sustain pedals last set by this input on their actual output channels.
    public mutating func releaseSustain(from deviceID: String? = nil) -> [MIDIMessage] {
        let channels = activeSustain.compactMap { channel, assignment in
            deviceID == nil || assignment.deviceID == deviceID ? channel : nil
        }
        let pedals = channels.compactMap { activeSustain.removeValue(forKey: $0)?.message.pedalOff() }
        return pedals.sorted { $0.word < $1.word }
    }

    private mutating func updateSustain(_ message: MIDIMessage, from deviceID: String) {
        guard let number = message.number, let value = message.value else { return }
        let channel = OutputChannel(group: message.group, channel: message.channel)
        switch (number, value) {
        case (64, 64...127):
            activeSustain[channel] = SustainAssignment(deviceID: deviceID, message: message)
        case (64, 0...63), (121, 0):
            activeSustain.removeValue(forKey: channel)
        default:
            break
        }
    }

    private mutating func clearMutedNotes(output: MIDIMessage, input: MIDIMessage, from deviceID: String) {
        for (key, presses) in activeNotes {
            let inputMuted = input.silencesChannelNotes && key.deviceID == deviceID
                && key.group == input.group && key.channel == input.channel
            let remaining = presses.filter { press in
                if let press { return press.group != output.group || press.channel != output.channel }
                return !inputMuted
            }
            if remaining.isEmpty {
                activeNotes.removeValue(forKey: key)
            } else if remaining.count != presses.count {
                activeNotes[key] = remaining
            }
        }
    }

    private func transform(_ message: MIDIMessage, from deviceID: String) -> MIDIMessage? {
        let rule = rules.first { $0.matches(message, from: deviceID) }
        guard rule?.drop != true else { return nil }
        return message.remapped(
            channel: rule?.outputChannel ?? defaultOutputChannel,
            number: rule?.outputNumber,
            invertCC: rule?.invertCC == true
        )
    }
}
