import XCTest
@testable import DeviceDiagnosticSuite

final class SyntheticFixtureTests: XCTestCase {
    func testParserTimelineAndFaultOrderUsingSyntheticFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "telephony", withExtension: "txt", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let events = CampaignAnalysis.events(from: text, source: "synthetic fixture", timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(events.count, 7)
        XCTAssertFalse(events.contains { $0.at == ISO8601DateFormatter().date(from: "2031-02-03T12:00:12Z") })
        var primary = CampaignRun(role: .primary, deviceID: "SYNTHETIC-PRIMARY", context: MatchedContext())
        primary.events = events
        primary.markers = [ActionMarker(kind: .sos, at: ISO8601DateFormatter().date(from: "2031-02-03T12:00:10Z")!, outcome: "Synthetic", note: "")]
        let result = CampaignAnalysis.assess(primary: primary, control: nil)
        XCTAssertTrue(result.inference.contains(FaultSignal.registrationLoss.rawValue))
        XCTAssertEqual(result.confidence, "Moderate for event order; low for cause")
        XCTAssertTrue(events.contains { $0.signal == .modemReset })
        XCTAssertTrue(events.contains { $0.signal == .networkReject })
    }
    func testPairedMetadataUsesSyntheticFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comparison", withExtension: "json", subdirectory: "Fixtures"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["synthetic"] as? Bool, true)
        let primary = try XCTUnwrap(json["primary"] as? [String: String])
        let control = try XCTUnwrap(json["control"] as? [String: String])
        XCTAssertEqual(primary, control)
        XCTAssertEqual(ExportPolicy.approvedValue(field: "productType", value: primary["productType"]!), "iPhone99,1")
    }
}
