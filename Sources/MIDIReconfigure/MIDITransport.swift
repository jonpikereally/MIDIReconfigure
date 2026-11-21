import CoreMIDI
import Foundation
import MIDIRouting

struct MIDIInputSource: Equatable, Identifiable {
    let id: String
    let name: String
}

struct MIDITransportError: Error, Identifiable {
    let id = UUID()
    let code: String
    let message: String
}

struct MIDIActivity: Identifiable {
    enum Direction: String, CaseIterable {
        case incoming, outgoing
    }

    let id = UUID()
    let timestamp: Date
    let direction: Direction
    let deviceID: String
    let deviceName: String
    let type: String
    let channel: Int?
    let detail: String
}

struct MIDILearnedInput: Sendable {
    let deviceID: String
    let type: MIDIRouting.MIDIMessageType
    let channel: Int
    let number: Int?
}

final class MIDITransport: @unchecked Sendable {
    static let outputName = "MIDI Reconfigure"
    private static let savedOutputID = "VirtualOutputUniqueID"
    private static let eventListCapacity = 65_536
    private static let monitorBatchLimit = 1_024

    private struct Source {
        let endpoint: MIDIEndpointRef
        let input: MIDIInputSource
    }

    private struct LearnRequest {
        let id: UUID
        let onLearn: (UUID, MIDILearnedInput) -> Void
    }

    private struct EventPacket {
        private static let packetOffset = MemoryLayout<MIDIEventList>.offset(of: \.packet)!
        private static let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)!

        let timestamp: MIDITimeStamp
        let words: [UInt32]

        static func copyPackets(from list: UnsafePointer<MIDIEventList>) -> [Self] {
            var packet = UnsafeRawPointer(list).advanced(by: packetOffset)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            return (0..<list.pointee.numPackets).map { _ in
                let words = UnsafeRawPointer(packet).advanced(by: wordsOffset)
                    .assumingMemoryBound(to: UInt32.self)
                let copy = Self(
                    timestamp: packet.pointee.timeStamp,
                    words: Array(UnsafeBufferPointer(start: words, count: Int(packet.pointee.wordCount)))
                )
                packet = UnsafePointer(MIDIEventPacketNext(packet))
                return copy
            }
        }
    }

    // CoreMIDI delivers inputs on its own thread. All routing and CoreMIDI handles live on this queue.
    private let queue = DispatchQueue(label: "MIDIReconfigure.transport", qos: .userInteractive)
    private let defaults: UserDefaults
    private let onSources: ([MIDIInputSource]) -> Void
    private let onActivity: ([MIDIActivity]) -> Void
    private let onStatus: (Bool) -> Void
    private let onError: (MIDITransportError) -> Void
    private let sessionID = UUID().uuidString
    private let eventListStorage = UnsafeMutableRawPointer.allocate(
        byteCount: eventListCapacity,
        alignment: MemoryLayout<MIDIEventList>.alignment
    ).bindMemory(to: MIDIEventList.self, capacity: 1)

    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var output: MIDIEndpointRef = 0
    private var sourceTimer: DispatchSourceTimer?
    private var router = MIDIRouter()
    private var enabledSourceIDs: Set<String> = []
    private var isPaused = false
    private var sources: [MIDIInputSource] = []
    private var connections: [Int: Source] = [:]
    private var connectionToken = 0
    private var learnRequest: LearnRequest?
    private var monitorBatch: [MIDIActivity] = []
    private var monitorDeliveryScheduled = false
    private var lastError: (code: String, message: String, time: Date)?

    init(
        defaults: UserDefaults = .standard,
        onSources: @escaping ([MIDIInputSource]) -> Void,
        onActivity: @escaping ([MIDIActivity]) -> Void,
        onStatus: @escaping (Bool) -> Void,
        onError: @escaping (MIDITransportError) -> Void
    ) {
        self.defaults = defaults
        self.onSources = onSources
        self.onActivity = onActivity
        self.onStatus = onStatus
        self.onError = onError
    }

    deinit {
        disposePortsAndSource()
        if client != 0 { MIDIClientDispose(client) }
        eventListStorage.deallocate()
    }

    func start() {
        queue.async { [weak self] in self?.startIfNeeded() }
    }

    func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.resetPorts()
            self.startIfNeeded()
        }
    }

    func configure(enabledSourceIDs: Set<String>, rules: [MIDIRule], defaultOutputChannel: Int?, isPaused: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if isPaused && !self.isPaused {
                self.releaseConnectedNotes()
            }
            let selectionChanged = self.enabledSourceIDs != enabledSourceIDs
            self.enabledSourceIDs = enabledSourceIDs
            self.router.rules = rules
            self.router.defaultOutputChannel = defaultOutputChannel
            self.isPaused = isPaused
            if selectionChanged { self.updateSources() }
        }
    }

    func armLearn(_ requestID: UUID, onLearn: @escaping (UUID, MIDILearnedInput) -> Void) {
        queue.async { [weak self] in
            self?.learnRequest = LearnRequest(id: requestID, onLearn: onLearn)
        }
    }

    func cancelLearn() {
        queue.async { [weak self] in self?.learnRequest = nil }
    }

    func refreshSources() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.inputPort == 0 {
                self.startIfNeeded()
            } else {
                self.updateSources()
            }
        }
    }

    func stop() {
        queue.sync {
            resetPorts()
            if client != 0 {
                MIDIClientDispose(client)
                client = 0
            }
        }
    }

    private func startIfNeeded() {
        guard inputPort == 0 else { return }

        if client == 0 {
            var newClient: MIDIClientRef = 0
            let clientStatus = MIDIClientCreateWithBlock(Self.outputName as CFString, &newClient) {
                [weak self] notification in
                switch notification.pointee.messageID {
                case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                    self?.queue.async { [weak self] in self?.updateSources() }
                default:
                    break
                }
            }
            guard clientStatus == noErr else {
                startupFailed("MIDI-101", "Couldn’t start CoreMIDI", status: clientStatus)
                return
            }
            client = newClient
        }

        let outputStatus = MIDISourceCreateWithProtocol(client, Self.outputName as CFString, ._1_0, &output)
        guard outputStatus == noErr else {
            startupFailed("MIDI-102", "Couldn’t publish the virtual MIDI output", status: outputStatus)
            return
        }
        restoreOutputID()

        let inputStatus = MIDIInputPortCreateWithProtocol(client, "MIDI Reconfigure Input" as CFString, ._1_0, &inputPort) {
            [weak self] list, context in
            guard let self, let context else { return }
            let token = Int(bitPattern: context)
            // CoreMIDI owns the list until this callback returns.
            let packets = EventPacket.copyPackets(from: list)
            let received = Date()
            self.queue.async { [weak self] in
                self?.receive(packets, from: token, received: received)
            }
        }
        guard inputStatus == noErr else {
            startupFailed("MIDI-103", "Couldn’t create the MIDI input port", status: inputStatus)
            return
        }

        updateSources()
        // A source can disappear from CoreMIDI's graph without an object removal callback.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.updateSources() }
        sourceTimer = timer
        timer.resume()
        publishStatus(true)
    }

    private func startupFailed(_ code: String, _ message: String, status: OSStatus) {
        disposePortsAndSource()
        publishStatus(false)
        report(code, message, status: status)
    }

    private func resetPorts() {
        learnRequest = nil
        releaseConnectedNotes()
        connections.removeAll()
        disposePortsAndSource()
        publishSources([])
        publishStatus(false)
        lastError = nil
    }

    private func disposePortsAndSource() {
        sourceTimer?.cancel()
        sourceTimer = nil
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if output != 0 { MIDIEndpointDispose(output) }
        inputPort = 0
        output = 0
    }

    private func restoreOutputID() {
        if let savedID = Int32(exactly: defaults.integer(forKey: Self.savedOutputID)), savedID != 0 {
            let status = MIDIObjectSetIntegerProperty(output, kMIDIPropertyUniqueID, savedID)
            if status == noErr { return }
            report("MIDI-106", "Couldn’t restore the virtual output identity", status: status)
        }

        var outputID: MIDIUniqueID = 0
        let status = MIDIObjectGetIntegerProperty(output, kMIDIPropertyUniqueID, &outputID)
        if status == noErr {
            defaults.set(Int(outputID), forKey: Self.savedOutputID)
        } else {
            report("MIDI-106", "Couldn’t save the virtual output identity", status: status)
        }
    }

    private func updateSources() {
        guard inputPort != 0 else { return }

        var seenEndpoints: Set<MIDIEndpointRef> = []
        let discovered = (0..<MIDIGetNumberOfSources()).compactMap { index -> Source? in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, endpoint != output, seenEndpoints.insert(endpoint).inserted,
                  !isOffline(endpoint) else { return nil }
            var uniqueID: MIDIUniqueID = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            let id = status == noErr && uniqueID != 0 ? String(uniqueID) : "\(sessionID):\(endpoint)"
            let name = stringProperty(endpoint, key: kMIDIPropertyDisplayName)
                ?? stringProperty(endpoint, key: kMIDIPropertyName)
                ?? "MIDI Input \(index + 1)"
            return Source(endpoint: endpoint, input: MIDIInputSource(id: id, name: name))
        }
        let inputs = discovered.map(\.input).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        publishSources(inputs)

        let enabled = discovered.filter { enabledSourceIDs.contains($0.input.id) }
        let byEndpoint = Dictionary(uniqueKeysWithValues: enabled.map { ($0.endpoint, $0) })
        for (token, connection) in connections {
            if let updated = byEndpoint[connection.endpoint], updated.input.id == connection.input.id {
                connections[token] = updated
            } else {
                MIDIPortDisconnectSource(inputPort, connection.endpoint)
                connections.removeValue(forKey: token)
                releaseNotes(from: connection.input)
            }
        }
        let connected = Set(connections.values.map(\.endpoint))
        for source in enabled where !connected.contains(source.endpoint) {
            connectionToken += 1
            let context = UnsafeMutableRawPointer(bitPattern: connectionToken)
            let status = MIDIPortConnectSource(inputPort, source.endpoint, context)
            if status == noErr {
                connections[connectionToken] = source
            } else {
                report("MIDI-104", "Couldn’t connect to \(source.input.name)", status: status)
            }
        }
    }

    private func isOffline(_ endpoint: MIDIEndpointRef) -> Bool {
        var offline: Int32 = 0
        if MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline) == noErr, offline != 0 {
            return true
        }
        var entity: MIDIEntityRef = 0
        var device: MIDIDeviceRef = 0
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0,
              MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else { return false }
        return MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline) == noErr && offline != 0
    }

    private func stringProperty(_ endpoint: MIDIEndpointRef, key: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, key, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func receive(_ packets: [EventPacket], from token: Int, received: Date) {
        guard let source = connections[token]?.input else { return }
        for packet in packets {
            var packetRouter = router
            var outputWords: [UInt32] = []
            var activity: [MIDIActivity] = []
            var index = 0
            while index < packet.words.count {
                let word = packet.words[index]
                let message = MIDIMessage(word: word)
                let type = Int(word >> 28)
                let wordCount = Self.umpWordCounts[type]
                let next = index + wordCount
                guard next <= packet.words.count else { break }
                if let message { learn(from: message, deviceID: source.id) }
                let messageWords = packet.words[index..<next]
                let incoming = activityRow(for: message, words: messageWords, from: source, direction: .incoming, time: received)
                activity.append(incoming)
                index = next
                guard !isPaused else { continue }

                if let message {
                    guard let routed = packetRouter.route(message, from: source.id) else { continue }
                    outputWords.append(routed.word)
                    activity.append(activityRow(
                        for: routed, words: [], from: source, direction: .outgoing, time: received
                    ))
                } else {
                    outputWords.append(contentsOf: messageWords)
                    activity.append(MIDIActivity(
                        timestamp: received, direction: .outgoing, deviceID: source.id, deviceName: source.name,
                        type: incoming.type, channel: nil, detail: incoming.detail
                    ))
                }
            }
            // Each incoming event packet gets a separate output list to preserve SysEx packet boundaries.
            if outputWords.isEmpty || transmit(outputWords, timestamp: packet.timestamp) {
                router = packetRouter
            } else {
                activity.removeAll { $0.direction == .outgoing }
            }
            record(activity)
        }
    }

    private func learn(from message: MIDIMessage, deviceID: String) {
        guard let request = learnRequest else { return }
        switch message.type {
        case .note:
            guard !message.isNoteRelease else { return }
        case .controlChange, .programChange:
            break
        default:
            return
        }

        learnRequest = nil
        let input = MIDILearnedInput(
            deviceID: deviceID, type: message.type, channel: message.channel, number: message.number
        )
        DispatchQueue.main.async { request.onLearn(request.id, input) }
    }

    // UMP size is defined by the leading message-type nibble, including reserved types.
    private static let umpWordCounts = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    private func transmit(_ words: [UInt32], timestamp: MIDITimeStamp) -> Bool {
        guard output != 0, !words.isEmpty else { return false }
        let list = eventListStorage
        let firstPacket = MIDIEventListInit(list, ._1_0)
        let time = timestamp == 0 ? mach_absolute_time() : timestamp
        _ = words.withUnsafeBufferPointer { buffer in
            MIDIEventListAdd(list, Self.eventListCapacity, firstPacket, time, buffer.count, buffer.baseAddress!)
        }
        // Swift imports MIDIEventListAdd's pointer as non-optional even on an add failure.
        guard list.pointee.numPackets != 0 else {
            report("MIDI-105", "The outgoing MIDI packet exceeded CoreMIDI’s size limit")
            return false
        }
        let status = MIDIReceivedEventList(output, list)
        if status != noErr {
            report("MIDI-105", "Couldn’t send MIDI to the virtual output", status: status)
        }
        return status == noErr
    }

    private func releaseConnectedNotes() {
        for source in connections.values {
            releaseNotes(from: source.input)
        }
    }

    private func releaseNotes(from source: MIDIInputSource) {
        let releases = router.releaseNotes(from: source.id) + router.releaseSustain(from: source.id)
        let time = Date()
        for start in stride(from: 0, to: releases.count, by: 256) {
            let batch = releases[start..<min(start + 256, releases.count)]
            guard transmit(batch.map(\.word), timestamp: 0) else { continue }
            record(batch.map { activityRow(for: $0, words: [], from: source, direction: .outgoing, time: time) })
        }
    }

    private func activityRow(
        for message: MIDIMessage?, words: ArraySlice<UInt32>, from source: MIDIInputSource,
        direction: MIDIActivity.Direction, time: Date
    ) -> MIDIActivity {
        let detail: String
        if let message {
            switch (message.number, message.value) {
            case let (number?, value?): detail = "\(number) · \(value)"
            case let (number?, nil): detail = "\(number)"
            case let (nil, value?): detail = "\(value)"
            case (nil, nil): detail = ""
            }
        } else {
            detail = words.map { String(format: "%08X", $0) }.joined(separator: " ")
        }
        return MIDIActivity(
            timestamp: time, direction: direction, deviceID: source.id, deviceName: source.name,
            type: message?.name ?? Self.otherMessageType(words.first), channel: message?.channel, detail: detail
        )
    }

    private static func otherMessageType(_ word: UInt32?) -> String {
        guard let word else { return "Other" }
        switch word >> 28 {
        case 0: return "Utility"
        case 1:
            switch (word >> 16) & 0xff {
            case 0xf1: return "Time Code"
            case 0xf2: return "Song Position"
            case 0xf3: return "Song Select"
            case 0xf6: return "Tune Request"
            case 0xf8: return "Timing Clock"
            case 0xfa: return "Start"
            case 0xfb: return "Continue"
            case 0xfc: return "Stop"
            case 0xfe: return "Active Sensing"
            case 0xff: return "System Reset"
            default: return "System"
            }
        case 3: return "System Exclusive"
        case 4: return "MIDI 2 Channel Voice"
        case 5: return "128-bit Data"
        case 13: return "Flex Data"
        case 15: return "Stream"
        default: return "Other"
        }
    }

    private func publishSources(_ updated: [MIDIInputSource]) {
        guard updated != sources else { return }
        sources = updated
        DispatchQueue.main.async { [onSources] in onSources(updated) }
    }

    private func publishStatus(_ ready: Bool) {
        DispatchQueue.main.async { [onStatus] in onStatus(ready) }
    }

    private func record(_ activity: [MIDIActivity]) {
        guard !activity.isEmpty else { return }
        monitorBatch.append(contentsOf: activity)
        let overflow = monitorBatch.count - Self.monitorBatchLimit
        if overflow > 0 { monitorBatch.removeFirst(overflow) }
        guard !monitorDeliveryScheduled else { return }
        monitorDeliveryScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(32)) { [weak self] in
            guard let self else { return }
            let batch = self.monitorBatch
            self.monitorBatch.removeAll(keepingCapacity: true)
            self.monitorDeliveryScheduled = false
            DispatchQueue.main.async { [onActivity = self.onActivity] in onActivity(batch) }
        }
    }

    private func report(_ code: String, _ description: String, status: OSStatus? = nil) {
        let message = status.map { "\(description) (CoreMIDI \($0))." } ?? "\(description)."
        let now = Date()
        if let lastError, lastError.code == code, lastError.message == message,
           now.timeIntervalSince(lastError.time) < 2 { return }
        lastError = (code, message, now)
        DispatchQueue.main.async { [onError] in onError(MIDITransportError(code: code, message: message)) }
    }
}
