import XCTest
@testable import DeviceDiagnosticSuite

final class CampaignAnalysisTests: XCTestCase {
    func testUntimedLogDoesNotReceiveInventedTimestamp() {
        XCTAssertTrue(CampaignAnalysis.events(from: "baseband reset detected", source: "test").isEmpty)
    }

    func testSavedLogUsesReferenceYearAndTimeZone() {
        let reference = ISO8601DateFormatter().date(from: "2031-02-03T12:00:00Z")!
        let result = Analysis.date(in: "Feb 03 06:00:05 emergency only", referenceDate: reference,
                                   timeZone: TimeZone(secondsFromGMT: -21600)!)
        let expected = ISO8601DateFormatter().date(from: "2031-02-03T12:00:05Z")!
        XCTAssertEqual(result, expected)
    }

    func testConditionalResetTextIsNotAnObservedReset() {
        XCTAssertNil(CampaignAnalysis.signal(in: "registration hints will re-send the next airplane mode toggle or baseband reset"))
        XCTAssertNil(CampaignAnalysis.signal(in: "Deferring baseband resets (call=true)"))
        XCTAssertEqual(CampaignAnalysis.signal(in: "baseband reset detected"), .modemReset)
    }

    func testBaselineWithoutSOSDoesNotIdentifyFirstFailure() {
        var run = CampaignRun(role: .primary, deviceID: "local-test", context: MatchedContext())
        run.events = [CampaignEvent(at: Date(), signal: .networkPath,
                                    summary: "interface changed", source: "test")]
        let result = CampaignAnalysis.assess(primary: run, control: nil)
        XCTAssertEqual(result.confidence, "None for fault isolation")
        XCTAssertTrue(result.inference.contains("cannot identify the first failed subsystem"))
    }

    func testLastNormalRegistrationAnchorsSOSSequence() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        var run = CampaignRun(role: .primary, deviceID: "local-test", context: MatchedContext())
        run.markers = [ActionMarker(kind: .sos, at: anchor.addingTimeInterval(70), outcome: "SOS", note: "")]
        run.events = [
            CampaignEvent(at: anchor.addingTimeInterval(-40), signal: .imsLoss, summary: "Transient IMS", source: "test"),
            CampaignEvent(at: anchor, signal: .registeredService, summary: "Home", source: "test"),
            CampaignEvent(at: anchor.addingTimeInterval(3), signal: .registrationLoss, summary: "Emergency only", source: "test"),
            CampaignEvent(at: anchor.addingTimeInterval(46), signal: .imsLoss, summary: "IMS lost", source: "test"),
            CampaignEvent(at: anchor.addingTimeInterval(47), signal: .dataLoss, summary: "Cellular path failed", source: "test")
        ]
        let result = CampaignAnalysis.assess(primary: run, control: nil)
        XCTAssertTrue(result.inference.contains("Registration lost or emergency only"))
        XCTAssertEqual(result.confidence, "Moderate for event order; low for cause")
    }

    func testIMSImpairmentBeforeNormalRegistrationRemainsContradictoryEvidence() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        var run = CampaignRun(role: .primary, deviceID: "local-test", context: MatchedContext())
        run.markers = [ActionMarker(kind: .sos, at: anchor.addingTimeInterval(50), outcome: "SOS", note: "")]
        run.events = [
            CampaignEvent(at: anchor.addingTimeInterval(-0.046), signal: .imsLoss, summary: "IMS not registered", source: "test"),
            CampaignEvent(at: anchor, signal: .registeredService, summary: "Home", source: "test"),
            CampaignEvent(at: anchor.addingTimeInterval(4), signal: .registrationLoss, summary: "Emergency only", source: "test")
        ]
        let result = CampaignAnalysis.assess(primary: run, control: nil)
        XCTAssertTrue(result.contradictoryEvidence.contains { $0.contains("does not establish that IMS recovered") })
        XCTAssertTrue(result.inference.contains("Earlier impairment can remain active"))
        XCTAssertTrue(result.nextTest.contains("not authorized"))
    }

    func testLatestObservationUsesTimestampAcrossImportedSources() {
        var run = CampaignRun(role: .primary, deviceID: "local-test", context: MatchedContext())
        run.observations = [
            FieldObservation(field: "registrationState", value: "Emergency only", basis: .log,
                             source: "sysdiagnose", observedAt: Date(timeIntervalSince1970: 2000)),
            FieldObservation(field: "registrationState", value: "Home", basis: .log,
                             source: "older baseline imported later", observedAt: Date(timeIntervalSince1970: 1000))
        ]
        XCTAssertEqual(CampaignAnalysis.observation("registrationState", in: run)?.value, "Emergency only")
    }

}
