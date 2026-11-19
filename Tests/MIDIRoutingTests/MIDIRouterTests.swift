import XCTest
@testable import MIDIRouting

final class MIDIRouterTests: XCTestCase {
    func testFirstEnabledRuleMatchesDeviceChannelTypeAndNumber() {
        var router = MIDIRouter()
        router.defaultOutputChannel = 16
        router.rules = [
            MIDIRule(isEnabled: false, drop: true),
            MIDIRule(deviceID: "other", drop: true),
            MIDIRule(inputChannel: 3, drop: true),
            MIDIRule(type: .programChange, drop: true),
            MIDIRule(type: .controlChange, inputNumber: 12, drop: true),
            MIDIRule(deviceID: "keys", inputChannel: 2, type: .controlChange, inputNumber: 7,
                     outputChannel: 5, outputNumber: 10, invertCC: true),
            MIDIRule(drop: true),
        ]

        let output = router.route(message(0xB, channel: 2, 7, 27, group: 2), from: "keys")
        XCTAssertEqual(output, message(0xB, channel: 5, 10, 100, group: 2))
        XCTAssertNil(router.route(message(0xB, channel: 2, 8, 27), from: "keys"))
    }

    func testDefaultChannelAndProgramChangeRemap() {
        var router = MIDIRouter()
        router.defaultOutputChannel = 16
        router.rules = [MIDIRule(type: .programChange, inputNumber: 3, outputNumber: 42, invertCC: true)]

        let program = router.route(message(0xC, channel: 1, 3), from: "keys")
        XCTAssertEqual(program, message(0xC, channel: 16, 42))
        XCTAssertEqual(router.route(message(0xE, channel: 4, 0, 64), from: "keys"),
                       message(0xE, channel: 16, 0, 64))
        XCTAssertEqual(program?.value, nil)
        XCTAssertEqual(program?.number, 42)
    }

    func testControlChangeInversionAtBothLimits() {
        var router = MIDIRouter()
        router.rules = [MIDIRule(type: .controlChange, invertCC: true)]

        XCTAssertEqual(router.route(message(0xB, channel: 1, 7, 0), from: "keys")?.value, 127)
        XCTAssertEqual(router.route(message(0xB, channel: 1, 7, 127), from: "keys")?.value, 0)
    }

    func testNoteReleasesFollowPriorAssignmentsAcrossRuleEditsInPressOrder() {
        var router = MIDIRouter()
        router.rules = [MIDIRule(type: .note, outputChannel: 2, outputNumber: 64)]
        let press = message(0x9, channel: 1, 60, 90)
        XCTAssertEqual(router.route(press, from: "keys"), message(0x9, channel: 2, 64, 90))

        router.rules = [MIDIRule(type: .note, outputChannel: 3, outputNumber: 72)]
        XCTAssertEqual(router.route(press, from: "keys"), message(0x9, channel: 3, 72, 90))
        XCTAssertEqual(router.route(message(0x9, channel: 1, 60, 0), from: "keys"),
                       message(0x9, channel: 2, 64, 0))

        router.rules = [MIDIRule(type: .note, drop: true)]
        XCTAssertEqual(router.route(message(0x8, channel: 1, 60, 34), from: "keys"),
                       message(0x8, channel: 3, 72, 34))
        XCTAssertEqual(router.releaseNotes(), [])
    }

    func testDroppedPressStillSuppressesItsReleaseAfterRuleRemoval() {
        var router = MIDIRouter()
        router.rules = [MIDIRule(drop: true)]
        let press = message(0x9, channel: 1, 60, 90)
        let release = message(0x8, channel: 1, 60, 0)
        XCTAssertNil(router.route(press, from: "keys"))

        router.rules = [MIDIRule(outputChannel: 4)]
        XCTAssertEqual(router.route(press, from: "keys"), message(0x9, channel: 4, 60, 90))
        XCTAssertNil(router.route(release, from: "keys"))
        XCTAssertEqual(router.route(release, from: "keys"), message(0x8, channel: 4, 60, 0))
        XCTAssertEqual(router.releaseNotes(), [])
    }

    func testDisconnectReleasesOnlyThatDevicesMappedNotesAndPreservesGroups() {
        var router = MIDIRouter()
        router.rules = [MIDIRule(deviceID: "keys", type: .note, outputChannel: 2, outputNumber: 64)]
        _ = router.route(message(0x9, channel: 1, 60, 90, group: 3), from: "keys")
        _ = router.route(message(0x9, channel: 1, 60, 90, group: 4), from: "keys")
        _ = router.route(message(0x9, channel: 1, 60, 90, group: 3), from: "pads")

        XCTAssertEqual(router.releaseNotes(from: "keys"), [
            message(0x8, channel: 2, 64, 0, group: 3),
            message(0x8, channel: 2, 64, 0, group: 4),
        ])
        XCTAssertEqual(router.releaseNotes(), [message(0x8, channel: 1, 60, 0, group: 3)])
        XCTAssertEqual(router.releaseNotes(), [])
    }

    func testAllNotesOffClearsAssignmentsOnlyForItsOutputGroupAndChannel() {
        var router = MIDIRouter()
        let press = message(0x9, channel: 1, 60, 90, group: 3)
        let release = message(0x8, channel: 1, 60, 0, group: 3)
        _ = router.route(press, from: "keys")
        _ = router.route(press, from: "pads")
        _ = router.route(message(0x9, channel: 1, 60, 90, group: 4), from: "keys")
        _ = router.route(message(0x9, channel: 2, 60, 90, group: 3), from: "keys")
        _ = router.route(message(0xB, channel: 1, 123, 0, group: 3), from: "keys")

        router.rules = [MIDIRule(type: .note, outputChannel: 10)]
        XCTAssertEqual(router.route(press, from: "keys"), message(0x9, channel: 10, 60, 90, group: 3))
        XCTAssertEqual(router.route(release, from: "keys"), message(0x8, channel: 10, 60, 0, group: 3))
        XCTAssertEqual(router.releaseNotes(), [
            message(0x8, channel: 2, 60, 0, group: 3),
            message(0x8, channel: 1, 60, 0, group: 4),
        ])
    }

    func testAllSoundOffWithNonzeroValuePreservesNoteAssignments() {
        var router = MIDIRouter()
        router.defaultOutputChannel = 4
        _ = router.route(message(0x9, channel: 1, 60, 90), from: "keys")
        _ = router.route(message(0xB, channel: 1, 120, 127), from: "keys")

        router.defaultOutputChannel = 8
        XCTAssertEqual(router.route(message(0x8, channel: 1, 60), from: "keys"), message(0x8, channel: 4, 60))
    }

    func testDisconnectReleasesSustainOnItsMappedGroupAndChannel() {
        var router = MIDIRouter()
        router.rules = [MIDIRule(deviceID: "keys", type: .controlChange, inputNumber: 11,
                                 outputChannel: 8, outputNumber: 64, invertCC: true)]
        _ = router.route(message(0xB, channel: 3, 11, 0, group: 5), from: "keys")
        _ = router.route(message(0xB, channel: 2, 64, 64, group: 5), from: "pads")
        _ = router.route(message(0xB, channel: 3, 11, 127, group: 7), from: "keys")

        router.rules = []
        XCTAssertEqual(router.releaseSustain(from: "keys"), [message(0xB, channel: 8, 64, 0, group: 5)])
        XCTAssertEqual(router.releaseSustain(), [message(0xB, channel: 2, 64, 0, group: 5)])
        XCTAssertEqual(router.releaseSustain(), [])
    }

    func testMostRecentSustainOwnerCanReleaseSharedOutput() {
        var router = MIDIRouter()
        router.defaultOutputChannel = 5
        _ = router.route(message(0xB, channel: 1, 64, 127), from: "keys")
        _ = router.route(message(0xB, channel: 2, 64, 64), from: "pads")

        XCTAssertEqual(router.releaseSustain(from: "keys"), [])
        XCTAssertEqual(router.releaseSustain(from: "pads"), [message(0xB, channel: 5, 64, 0)])
    }

    func testPedalUpAndResetAllControllersClearSustainForTheirOutputs() {
        var router = MIDIRouter()
        _ = router.route(message(0xB, channel: 1, 64, 127), from: "keys")
        _ = router.route(message(0xB, channel: 2, 64, 127), from: "keys")
        _ = router.route(message(0xB, channel: 3, 64, 127), from: "keys")
        _ = router.route(message(0xB, channel: 1, 64, 63), from: "keys")
        _ = router.route(message(0xB, channel: 2, 121, 0), from: "other")
        _ = router.route(message(0xB, channel: 3, 121, 0, group: 2), from: "other")

        XCTAssertEqual(router.releaseSustain(), [message(0xB, channel: 3, 64, 0)])
    }

    func testDecodingAndInvalidOutputSettings() {
        XCTAssertNil(MIDIMessage(word: 0x4090_3C40))
        XCTAssertNil(MIDIMessage(word: 0x2090_3C80))
        XCTAssertEqual(message(0x9, channel: 1, 0, 0).name, "Note Off")
        XCTAssertEqual(message(0xD, channel: 1, 127).value, 127)
        XCTAssertEqual(message(0xE, channel: 1, 127, 127).value, 16_383)

        var router = MIDIRouter()
        router.rules = [MIDIRule(outputChannel: 17, outputNumber: -1)]
        let control = message(0xB, channel: 1, 9, 127)
        XCTAssertEqual(router.route(control, from: "keys"), control)
    }

    private func message(
        _ status: UInt32, channel: UInt32, _ firstByte: UInt32, _ secondByte: UInt32 = 0, group: UInt32 = 0
    ) -> MIDIMessage {
        let word = 0x2000_0000 | (group << 24) | (status << 20) | ((channel - 1) << 16)
            | (firstByte << 8) | secondByte
        return MIDIMessage(word: word)!
    }
}
