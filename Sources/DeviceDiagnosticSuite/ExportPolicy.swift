import Foundation

enum ExportMode: String, CaseIterable, Identifiable {
    case privateDiagnostic = "Private Diagnostic Export"
    case shareSafe = "Share-Safe Export"
    var id: String { rawValue }
}

/// Share-safe output uses a closed schema. Free text never enters this schema.
enum ExportPolicy {
    static let approvedFields: Set<String> = [
        "productType", "hardwareModel", "iOS", "build", "modemFirmware", "carrierBundleVersion",
        "simState", "esimEmbedded", "carrierMCCMNC", "registrationState", "radioAccessTechnology",
        "imsVoiceRegistration", "serviceState", "signalBars", "fieldTestSNR", "batteryPercent",
        "crashReports", "archiveWindowLines", "deviceLogArchive", "sysdiagnose"
    ]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func approvedValue(field: String, value: String) -> String {
        let patterns: [String: String] = [
            "productType": #"^iPhone[0-9]{1,3},[0-9]{1,3}$"#,
            "hardwareModel": #"^[A-Z][0-9]{1,3}AP$"#,
            "iOS": #"^[0-9]{1,2}(\.[0-9]{1,2}){1,2}$"#,
            "build": #"^[0-9]{1,2}[A-Z][0-9]{1,4}[a-z]?$"#,
            "modemFirmware": #"^[0-9]{1,3}(\.[0-9]{1,3}){1,3}$"#,
            "carrierBundleVersion": #"^[0-9]{1,3}(\.[0-9]{1,3}){1,3}$"#,
            "carrierMCCMNC": #"^[0-9]{3}/[0-9]{2,3}$"#
        ]
        if let pattern = patterns[field], value.range(of: pattern, options: .regularExpression) != nil { return value }
        let choices: [String: Set<String>] = [
            "simState": ["kCTSIMSupportSIMStatusReady", "kCTSIMSupportSIMStatusNotReady", "kCTSIMSupportSIMStatusUnknown", "Ready", "Absent", "Unavailable"],
            "esimEmbedded": ["true", "false", "True", "False", "Unavailable"],
            "registrationState": ["kRegisteredHome", "kRegisteredRoaming", "kEmergencyOnly", "kSearching", "Unavailable"],
            "radioAccessTechnology": ["LTE", "5G NR", "5G", "3G", "Unknown", "Unavailable"],
            "imsVoiceRegistration": ["kRegistered", "kNotRegistered", "Unavailable"],
            "serviceState": ["SOS", "No service", "LTE", "5G", "5G+", "Unavailable"],
            "deviceLogArchive": ["Collected", "Unavailable"], "sysdiagnose": ["Collected", "Unavailable"]
        ]
        if choices[field]?.contains(value) == true { return value }
        let bounds: [String: ClosedRange<Double>] = ["signalBars": 0...5, "fieldTestSNR": -250...250,
            "batteryPercent": 0...100, "crashReports": 0...1_000_000, "archiveWindowLines": 0...100_000_000]
        if let range = bounds[field], value.range(of: #"^-?[0-9]{1,9}(\.[0-9]{1,3})?$"#, options: .regularExpression) != nil,
           let number = Double(value), range.contains(number) { return value }
        return "[omitted]"
    }

    static func safeRun(_ input: CampaignRun) -> CampaignRun {
        var run = input
        run.deviceID = "[device omitted]"
        run.context = MatchedContext()
        run.status = ["Complete", "Complete with limits", "In progress"].contains(run.status) ? run.status : "Recorded"
        run.errors = []
        run.observations = input.observations.filter { approvedFields.contains($0.field) }.map { item in
            var x = item
            x.value = approvedValue(field: item.field, value: item.value)
            x.source = "Normalized observation"
            x.note = ""
            return x
        }
        run.events = input.events.map { item in
            var x = item; x.summary = x.signal.rawValue; x.source = "Classified device log"; return x
        }
        run.markers = input.markers.map { item in
            var x = item; x.note = ""; x.outcome = "[omitted]"; return x
        }
        run.evidence = []
        return run
    }

    static func campaignData(_ input: CampaignRun, mode: ExportMode, control: CampaignRun? = nil) throws -> Data {
        if mode == .privateDiagnostic { return try encoder().encode(input) }
        let run = safeRun(input)
        let date = ISO8601DateFormatter()
        let assessment = CampaignAnalysis.assess(primary: run, control: control.map(safeRun))
        let assessmentObject = try JSONSerialization.jsonObject(with: encoder().encode(assessment))
        let object: [String: Any] = [
            "schema": "share-safe-campaign-v1", "role": run.role.rawValue,
            "startedAt": date.string(from: run.startedAt), "endedAt": run.endedAt.map(date.string) ?? "Not recorded",
            "status": run.status, "errorCount": input.errors.count,
            "observations": run.observations.map { ["field": $0.field, "value": $0.value,
                "basis": $0.basis.rawValue, "observedAt": date.string(from: $0.observedAt)] },
            "events": run.events.map { ["at": date.string(from: $0.at), "signal": $0.signal.rawValue] },
            "markers": run.markers.map { ["at": date.string(from: $0.at), "action": $0.kind.rawValue,
                "role": $0.role?.rawValue ?? "Unspecified"] },
            "evidenceFileCount": input.evidence.count, "assessment": assessmentObject,
            "comparison": approvedFields.sorted().map { field -> [String: String] in
                let a = CampaignAnalysis.observation(field, in: input)
                let b = CampaignAnalysis.observation(field, in: control)
                let known = a != nil && b != nil && a?.basis != .unavailable && b?.basis != .unavailable
                return ["field": field, "result": known ? (a?.value == b?.value ? "Matches" : "Differs") : "Unmeasured"]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try validateShareSafe(data)
        return data
    }

    static func sessionData(_ input: CaptureSession, mode: ExportMode) throws -> Data {
        if mode == .privateDiagnostic { return try encoder().encode(input) }
        let date = ISO8601DateFormatter()
        var device: [String: String] = [:]
        if let snapshot = input.device {
            for (field, value) in [("productType", snapshot.productType), ("iOS", snapshot.ios),
                                   ("build", snapshot.build), ("modemFirmware", snapshot.baseband)] {
                device[field] = approvedValue(field: field, value: value)
            }
        }
        let object: [String: Any] = ["schema": "share-safe-session-v1", "kind": input.kind.rawValue,
            "startedAt": date.string(from: input.startedAt), "endedAt": input.endedAt.map(date.string) ?? "Not recorded",
            "device": device, "logLines": max(0, input.logLines), "importedFileCount": input.importedFiles.count,
            "events": input.events.map { ["at": date.string(from: $0.date), "kind": $0.kind.rawValue] }]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try validateShareSafe(data)
        return data
    }

    enum ExportError: Error { case sensitivePattern, symbolicLink }
    static func validateShareSafe(_ data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"/Users/[^/\s]+|/home/[^/\s]+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"\b[0-9A-F]{8}-[0-9A-F]{16}\b|\b[0-9A-F]{40}\b|\b[0-9]{15,32}\b"#,
            #"\b(?:\+?[0-9]{1,3}[-. ])?(?:\([0-9]{3}\)|[0-9]{3})[-. ]?[0-9]{3}[-. ]?[0-9]{4}\b"#,
            #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b|\b(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\b"#,
            #"-----BEGIN [A-Z ]*(PRIVATE KEY|CERTIFICATE)-----|\b(ghp_|github_pat_|sk-|AKIA)[A-Z0-9_-]{12,}"#
        ]
        if patterns.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
            throw ExportError.sensitivePattern
        }
    }

    static func createCampaignBundle(_ run: CampaignRun, mode: ExportMode, runFolder: URL,
                                     destination: URL, control: CampaignRun? = nil) async throws {
        let assessment = CampaignAnalysis.assess(primary: run, control: control)
        let privateReport = "Observed facts\n" + assessment.observedFacts.joined(separator: "\n") +
            "\n\nInference\n" + assessment.inference + "\nConfidence: " + assessment.confidence +
            "\n\nContrary evidence\n" + assessment.contradictoryEvidence.joined(separator: "\n") +
            "\n\nUncertainty\n" + assessment.remainingUncertainty.joined(separator: "\n") +
            "\n\nNext test\n" + assessment.nextTest
        try await bundle(payload: campaignData(run, mode: mode, control: control), name: "run.json",
                         mode: mode, sourceFolder: mode == .privateDiagnostic ? runFolder : nil,
                         destination: destination, privateReport: privateReport)
    }

    static func createSessionBundle(_ session: CaptureSession, mode: ExportMode, destination: URL) async throws {
        try await bundle(payload: sessionData(session, mode: mode), name: "session.json", mode: mode,
                         sourceFolder: nil, destination: destination)
    }

    private static func copyPrivateEvidence(_ sourceFolder: URL, destination: URL) throws {
            // Do not follow imported links into unrelated local data.
            if let files = FileManager.default.enumerator(at: sourceFolder, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                for case let file as URL in files {
                    if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw ExportError.symbolicLink }
                }
            }
            try FileManager.default.copyItem(at: sourceFolder, to: destination)
    }

    private static func bundle(payload: Data, name: String, mode: ExportMode, sourceFolder: URL?, destination: URL, privateReport: String? = nil) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suite-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        if let sourceFolder { try copyPrivateEvidence(sourceFolder, destination: folder.appendingPathComponent("private-evidence")) }
        try payload.write(to: folder.appendingPathComponent(name), options: .atomic)
        let report = "Device Diagnostic Suite\n\(mode.rawValue)\n\n" +
            (mode == .privateDiagnostic ? (privateReport ?? "") + "\n\n" : "") + String(decoding: payload, as: UTF8.self)
        try report.write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        if name == "session.json",
           let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let events = object["events"] as? [[String: Any]] {
            let rows = ["time,kind,source,summary"] + events.map { event in
                [event["at"] as? String ?? event["date"] as? String ?? "",
                 event["kind"] as? String ?? "", event["source"] as? String ?? "",
                 event["summary"] as? String ?? event["kind"] as? String ?? ""].map { value in
                    let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
                    return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
                }.joined(separator: ",")
            }
            let csv = rows.joined(separator: "\n") + "\n"
            if mode == .shareSafe { try validateShareSafe(Data(csv.utf8)) }
            try csv.write(to: folder.appendingPathComponent("events.csv"), atomically: true, encoding: .utf8)
        }
        let note = mode == .shareSafe ?
            "Share-Safe Export. Closed-schema normalized facts only. No raw logs, identifiers, filenames, locations, notes, or event text. Exact timestamps remain and can identify an incident. Review before sharing.\n" :
            "Private Diagnostic Export. Contains retained private evidence. Do not upload to a public issue. Session captures contain only retained data; earlier display redaction cannot be reversed.\n"
        try note.write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let (code, output) = await Command.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", folder.path, destination.path], timeout: 300)
        guard code == 0 else { throw NSError(domain: "DiagnosticExport", code: Int(code), userInfo: [NSLocalizedDescriptionKey: String(output.prefix(180))]) }
    }
}
