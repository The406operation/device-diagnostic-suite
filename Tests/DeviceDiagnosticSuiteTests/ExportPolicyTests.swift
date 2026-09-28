import XCTest
@testable import DeviceDiagnosticSuite

final class ExportPolicyTests: XCTestCase {
    let time = ISO8601DateFormatter().date(from: "2031-02-03T12:00:00Z")!
    // Every value below is synthetic. Reserved contact examples are never real credentials.
    var canaries: [String] {
        ["SYNTHETIC_PERSON", "SYNTHETIC_DEVICE_NAME", "/" + "Users/fixture-owner/private-data",
         "/" + "home/fixture-owner/private-data", "fixture-user" + "@invalid.example",
         "+1 " + "202 555 0107", "11111111-" + String(repeating: "2", count: 16), "SYNTHETIC_SERIAL",
         String(repeating: "1", count: 15), String(repeating: "2", count: 32), String(repeating: "3", count: 20),
         "SYNTHETIC_CARRIER_ACCOUNT", "SYNTHETIC_SSID", "02:00:00:00:00:07",
         "192.0.2.7", "2001:db8::7", "45.123456,-110.123456", "SYNTHETIC_PAIRING_RECORD",
         "SYNTHETIC_SIGNING_IDENTITY", "SYNTHETIC_PROVISIONING", "-----BEGIN " + "PRIVATE KEY-----",
         "ghp_" + String(repeating: "X", count: 30), "SYNTHETIC_PASSWORD", "SYNTHETIC_ACCOUNT"]
    }
    var sensitiveFields: [String] {
        ["ownerName", "deviceName", "path", "machinePath", "email", "phoneNumber", "deviceIdentifier",
         "serialNumber", "IMEI", "EID", "ICCID", "carrierAccount", "SSID", "BSSID", "ipv4", "ipv6",
         "location", "pairingRecord", "certificate", "provisioningProfile", "privateKey", "apiToken", "password", "appleAccount"]
    }
    func poisonedRun() -> CampaignRun {
        var run = CampaignRun(role: .primary, deviceID: canaries[6], context: MatchedContext())
        let text = canaries.joined(separator: " | ")
        run.startedAt = time
        run.status = text; run.context.location = text; run.context.notes = text
        run.observations = zip(sensitiveFields, canaries).map {
            FieldObservation(field: $0.0, value: $0.1, basis: .device, source: text, observedAt: time, note: text)
        }
        // Poison approved values, source labels, and every free-text channel too.
        run.observations += ExportPolicy.approvedFields.map {
            FieldObservation(field: $0, value: text, basis: .user, source: text, observedAt: time, note: text)
        }
        run.events = [CampaignEvent(at: time, signal: .registrationLoss, summary: text, source: text)]
        run.markers = [ActionMarker(kind: .sos, at: time, outcome: text, note: text, role: .primary)]
        run.errors = [text]
        run.evidence = [RawEvidence(relativePath: text, sha256: text, bytes: 10, source: text)]
        return run
    }
    func assertNoCanary(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let text = String(decoding: data, as: UTF8.self)
        for value in canaries { XCTAssertFalse(text.contains(value), "Sensitive class survived", file: file, line: line) }
        XCTAssertNoThrow(try ExportPolicy.validateShareSafe(data), file: file, line: line)
    }
    func testCampaignShareSafeOmitsAllDefinedSensitiveClasses() throws {
        let run = poisonedRun()
        assertNoCanary(try ExportPolicy.campaignData(run, mode: .shareSafe, control: run))
    }
    func testSessionShareSafeOmitsAllFreeTextAndIdentifiers() throws {
        let text = canaries.joined(separator: " | ")
        var device = DeviceSnapshot(); device.identifier = text; device.name = text
        device.productType = text; device.ios = text; device.build = text; device.baseband = text
        var session = CaptureSession(kind: .sos, title: text, device: device)
        session.startedAt = time; session.note = text; session.importedFiles = [text]
        session.events = [DiagnosticEvent(date: time, kind: .cellular, summary: text, source: text, detail: text)]
        assertNoCanary(try ExportPolicy.sessionData(session, mode: .shareSafe))
        let raw = try ExportPolicy.sessionData(session, mode: .privateDiagnostic)
        XCTAssertTrue(String(decoding: raw, as: UTF8.self).contains(canaries[0]))
    }
    func testValidatorRejectsSensitiveValues() {
        for index in [2, 3, 4, 5, 6, 8, 9, 10, 13, 14, 20, 21] {
            XCTAssertThrowsError(try ExportPolicy.validateShareSafe(Data(canaries[index].utf8)), "Pattern class index \(index)")
        }
        XCTAssertNoThrow(try ExportPolicy.validateShareSafe(Data("2031-02-03T12:00:00Z".utf8)))
    }
    func testApprovedFactsAndComparisonSurvive() throws {
        var run = CampaignRun(role: .primary, deviceID: "SYNTHETIC", context: MatchedContext())
        run.startedAt = time
        run.observations = [FieldObservation(field: "iOS", value: "99.1", basis: .device, source: "synthetic", observedAt: time)]
        let data = try ExportPolicy.campaignData(run, mode: .shareSafe, control: run)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let observations = try XCTUnwrap(json["observations"] as? [[String: String]])
        XCTAssertEqual(observations.first?["value"], "99.1")
        let comparison = try XCTUnwrap(json["comparison"] as? [[String: String]])
        XCTAssertEqual(comparison.first { $0["field"] == "iOS" }?["result"], "Matches")
    }
    func testActualBundlesKeepPrivateRawEvidenceAndExcludeItFromShareSafe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("run/raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let secret = canaries.joined(separator: " | ")
        try secret.write(to: raw.appendingPathComponent("synthetic.txt"), atomically: true, encoding: .utf8)
        for mode in ExportMode.allCases {
            let archive = root.appendingPathComponent(mode == .shareSafe ? "safe.zip" : "private.zip")
            try await ExportPolicy.createCampaignBundle(poisonedRun(), mode: mode, runFolder: raw.deletingLastPathComponent(), destination: archive)
            let (code, listing) = await Command.run("/usr/bin/unzip", ["-Z1", archive.path])
            XCTAssertEqual(code, 0)
            let (_, json) = await Command.run("/usr/bin/unzip", ["-p", archive.path, "run.json"])
            if mode == .shareSafe {
                XCTAssertFalse(listing.contains("private-evidence")); assertNoCanary(Data(json.utf8))
                for member in listing.split(separator: "\n").map(String.init).filter({ !$0.hasSuffix("/") }) {
                    let (_, text) = await Command.run("/usr/bin/unzip", ["-p", archive.path, member])
                    assertNoCanary(Data(text.utf8))
                }
            } else {
                XCTAssertTrue(listing.contains("private-evidence/raw/synthetic.txt"))
                XCTAssertTrue(json.contains(canaries[0]))
                let (_, content) = await Command.run("/usr/bin/unzip", ["-p", archive.path, "private-evidence/raw/synthetic.txt"])
                XCTAssertEqual(content, secret)
            }
        }
    }
    func testSessionShareSafeCSVAndReportContainNoCanary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = canaries.joined(separator: " | ")
        var session = CaptureSession(kind: .sos, title: text)
        session.startedAt = time
        session.events = [DiagnosticEvent(date: time, kind: .cellular, summary: text, source: text, detail: text)]
        let archive = root.appendingPathComponent("safe-session.zip")
        try await ExportPolicy.createSessionBundle(session, mode: .shareSafe, destination: archive)
        let (_, listing) = await Command.run("/usr/bin/unzip", ["-Z1", archive.path])
        XCTAssertTrue(listing.contains("events.csv"))
        for member in listing.split(separator: "\n").map(String.init).filter({ !$0.hasSuffix("/") }) {
            let (_, text) = await Command.run("/usr/bin/unzip", ["-p", archive.path, member])
            assertNoCanary(Data(text.utf8))
        }
    }
    func testPrivateExportRejectsImportedSymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "/dev/null")
        do {
            try await ExportPolicy.createCampaignBundle(poisonedRun(), mode: .privateDiagnostic, runFolder: root, destination: root.appendingPathComponent("output.zip"))
            XCTFail("Link must not be copied")
        } catch ExportPolicy.ExportError.symbolicLink { }
    }
}
