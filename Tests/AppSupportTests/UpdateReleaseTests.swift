import XCTest
@testable import AppSupport

final class UpdateReleaseTests: XCTestCase {
    func testVersionParsingAndOrdering() {
        XCTAssertEqual(AppVersion("v1.3.0")?.components, [1, 3, 0])
        XCTAssertEqual(AppVersion("2.0-beta.1")?.components, [2, 0])
        XCTAssertNil(AppVersion("Dev"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertTrue(AppVersion("1.2.0")! < AppVersion("1.10")!)
        XCTAssertTrue(AppVersion("1.2")! == AppVersion("1.2.0")!)
        XCTAssertFalse(AppVersion("1.3.0")! < AppVersion("1.2.9")!)
    }

    func testParsesLatestReleaseAndPrefersAppZip() throws {
        let json = """
        {"tag_name":"v1.3.0","html_url":"https://github.com/o/r/releases/tag/v1.3.0","body":" Notes \\n",
         "draft":false,"prerelease":false,
         "assets":[{"name":"Source.zip","browser_download_url":"https://example.com/source.zip"},
                   {"name":"MIDI-Reconfigure.zip","browser_download_url":"https://example.com/app.zip"}]}
        """
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))
        XCTAssertEqual(release.version.description, "1.3.0")
        XCTAssertEqual(release.notes, "Notes")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://example.com/app.zip")
        XCTAssertTrue(release.isNewer(than: "1.2.0"))
        XCTAssertFalse(release.isNewer(than: "1.3"))
        XCTAssertFalse(release.isNewer(than: "1.4.0"))
        XCTAssertTrue(release.isNewer(than: "Dev"))
    }

    func testIgnoresPrereleasesAndNonVersionTags() throws {
        let prerelease = #"{"tag_name":"v2.0.0","prerelease":true,"assets":[]}"#
        XCTAssertNil(try ReleaseInfo.parse(Data(prerelease.utf8)))
        let named = #"{"tag_name":"nightly","assets":[]}"#
        XCTAssertNil(try ReleaseInfo.parse(Data(named.utf8)))
        let noAsset = #"{"tag_name":"1.4.0"}"#
        XCTAssertNil(try ReleaseInfo.parse(Data(noAsset.utf8))?.downloadURL)
        XCTAssertThrowsError(try ReleaseInfo.parse(Data("not json".utf8)))
    }

    func testInstallScriptRestoresOnFailedMove() {
        XCTAssertTrue(UpdateInstallScript.contents.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(UpdateInstallScript.contents.contains(#"mv "$backup" "$target""#))
    }
}
