import XCTest
@testable import DeviceDiagnosticSuite

final class AnalysisTests: XCTestCase {
    func testCellularEventAndRedaction() {
        let line = "2031-02-03 16:10:00 CommCenter registration lost for +1 415 555 0100"
        let event = Analysis.event(from: line, source: "test")
        XCTAssertEqual(event?.kind, .cellular)
        XCTAssertFalse(event?.detail.contains("415 555 0100") ?? true)
        XCTAssertNotNil(event?.date)
    }

    func testUnrelatedLineIsNotEvent() {
        XCTAssertNil(Analysis.event(from: "Hello from an unrelated app", source: "test"))
    }

    func testLiveLogTimestampUsesCurrentYear() {
        let date = Analysis.date(in: "Feb 03 07:01:02.123456 CommCenter(123): message")
        XCTAssertEqual(Calendar.current.component(.year, from: date ?? .distantPast), Calendar.current.component(.year, from: Date()))
    }

    func testFullDeviceIDIsRedacted() {
        let result = Analysis.redact("connected:" + "11111111-" + String(repeating: "2", count: 16))
        XCTAssertEqual(result, "connected:[device id]")
    }
}
