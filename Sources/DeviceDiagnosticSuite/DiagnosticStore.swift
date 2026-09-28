import AppKit
import Combine
import Foundation

@MainActor
final class DiagnosticStore: ObservableObject {
    @Published var state = AppState()
    @Published var device: DeviceSnapshot?
    @Published var status = "Ready"
    @Published var liveLines: [String] = []
    @Published var capturing = false
    @Published var networkResult = "Not run"
    @Published var importProgress = ""

    private var logProcess: Process?
    private var logBuffer = ""
    private var unsavedLogCount = 0
    private let storageURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Device Diagnostic Suite Public", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("sessions.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: storageURL), let saved = try? decoder.decode(AppState.self, from: data) { state = saved }
    }

    var selectedSession: CaptureSession? {
        state.sessions.first { $0.id == state.selectedSessionID }
    }

    func save() {
        guard let data = try? JSONEncoder.pretty.encode(state) else { status = "Could not encode sessions"; return }
        do { try data.write(to: storageURL, options: .atomic) }
        catch { status = "Could not save sessions: \(error.localizedDescription)" }
    }

    func startSession(kind: SessionKind) {
        stopLogs()
        let title = "\(kind.rawValue) · \(Date().formatted(date: .abbreviated, time: .shortened))"
        let session = CaptureSession(kind: kind, title: title, device: device)
        state.sessions.insert(session, at: 0)
        state.selectedSessionID = session.id
        liveLines = []
        status = "Session started"
        save()
    }

    func endSession() {
        stopLogs()
        editSelected { $0.endedAt = Date() }
        status = "Session ended"
    }

    func editSelected(_ edit: (inout CaptureSession) -> Void) {
        guard let id = state.selectedSessionID, let index = state.sessions.firstIndex(where: { $0.id == id }) else { return }
        edit(&state.sessions[index])
        save()
    }

    func addNote(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let event = DiagnosticEvent(kind: .note, summary: Analysis.redact(text), source: "User note", detail: Analysis.redact(text))
        editSelected { $0.events.append(event) }
    }

    func addEvent(_ event: DiagnosticEvent) {
        guard state.selectedSessionID != nil else { return }
        editSelected { session in
            if session.events.count < 10_000 { session.events.append(event) }
            session.logLines += 1
        }
    }

    func refreshDevice(preferredID: String? = nil) async {
        status = "Checking iPhone"
        guard let infoPath = Command.tool("ideviceinfo"), let idPath = Command.tool("idevice_id") else {
            status = "libimobiledevice is unavailable. Install it with Homebrew."
            return
        }
        let (code, ids) = await Command.run(idPath, ["-l"])
        let connected = ids.split(separator: "\n").map(String.init)
        guard code == 0, let identifier = preferredID.flatMap({ connected.contains($0) ? $0 : nil }) ?? connected.first else {
            device = nil
            status = "No iPhone found. Connect and trust the iPhone."
            return
        }
        var snapshot = DeviceSnapshot()
        snapshot.identifier = identifier
        snapshot.connected = true
        let keys: [(String, WritableKeyPath<DeviceSnapshot, String>)] = [
            ("DeviceName", \.name), ("ProductType", \.productType),
            ("ProductVersion", \.ios), ("BuildVersion", \.build),
            ("BasebandVersion", \.baseband), ("SIMStatus", \.simStatus)
        ]
        for (key, path) in keys {
            let (statusCode, value) = await Command.run(infoPath, ["-u", identifier, "-k", key])
            if statusCode == 0 { snapshot[keyPath: path] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let (batteryCode, batteryValue) = await Command.run(infoPath, ["-u", identifier, "-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"])
        if batteryCode == 0 { snapshot.battery = batteryValue.trimmingCharacters(in: .whitespacesAndNewlines) + "%" }
        let (storageCode, storageValue) = await Command.run(infoPath, ["-u", identifier, "-q", "com.apple.disk_usage", "-k", "AmountDataAvailable"])
        if storageCode == 0, let bytes = Double(storageValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            snapshot.storage = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + " available"
        }
        if let pairPath = Command.tool("idevicepair") {
            let (pairCode, _) = await Command.run(pairPath, ["validate", "-u", identifier])
            snapshot.paired = pairCode == 0
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("device-\(UUID().uuidString).json")
        let (_, _) = await Command.run("/usr/bin/xcrun", ["devicectl", "device", "info", "details", "--device", identifier, "--json-output", temporary.path], timeout: 8)
        if let data = try? Data(contentsOf: temporary),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let properties = result["properties"] as? [String: Any] {
            let hardware = properties["hardware"] as? [String: Any]
            let state = properties["state"] as? [String: Any]
            snapshot.model = hardware?["marketingName"] as? String ?? snapshot.productType
            if let mode = state?["developerModeStatus"] as? [String: Any] { snapshot.developerMode = mode.keys.first?.capitalized ?? "Unknown" }
        } else { snapshot.model = snapshot.productType }
        try? FileManager.default.removeItem(at: temporary)
        device = snapshot
        if state.selectedSessionID != nil { editSelected { $0.device = snapshot } }
        status = "iPhone connected · \(snapshot.model)"
    }

    func startLogs() {
        guard !capturing else { return }
        guard let identifier = device?.identifier, let path = Command.tool("idevicesyslog") else {
            status = "Connect an iPhone and install libimobiledevice first"
            return
        }
        if selectedSession == nil || selectedSession?.endedAt != nil { startSession(kind: .general) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-u", identifier, "-x", "--no-colors", "-p", "CommCenter|CoreTelephony|basebandd|telephonyutilitiesd|callservicesd"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.consumeLogChunk(chunk) }
        }
        do {
            try process.run()
            logProcess = process
            capturing = true
            status = "Capturing live iPhone logs"
        } catch { status = "Log capture failed: \(error.localizedDescription)" }
    }

    func stopLogs() {
        if logProcess?.isRunning == true { logProcess?.terminate() }
        logProcess = nil
        capturing = false
        if unsavedLogCount > 0 { save(); unsavedLogCount = 0 }
    }

    private func consumeLogChunk(_ chunk: String) {
        logBuffer += chunk
        let parts = logBuffer.components(separatedBy: .newlines)
        logBuffer = parts.last ?? ""
        let lines = Array(parts.dropLast())
        var display = liveLines
        display += lines.suffix(150).map(Analysis.redact)
        liveLines = Array(display.suffix(150))
        if let id = state.selectedSessionID, let index = state.sessions.firstIndex(where: { $0.id == id }) {
            var session = state.sessions[index]
            session.logLines += lines.count
            for line in lines {
                if let event = Analysis.event(from: line, source: "Live iPhone log"), session.events.count < 3_000 {
                    session.events.append(event)
                }
            }
            state.sessions[index] = session
        }
        unsavedLogCount += lines.count
        if unsavedLogCount >= 500 { save(); unsavedLogCount = 0 }
    }

    func importFile(_ url: URL) async {
        if selectedSession == nil || selectedSession?.endedAt != nil { startSession(kind: .general) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        importProgress = "Reading \(url.lastPathComponent)"
        var lines: [String] = []
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            if url.pathExtension == "logarchive" { lines = await logArchiveLines(url) }
            else if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                var fileCount = 0
                while let file = enumerator.nextObject() as? URL, fileCount < 200 {
                    guard ["txt", "log", "ips", "crash", "json"].contains(file.pathExtension.lowercased()),
                          (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < 5_000_000 else { continue }
                    fileCount += 1
                    if let text = try? String(contentsOf: file, encoding: .utf8) { lines += text.components(separatedBy: .newlines).prefix(30_000) }
                }
            }
        } else if ["tar", "gz", "tgz"].contains(url.pathExtension.lowercased()) {
            lines = await archiveLines(url)
        } else if ["txt", "log", "ips", "crash", "json"].contains(url.pathExtension.lowercased()),
                  ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max) < 5_000_000,
                  let text = try? String(contentsOf: url, encoding: .utf8) {
            lines = Array(text.components(separatedBy: .newlines).prefix(50_000))
        } else {
            importProgress = "Unsupported or too large: \(url.lastPathComponent)"
            return
        }
        let source = url.lastPathComponent
        var found: [DiagnosticEvent] = []
        for line in lines.prefix(100_000) {
            if let event = Analysis.event(from: line, source: source), found.count < 5_000 { found.append(event) }
        }
        editSelected { session in
            session.importedFiles.append(source)
            session.logLines += lines.count
            session.events += found
        }
        importProgress = "\(source): Imported \(lines.count) lines · \(found.count) related events"
    }

    func importDeviceCrashes() async {
        guard let identifier = device?.identifier, let tool = Command.tool("idevicecrashreport") else {
            status = "Connect the iPhone and install libimobiledevice first"
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("device-crashes-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { status = "Cannot create a temporary folder"; return }
        status = "Copying crash reports from iPhone"
        let (code, output) = await Command.run(tool, ["-u", identifier, "-k", folder.path], timeout: 90)
        if code == 0 { await importFile(folder); status = "Crash reports copied and scanned" }
        else { status = "Crash report copy failed: \(String(output.prefix(180)))" }
        try? FileManager.default.removeItem(at: folder)
    }

    private func archiveLines(_ url: URL) async -> [String] {
        let isGzip = ["gz", "tgz"].contains(url.pathExtension.lowercased())
        let listArgs = [isGzip ? "-tzf" : "-tf", url.path]
        let (listCode, listing) = await Command.run("/usr/bin/tar", listArgs, timeout: 30)
        guard listCode == 0 else { importProgress = "Archive could not be read"; return [] }
        let names = listing.components(separatedBy: .newlines).filter { name in
            !name.hasPrefix("/") && !name.split(separator: "/").contains("..") &&
            ["txt", "log", "ips", "crash"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) &&
            Analysis.cellularTerms.contains(where: name.lowercased().contains)
        }.prefix(30)
        var result: [String] = []
        for name in names {
            let (_, content) = await Command.run("/usr/bin/tar", [isGzip ? "-xOzf" : "-xOf", url.path, name], timeout: 20)
            result += content.components(separatedBy: .newlines).prefix(10_000)
        }
        return result
    }

    private func logArchiveLines(_ url: URL) async -> [String] {
        let predicate = "process == 'CommCenter' OR process == 'CoreTelephony' OR eventMessage CONTAINS[c] 'baseband' OR eventMessage CONTAINS[c] 'registration'"
        let (_, output) = await Command.run("/usr/bin/log", ["show", "--archive", url.path, "--style", "compact", "--last", "1d", "--predicate", predicate], timeout: 60)
        return Array(output.components(separatedBy: .newlines).prefix(50_000))
    }

    func runNetworkTest() async {
        networkResult = "Testing Mac connection"
        let start = Date()
        do {
            var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            networkResult = "Mac HTTPS: HTTP \(code) · \(elapsed) ms. This does not test iPhone cellular service."
        } catch { networkResult = "Mac HTTPS failed: \(error.localizedDescription). This does not test iPhone cellular service." }
        if state.selectedSessionID != nil {
            let event = DiagnosticEvent(kind: .network, summary: networkResult, source: "Mac network test", detail: networkResult)
            editSelected { $0.events.append(event) }
        }
    }

    func exportSelected(to url: URL, mode: ExportMode = .shareSafe) async {
        guard let session = selectedSession else { status = "Select a session first"; return }
        do {
            try await ExportPolicy.createSessionBundle(session, mode: mode, destination: url)
            status = "\(mode.rawValue) saved"
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }

}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
