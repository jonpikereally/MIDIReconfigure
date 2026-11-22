public enum MIDIMessageType: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case note
    case controlChange
    case programChange
    case polyphonicPressure
    case channelPressure
    case pitchBend

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: "Any channel message"
        case .note: "Note"
        case .controlChange: "Control Change"
        case .programChange: "Program Change"
        case .polyphonicPressure: "Polyphonic Pressure"
        case .channelPressure: "Channel Pressure"
        case .pitchBend: "Pitch Bend"
        }
    }

    public var supportsNumber: Bool {
        switch self {
        case .note, .controlChange, .programChange, .polyphonicPressure: true
        case .any, .channelPressure, .pitchBend: false
        }
    }
}

/// A MIDI 1.0 channel voice Universal MIDI Packet.
public struct MIDIMessage: Equatable, Sendable {
    public let word: UInt32

    private enum Status: UInt32 {
        case noteOff = 8
        case noteOn
        case polyphonicPressure
        case controlChange
        case programChange
        case channelPressure
        case pitchBend
    }

    private let status: Status

    public init?(word: UInt32) {
        guard word >> 28 == 2, let status = Status(rawValue: (word >> 20) & 0xF),
              word & 0x0000_8080 == 0 else { return nil }
        self.init(word: word, status: status)
    }

    private init(word: UInt32, status: Status) {
        self.word = word
        self.status = status
    }

    var group: UInt32 { (word >> 24) & 0xF }
    public var channel: Int { Int((word >> 16) & 0xF) + 1 }
    private var firstDataByte: Int { Int((word >> 8) & 0x7F) }
    private var secondDataByte: Int { Int(word & 0x7F) }

    public var type: MIDIMessageType {
        switch status {
        case .noteOn, .noteOff: .note
        case .controlChange: .controlChange
        case .programChange: .programChange
        case .polyphonicPressure: .polyphonicPressure
        case .channelPressure: .channelPressure
        case .pitchBend: .pitchBend
        }
    }

    public var number: Int? { type.supportsNumber ? firstDataByte : nil }

    public var value: Int? {
        switch status {
        case .noteOn, .noteOff, .polyphonicPressure, .controlChange: secondDataByte
        case .programChange: nil
        case .channelPressure: firstDataByte
        case .pitchBend: (secondDataByte << 7) | firstDataByte
        }
    }

    public var name: String {
        switch status {
        case .noteOn, .noteOff: isNoteRelease ? "Note Off" : "Note On"
        default: type.title
        }
    }

    public var isNoteRelease: Bool { status == .noteOff || (status == .noteOn && secondDataByte == 0) }

    var silencesChannelNotes: Bool {
        status == .controlChange && secondDataByte == 0 && (firstDataByte == 120 || firstDataByte == 123)
    }

    func remapped(channel: Int?, number: Int? = nil, invertCC: Bool = false) -> MIDIMessage {
        var result = word
        if let channel, (1...16).contains(channel) {
            result = (result & 0xFFF0_FFFF) | (UInt32(channel - 1) << 16)
        }
        if let number, type.supportsNumber, (0...127).contains(number) {
            result = (result & 0xFFFF_00FF) | (UInt32(number) << 8)
        }
        if invertCC, status == .controlChange {
            result = (result & 0xFFFF_FF00) | UInt32(127 - secondDataByte)
        }
        return MIDIMessage(word: result, status: status)
    }

    private static func channelVoice(_ status: Status, group: UInt32, channel: Int, data1: Int, data2: Int) -> MIDIMessage {
        let channelBits = UInt32(min(max(channel, 1), 16) - 1)
        let word = 0x2000_0000 | ((group & 0xF) << 24) | (status.rawValue << 20) | (channelBits << 16)
            | (UInt32(min(max(data1, 0), 127)) << 8) | UInt32(min(max(data2, 0), 127))
        return MIDIMessage(word: word, status: status)
    }

    public static func noteOn(channel: Int, number: Int, velocity: Int, group: UInt32 = 0) -> MIDIMessage {
        channelVoice(.noteOn, group: group, channel: channel, data1: number, data2: max(velocity, 1))
    }

    public static func noteOff(channel: Int, number: Int, group: UInt32 = 0) -> MIDIMessage {
        channelVoice(.noteOff, group: group, channel: channel, data1: number, data2: 0)
    }

    public static func controlChange(channel: Int, number: Int, value: Int, group: UInt32 = 0) -> MIDIMessage {
        channelVoice(.controlChange, group: group, channel: channel, data1: number, data2: value)
    }

    public static func programChange(channel: Int, program: Int, group: UInt32 = 0) -> MIDIMessage {
        channelVoice(.programChange, group: group, channel: channel, data1: program, data2: 0)
    }

    func noteOff() -> MIDIMessage {
        let result = (word & 0xFF0F_FF00) | (Status.noteOff.rawValue << 20)
        return MIDIMessage(word: result, status: .noteOff)
    }

    func pedalOff() -> MIDIMessage {
        MIDIMessage(word: word & 0xFFFF_FF00, status: status)
    }
}
