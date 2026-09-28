import AppKit
import Combine
import CryptoKit
import Foundation
import Darwin

@MainActor
final class CampaignStore: ObservableObject {
    @Published var state = CampaignState()
    @Published var candidates: [DeviceCandidate] = []
    @Published var status = "Campaign ready"
    @Published var baselineRunning = false
    @Published var selectedRunID: UUID?
    @Published var watcherStatus = "Not armed"
    @Published var watcherActive = false
    @Published var watcherIncidents: [WatcherIncidentEntry] = []

    let folder: URL
    private let stateURL: URL
    private var watcherProcess: Process?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Device Diagnostic Suite Public/Campaign", isDirectory: true)
        stateURL = folder.appendingPathComponent("campaign.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if let data = try? Data(contentsOf: stateURL), let saved = try? Self.decoder.decode(CampaignState.self, from: data) {
            state = saved
        }
        loadRuns()
        pollWatcher()
    }

    var selectedRun: CampaignRun? { state.runs.first { $0.id == selectedRunID } }
    func latest(_ role: DeviceRole) -> CampaignRun? { state.runs.filter { $0.role == role }.max { $0.startedAt < $1.startedAt } }

    func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        } catch { status = "Campaign save failed: \(error.localizedDescription)" }
    }

    func refreshDevices() async {
        guard let idTool = Command.tool("idevice_id"), let infoTool = Command.tool("ideviceinfo") else {
            status = "libimobiledevice is required for paired-device capture"
            return
        }
        let (code, output) = await Command.run(idTool, ["-l"])
        guard code == 0 else { status = "Could not list paired iPhones"; return }
        var found: [DeviceCandidate] = []
        for id in output.split(separator: "\n").map(String.init) {
            let (_, name) = await Command.run(infoTool, ["-u", id, "-k", "DeviceName"])
            let (_, model) = await Command.run(infoTool, ["-u", id, "-k", "ProductType"])
            let (_, ios) = await Command.run(infoTool, ["-u", id, "-k", "ProductVersion"])
            found.append(DeviceCandidate(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                         productType: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                         ios: ios.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        candidates = found
        status = "\(found.count) paired iPhone\(found.count == 1 ? "" : "s") connected"
        pollWatcher()
    }

    func assign(_ role: DeviceRole, id: String) {
        guard candidates.contains(where: { $0.id == id }) else { status = "Connect this phone before assigning it"; return }
        if role == .primary && state.controlID == id || role == .control && state.primaryID == id {
            status = "The control and primary roles need different phones"
            return
        }
        if role == .primary { state.primaryID = id }
        else { state.controlID = id }
        save()
    }

    func loadRuns() {
        let runsFolder = folder.appendingPathComponent("runs", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: runsFolder, includingPropertiesForKeys: nil) else { return }
        for directory in directories {
            let file = directory.appendingPathComponent("run.json")
            guard let data = try? Data(contentsOf: file), var imported = try? Self.decoder.decode(CampaignRun.self, from: data) else { continue }
            let log = directory.appendingPathComponent("raw/device-syslog.log")
            if let data = try? Data(contentsOf: log) {
                let zone = TimeZone(secondsFromGMT: imported.timeZoneOffsetSeconds ?? TimeZone.current.secondsFromGMT(for: imported.startedAt)) ?? .current
                imported.events = CampaignAnalysis.events(from: String(decoding: data.prefix(30_000_000), as: UTF8.self),
                                                          source: "device-syslog.log", referenceDate: imported.startedAt, timeZone: zone)
            }
            let archiveEvents = directory.appendingPathComponent("raw/archive-events.json")
            if let data = try? Data(contentsOf: archiveEvents),
               let parsed = try? Self.decoder.decode([CampaignEvent].self, from: data) {
                imported.events.append(contentsOf: parsed)
                imported.events.sort { $0.at < $1.at }
            }
            let archiveObservations = directory.appendingPathComponent("raw/archive-observations.json")
            let supplementalEvents = directory.appendingPathComponent("raw/supplemental-events.json")
            if let data = try? Data(contentsOf: supplementalEvents),
               let parsed = try? Self.decoder.decode([CampaignEvent].self, from: data) {
                imported.events.append(contentsOf: parsed)
                imported.events.sort { $0.at < $1.at }
            }
            if let data = try? Data(contentsOf: archiveObservations),
               let parsed = try? Self.decoder.decode([FieldObservation].self, from: data) {
                imported.observations.removeAll { $0.source == "telephony-logarchive-decoded.log" }
                imported.observations.append(contentsOf: parsed)
            }
            if let index = state.runs.firstIndex(where: { $0.id == imported.id }) {
                imported.markers = state.runs[index].markers
                state.runs[index] = imported
            } else { state.runs.append(imported) }
            if imported.role == .control { state.controlID = imported.deviceID }
            else { state.primaryID = imported.deviceID }
        }
        state.runs.sort { $0.startedAt > $1.startedAt }
        if selectedRunID == nil { selectedRunID = latest(.primary)?.id }
        save()
    }

    func startBaseline(_ role: DeviceRole, context: MatchedContext) async {
        guard !baselineRunning else { return }
        guard let id = role == .control ? state.controlID : state.primaryID else { status = "Assign the \(role.rawValue) phone first"; return }
        if role == .primary && latest(.control) == nil { status = "Run the control baseline first"; return }
        guard candidates.contains(where: { $0.id == id }) else { status = "The selected phone is not connected"; return }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("run_baseline.py"), FileManager.default.fileExists(atPath: script.path) else {
            status = "The baseline resource is missing from this app build"
            return
        }
        baselineRunning = true
        status = "Capturing \(role.rawValue) baseline. Keep the phone connected."
        let args = [script.path, "--udid", id, "--role", role == .control ? "control" : "primary",
                    "--duration", "45", "--location", context.location, "--wifi", context.wifi,
                    "--cellular", context.cellular]
        let (code, output) = await Command.run("/usr/bin/python3", args, timeout: 300)
        loadRuns()
        selectedRunID = latest(role)?.id
        status = code == 0 ? "\(role.rawValue) baseline saved with raw evidence" : "Baseline incomplete: \(String(output.suffix(250)))"
        if code == 0 {
            updateMatchedRun(role)
            if let runID = selectedRunID { await collectLogArchive(for: runID) }
        }
        baselineRunning = false
    }

    func startMatched(_ context: MatchedContext) {
        state.matchedSessions.insert(MatchedSession(context: context), at: 0)
        save()
        status = "Matched session created. Run control, then primary, with the same settings."
    }

    private func updateMatchedRun(_ role: DeviceRole) {
        guard !state.matchedSessions.isEmpty, let run = latest(role) else { return }
        if role == .control { state.matchedSessions[0].controlRunID = run.id }
        else { state.matchedSessions[0].primaryRunID = run.id }
        save()
    }

    func addMarker(_ kind: MarkerKind, outcome: String, note: String, role: DeviceRole = .primary) {
        let marker = ActionMarker(kind: kind, outcome: outcome, note: note, role: role)
        state.markers.append(marker)
        if let id = latest(role)?.id, let index = state.runs.firstIndex(where: { $0.id == id }) {
            state.runs[index].markers.append(marker)
            persistRun(index)
        }
        save()
        if role == .primary && state.primaryID != nil { sendWatcherCommand(kind: kind.rawValue, at: marker.at, note: note, outcome: outcome) }
        status = "Marker saved at \(marker.at.formatted(date: .omitted, time: .standard))"
    }

    private var watcherFolder: URL? {
        guard let id = state.primaryID else { return nil }
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("watcher/\(digest.prefix(16))", isDirectory: true)
    }

    private func sendWatcherCommand(kind: String, at: Date, note: String, outcome: String) {
        guard let watcherFolder else { return }
        let commands = watcherFolder.appendingPathComponent("commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let json: [String: String] = ["kind": kind, "at": formatter.string(from: at), "note": note, "outcome": outcome]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            let path = commands.appendingPathComponent("\(UUID().uuidString).json")
            try? data.write(to: path, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
    }

    func startWatcher() {
        guard let id = state.primaryID else { status = "Assign the primary iPhone first"; return }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("watch_sos.py"), FileManager.default.fileExists(atPath: script.path) else {
            status = "The watcher resource is missing from this app build"
            return
        }
        if watcherActive { status = "SOS watcher is already running"; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, "--udid", id]
        let log = folder.appendingPathComponent("watcher-launch.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: log.path)
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
            watcherProcess = process
            state.autoResumeWatcher = true
            save()
            watcherActive = true
            watcherStatus = "Starting. The app will keep a bounded raw log ring while the Mac is on."
            status = "SOS watcher armed for the primary iPhone"
        } catch { status = "Could not start SOS watcher: \(error.localizedDescription)" }
    }

    func stopWatcher() {
        sendWatcherCommand(kind: "Stop watcher", at: Date(), note: "User stopped watcher", outcome: "")
        state.autoResumeWatcher = false
        save()
        watcherStatus = "Stop requested"
    }

    func resumeWatcherIfNeeded() {
        pollWatcher()
        if state.autoResumeWatcher && state.primaryID != nil && !watcherActive { startWatcher() }
    }

    func pollWatcher() {
        if let watcherFolder,
           let directories = try? FileManager.default.contentsOfDirectory(at: watcherFolder.appendingPathComponent("incidents"), includingPropertiesForKeys: nil) {
            watcherIncidents = directories.compactMap { path in
                guard let data = try? Data(contentsOf: path.appendingPathComponent("incident.json")),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String, let at = json["at"] as? String else { return nil }
                return WatcherIncidentEntry(id: id, at: at, status: json["status"] as? String ?? "Unknown",
                                            complete: json["finishedAt"] is String, path: path)
            }.sorted { $0.at > $1.at }
        }
        guard let watcherFolder,
              let data = try? Data(contentsOf: watcherFolder.appendingPathComponent("status.json")),
              let statusJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            watcherActive = false
            watcherStatus = "Not armed"
            return
        }
        let pid = statusJSON["pid"] as? Int ?? -1
        let stopped = statusJSON["stopped"] as? Bool ?? false
        let clock = ISO8601DateFormatter()
        clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let heartbeat = (statusJSON["at"] as? String).flatMap { clock.date(from: $0) }
        let fresh = heartbeat.map { Date().timeIntervalSince($0) < 120 } ?? false
        watcherActive = !stopped && fresh && pid > 0 && Darwin.kill(Int32(pid), 0) == 0
        let connected = statusJSON["connected"] as? Bool ?? false
        let bytes = statusJSON["rollingBytes"] as? Int ?? 0
        let incident = statusJSON["activeIncidentID"] as? String
        let lastLog = statusJSON["lastLogAt"] as? String ?? "No log bytes received"
        watcherStatus = watcherActive ? "Armed · \(connected ? "iPhone connected" : "waiting for iPhone") · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) raw history\(incident == nil ? "" : " · incident active")\nLast log: \(lastLog)" : "Not running or status is stale"
    }

    func collectSysdiagnose(for runID: UUID) async {
        guard let run = state.runs.first(where: { $0.id == runID }) else { return }
        let raw = folder.appendingPathComponent("runs/\(run.id.uuidString.lowercased())/raw", isDirectory: true)
        let destination = raw.appendingPathComponent("sysdiagnose", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        status = "Collecting \(run.role.rawValue) sysdiagnose. Keep that phone unlocked."
        let json = raw.appendingPathComponent("sysdiagnose-command.json")
        let (code, output) = await Command.run("/usr/bin/xcrun", ["devicectl", "device", "sysdiagnose", "--device", run.deviceID,
            "--destination", destination.path, "--json-output", json.path, "--timeout", "180"], timeout: 190)
        try? output.write(to: raw.appendingPathComponent("sysdiagnose-command.txt"), atomically: true, encoding: .utf8)
        if code == 0 { status = "Sysdiagnose saved for \(run.role.rawValue)" }
        else { status = "Sysdiagnose unavailable: \(Analysis.redact(String(output.suffix(250))))" }
        recordObservation(runID, field: "sysdiagnose", value: code == 0 ? "Collected" : "Unavailable",
                          basis: code == 0 ? .device : .unavailable, source: "devicectl sysdiagnose",
                          note: code == 0 ? "Raw archive stored locally" : "Command failed; see raw command result")
        updateEvidence(runID)
    }

    func collectLogArchive(for runID: UUID) async {
        guard let run = state.runs.first(where: { $0.id == runID }),
              let tool = Command.tool("idevicesyslog") else { status = "The log archive tool is unavailable"; return }
        let raw = folder.appendingPathComponent("runs/\(run.id.uuidString.lowercased())/raw", isDirectory: true)
        let archive = raw.appendingPathComponent("device-logarchive.tar")
        status = "Collecting the \(run.role.rawValue) device log archive"
        let (code, output) = await Command.run(tool, ["-u", run.deviceID, "archive", archive.path,
                                                   "--age-limit", "3600", "--size-limit", "50000000"], timeout: 180)
        try? output.write(to: raw.appendingPathComponent("logarchive-command.txt"), atomically: true, encoding: .utf8)
        let bytes = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let complete = code == 0 && bytes > 0
        if complete, let script = Bundle.main.resourceURL?.appendingPathComponent("parse_logarchive.py") {
            let (parseCode, _) = await Command.run("/usr/bin/python3", [script.path, "--run-folder", raw.deletingLastPathComponent().path], timeout: 240)
            if parseCode != 0 { status = "Archive saved, but the decoder could not read it" }
            loadRuns()
        } else {
            recordObservation(runID, field: "deviceLogArchive", value: "Unavailable",
                              basis: .unavailable, source: "idevicesyslog archive",
                              note: "Command failed; see raw command result")
        }
        updateEvidence(runID)
        if !complete { status = "Device log archive unavailable" }
        else if status != "Archive saved, but the decoder could not read it" { status = "Device log archive saved and decoded" }
    }

    private func recordObservation(_ runID: UUID, field: String, value: String, basis: EvidenceBasis,
                                   source: String, note: String) {
        guard let index = state.runs.firstIndex(where: { $0.id == runID }) else { return }
        state.runs[index].observations.append(FieldObservation(field: field, value: value,
                                                                basis: basis, source: source, note: note))
        persistRun(index)
    }

    func attachEvidence(_ url: URL, to runID: UUID) async {
        guard state.runs.contains(where: { $0.id == runID }) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let target = folder.appendingPathComponent("runs/\(runID.uuidString.lowercased())/raw/imported/\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            updateEvidence(runID)
            status = "Raw evidence copied into the selected run"
        } catch { status = "Evidence import failed: \(error.localizedDescription)" }
    }

    func updateEvidence(_ runID: UUID) {
        guard let index = state.runs.firstIndex(where: { $0.id == runID }) else { return }
        let root = folder.appendingPathComponent("runs/\(runID.uuidString.lowercased())", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        var evidence: [RawEvidence] = []
        while let file = files.nextObject() as? URL {
            guard file.hasDirectoryPath == false,
                  file.path != root.appendingPathComponent("run.json").path,
                  file.path != root.appendingPathComponent("manifest.json").path else { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            var hasher = SHA256()
            while true {
                let chunk = (try? handle.read(upToCount: 1_048_576)) ?? nil
                guard let chunk, !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
            try? handle.close()
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            evidence.append(RawEvidence(relativePath: relative, sha256: digest, bytes: Int64(bytes), source: "raw campaign evidence"))
        }
        state.runs[index].evidence = evidence.sorted { $0.relativePath < $1.relativePath }
        persistRun(index)
        save()
    }

    private func persistRun(_ index: Int) {
        let run = state.runs[index]
        let file = folder.appendingPathComponent("runs/\(run.id.uuidString.lowercased())/run.json")
        try? Self.encoder.encode(run).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        save()
    }

    func exportRun(_ runID: UUID, mode: ExportMode, to destination: URL) async {
        guard let run = state.runs.first(where: { $0.id == runID }) else { return }
        do {
            let root = folder.appendingPathComponent("runs/\(run.id.uuidString.lowercased())")
            try await ExportPolicy.createCampaignBundle(run, mode: mode, runFolder: root,
                destination: destination, control: latest(.control))
            status = "\(mode.rawValue) saved"
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }

    static func reportText(run: CampaignRun, assessment: FaultAssessment) -> String {
        let observations = run.observations.map { "\($0.field): \($0.value) [\($0.basis.rawValue), \($0.observedAt.formatted(.iso8601))]" }.joined(separator: "\n")
        let role = run.role == .control ? "Control" : "Primary"
        return "Device Diagnostic Campaign\nRole: \(role)\nStarted: \(run.startedAt.formatted(.iso8601))\nStatus: \(run.status)\n\nObserved facts\n\(assessment.observedFacts.joined(separator: "\n"))\n\nInference\n\(assessment.inference)\nConfidence: \(assessment.confidence)\n\nContradictory evidence\n\(assessment.contradictoryEvidence.joined(separator: "\n"))\n\nRemaining uncertainty\n\(assessment.remainingUncertainty.joined(separator: "\n"))\n\nNext discriminating test\n\(assessment.nextTest)\n\nNormalized fields\n\(observations)\n"
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid timestamp")
        }
        return decoder
    }
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}
