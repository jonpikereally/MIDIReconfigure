import XCTest
@testable import MIDIRouting

final class MIDIFunctionEngineTests: XCTestCase {
    private func word(_ status: UInt32, channel: Int, _ data1: UInt32, _ data2: UInt32 = 0) -> MIDIMessage {
        MIDIMessage(word: 0x2000_0000 | (status << 20) | (UInt32(channel - 1) << 16) | (data1 << 8) | data2)!
    }

    private func engine(_ functions: [MIDIOutputFunction], triggers: [MIDITrigger?]) -> MIDIFunctionEngine {
        var engine = MIDIFunctionEngine()
        engine.functions = functions
        engine.mappings = zip(functions, triggers).map { MIDIFunctionMapping(functionID: $0.id, trigger: $1) }
        return engine
    }

    func testFixedControlChangeFiresOnPressAndConsumesRelease() {
        let play = MIDIOutputFunction(
            name: "Play", output: MIDIFunctionOutput(type: .controlChange, channel: 16, number: 20, value: 127)
        )
        var engine = engine([play], triggers: [MIDITrigger(deviceID: "mc6", channel: 1, type: .controlChange, number: 64)])

        let press = engine.handle(word(0xB, channel: 1, 64, 127), from: "mc6")
        XCTAssertEqual(press?.map(\.message), [.controlChange(channel: 16, number: 20, value: 127)])
        XCTAssertEqual(press?.first?.destinationID, nil)
        XCTAssertEqual(engine.handle(word(0xB, channel: 1, 64, 0), from: "mc6"), [])
        XCTAssertNil(engine.handle(word(0xB, channel: 1, 64, 127), from: "keys"))
        XCTAssertNil(engine.handle(word(0xB, channel: 2, 64, 127), from: "mc6"))
        XCTAssertNil(engine.handle(word(0xB, channel: 1, 65, 127), from: "mc6"))
    }

    func testFollowValueControlChangePassesEveryValue() {
        let sweep = MIDIOutputFunction(
            name: "Sweep", output: MIDIFunctionOutput(type: .controlChange, channel: 2, number: 74, value: nil)
        )
        var engine = engine([sweep], triggers: [MIDITrigger(type: .controlChange, number: 11)])

        XCTAssertEqual(engine.handle(word(0xB, channel: 5, 11, 90), from: "x")?.map(\.message),
                       [.controlChange(channel: 2, number: 74, value: 90)])
        XCTAssertEqual(engine.handle(word(0xB, channel: 5, 11, 0), from: "x")?.map(\.message),
                       [.controlChange(channel: 2, number: 74, value: 0)])
    }

    func testNoteTriggerHoldsNoteOutputUntilRelease() {
        let cue = MIDIOutputFunction(
            name: "Cue", output: MIDIFunctionOutput(type: .note, channel: 3, number: 60, value: nil),
            destinationID: "qc"
        )
        var engine = engine([cue], triggers: [MIDITrigger(type: .note, number: 36)])

        let press = engine.handle(word(0x9, channel: 1, 36, 80), from: "pads")
        XCTAssertEqual(press?.map(\.message), [.noteOn(channel: 3, number: 60, velocity: 80)])
        XCTAssertEqual(press?.first?.destinationID, "qc")

        // A library edit before the release must not strand the sounding note.
        engine.functions = []
        let release = engine.handle(word(0x8, channel: 1, 36, 0), from: "pads")
        XCTAssertEqual(release?.map(\.message), [.noteOff(channel: 3, number: 60)])
        XCTAssertEqual(release?.first?.destinationID, "qc")
        XCTAssertNil(engine.handle(word(0x8, channel: 1, 36, 0), from: "pads"))
    }

    func testControlChangeTriggerSendsCompleteNote() {
        let hit = MIDIOutputFunction(name: "Hit", output: MIDIFunctionOutput(type: .note, channel: 10, number: 38, value: 100))
        var engine = engine([hit], triggers: [MIDITrigger(type: .controlChange, number: 80)])

        XCTAssertEqual(engine.handle(word(0xB, channel: 1, 80, 127), from: "x")?.map(\.message),
                       [.noteOn(channel: 10, number: 38, velocity: 100), .noteOff(channel: 10, number: 38)])
        XCTAssertEqual(engine.handle(word(0xB, channel: 1, 80, 0), from: "x"), [])
    }

    func testProgramChangeOutputAndReleaseOfHeldNotes() {
        let scene = MIDIOutputFunction(name: "Scene", output: MIDIFunctionOutput(type: .programChange, channel: 1, number: 5))
        let pad = MIDIOutputFunction(name: "Pad", output: MIDIFunctionOutput(type: .note, channel: 1, number: 48, value: 90))
        var engine = engine([scene, pad], triggers: [
            MIDITrigger(type: .programChange, number: 2),
            MIDITrigger(deviceID: "pads", type: .note)
        ])

        XCTAssertEqual(engine.handle(word(0xC, channel: 1, 2), from: "x")?.map(\.message),
                       [.programChange(channel: 1, program: 5)])
        _ = engine.handle(word(0x9, channel: 1, 40, 70), from: "pads")
        XCTAssertEqual(engine.releaseNotes(from: "other"), [])
        XCTAssertEqual(engine.releaseNotes(from: "pads").map(\.message), [.noteOff(channel: 1, number: 48)])
        XCTAssertEqual(engine.releaseNotes(), [])
    }

    func testUnmappedDisabledAndMissingFunctionsPassThrough() {
        let play = MIDIOutputFunction(name: "Play", output: MIDIFunctionOutput(type: .controlChange, channel: 1, number: 1))
        var engine = MIDIFunctionEngine()
        engine.functions = [play]
        engine.mappings = [
            MIDIFunctionMapping(functionID: play.id, trigger: nil),
            MIDIFunctionMapping(functionID: play.id, isEnabled: false, trigger: MIDITrigger(type: .note)),
            MIDIFunctionMapping(functionID: UUID(), trigger: MIDITrigger(type: .note))
        ]
        XCTAssertNil(engine.handle(word(0x9, channel: 1, 36, 80), from: "x"))
    }

    func testOutputValidationAndConstructors() {
        XCTAssertTrue(MIDIFunctionOutput(type: .programChange, channel: 16, number: 127, value: 0).isValid)
        XCTAssertFalse(MIDIFunctionOutput(type: .note, channel: 1, number: 1, value: 0).isValid)
        XCTAssertFalse(MIDIFunctionOutput(type: .controlChange, channel: 17, number: 1).isValid)
        XCTAssertFalse(MIDIFunctionOutput(type: .controlChange, channel: 1, number: 128).isValid)
        XCTAssertEqual(MIDIMessage.controlChange(channel: 16, number: 20, value: 127).word, 0x20BF_147F)
        XCTAssertEqual(MIDIMessage.programChange(channel: 2, program: 5).word, 0x20C1_0500)
        XCTAssertFalse(MIDIMessage.noteOn(channel: 1, number: 60, velocity: 0).isNoteRelease)
        XCTAssertTrue(MIDIOutputFunction.starterLibrary.allSatisfy { $0.needsVerification && $0.output.isValid })
    }

    func testHoldingNoteReportsOnlyOwnPresses() {
        let pad = MIDIOutputFunction(name: "Pad", output: MIDIFunctionOutput(type: .note, channel: 1, number: 48, value: 90))
        var engine = engine([pad], triggers: [MIDITrigger(type: .note, number: 36)])
        var router = MIDIRouter()
        _ = router.route(word(0x9, channel: 1, 40, 70), from: "keys")
        _ = engine.handle(word(0x9, channel: 1, 36, 70), from: "keys")

        XCTAssertTrue(router.isHoldingNote(word(0x8, channel: 1, 40), from: "keys"))
        XCTAssertFalse(router.isHoldingNote(word(0x8, channel: 1, 36), from: "keys"))
        XCTAssertTrue(engine.isHoldingNote(word(0x8, channel: 1, 36), from: "keys"))
        XCTAssertFalse(engine.isHoldingNote(word(0x8, channel: 1, 36), from: "other"))
    }

    func testTestEmissionsUseDestination() {
        let tuner = MIDIOutputFunction(
            name: "Tuner", output: MIDIFunctionOutput(type: .controlChange, channel: 1, number: 45, value: nil),
            destinationID: "qc"
        )
        let emissions = MIDIFunctionEngine.testEmissions(for: tuner)
        XCTAssertEqual(emissions.map(\.message), [.controlChange(channel: 1, number: 45, value: 127)])
        XCTAssertEqual(emissions.map(\.destinationID), ["qc"])
    }
}
