import AppKit
import SwiftUI

@main
struct DeviceDiagnosticSuiteApp: App {
    @StateObject private var store = DiagnosticStore()
    @StateObject private var campaign = CampaignStore()

    var body: some Scene {
        WindowGroup("Device Diagnostic Suite") {
            MainView(store: store, campaign: campaign)
                .frame(minWidth: 1080, minHeight: 680)
                .task {
                    await campaign.refreshDevices()
                    await store.refreshDevice(preferredID: campaign.state.primaryID)
                    campaign.resumeWatcherIfNeeded()
                    while !Task.isCancelled {
                        campaign.pollWatcher()
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
        }
        .windowStyle(.titleBar)
    }
}

struct MainView: View {
    @ObservedObject var store: DiagnosticStore
    @ObservedObject var campaign: CampaignStore
    @State private var section: Section = .overview
    @State private var kind: SessionKind = .general
    @State private var note = ""
    @State private var goodID: UUID?
    @State private var sosID: UUID?
    @State private var exportMode: ExportMode = .shareSafe

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
                    .padding(.vertical, 5)
            }
            .navigationTitle("Diagnostics")
            .frame(minWidth: 230)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(section.rawValue).font(.largeTitle.bold())
                        sectionContent
                    }
                    .frame(maxWidth: 1050, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task {
                    await campaign.refreshDevices()
                    await store.refreshDevice(preferredID: campaign.state.primaryID)
                } } label: { Label("Refresh iPhone", systemImage: "arrow.clockwise") }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: store.device?.connected == true ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .font(.title2)
                .foregroundStyle(store.device?.connected == true ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.device?.model ?? "No iPhone detected").font(.headline)
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Session", selection: $store.state.selectedSessionID) {
                Text("None").tag(UUID?.none)
                ForEach(store.state.sessions) { session in
                    Text(session.title).tag(Optional(session.id))
                }
            }
            .frame(width: 270)
            .onChange(of: store.state.selectedSessionID) { _, _ in store.save() }
            if let session = store.selectedSession {
                Text(session.endedAt == nil ? "Recording session" : "Saved session")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(session.endedAt == nil ? Color.green.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .overview: overview
        case .paired, .sosCapture, .fault: CampaignView(campaign: campaign, section: section)
        case .liveLogs: liveLogs
        case .cellular: cellular
        case .network: network
        case .crashes: crashes
        case .sysdiagnose: sysdiagnose
        case .timeline: timeline
        case .comparison: comparison
        case .export: export
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let d = store.device {
                HStack(spacing: 14) {
                    metric("Connection", d.connected ? "Connected" : "Disconnected", "cable.connector")
                    metric("Pairing", d.paired ? "Trusted" : "Not trusted", "checkmark.shield")
                    metric("Developer Mode", d.developerMode, "hammer")
                }
                panel("Device details", icon: "iphone") {
                    detail("Name", d.name)
                    detail("Model", d.model)
                    detail("Product code", d.productType)
                    detail("iOS", d.ios)
                    detail("Build", d.build)
                    detail("Modem firmware", d.baseband)
                    detail("SIM status", d.simStatus)
                    detail("Battery", d.battery)
                    detail("Free storage", d.storage)
                    detail("Device ID", d.identifier)
                }
            } else {
                panel("Connect an iPhone", icon: "cable.connector") {
                    Text("Connect the iPhone with a cable. Unlock it and choose Trust if the iPhone asks. Then choose Refresh iPhone.")
                }
            }
            sessionControls
            panel("Access notes", icon: "info.circle") {
                Text("The device details come from the paired iPhone. Apple does not provide a public API for a Mac app to read live signal strength, serving cell, or all modem state from a personal iPhone.")
                Text("Developer Mode is optional for this Mac app. Some Xcode device services require it.").foregroundStyle(.secondary)
            }
        }
    }

    private var sessionControls: some View {
        panel("Capture session", icon: "record.circle") {
            HStack {
                Picker("Run type", selection: $kind) { ForEach(SessionKind.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 260)
                Button("Start new session") { store.startSession(kind: kind) }
                    .buttonStyle(.borderedProminent)
                Button("End session") { store.endSession() }
                    .disabled(store.selectedSession == nil || store.selectedSession?.endedAt != nil)
            }
            Text("Use one run while service works and another run during SOS. Keep the iPhone connected for live logs.")
                .foregroundStyle(.secondary)
        }
    }

    private var liveLogs: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("iPhone log stream", icon: "waveform.path") {
                HStack {
                    Button(store.capturing ? "Stop capture" : "Start capture") {
                        store.capturing ? store.stopLogs() : store.startLogs()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.device == nil)
                    Text("Recent lines: \(store.liveLines.count)").foregroundStyle(.secondary)
                }
                Text("The app captures selected telephony processes. It stores related events and a line count. It does not store the full raw stream. Displayed lines have basic identifier redaction.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(store.liveLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 360)
                .padding(10)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            panel("Apple Console", icon: "macwindow") {
                Text("Console can show connected iPhone logs when a service does not relay through libimobiledevice.")
                Button("Open Console") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")) }
            }
        }
    }

    private var cellular: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                metric("Cellular events", "\(Analysis.count(.cellular, in: store.selectedSession))", "antenna.radiowaves.left.and.right")
                metric("Modem events", "\(Analysis.count(.modem, in: store.selectedSession))", "cpu")
                metric("SIM events", "\(Analysis.count(.esim, in: store.selectedSession))", "simcard")
                metric("Call events", "\(Analysis.count(.call, in: store.selectedSession))", "phone.down")
            }
            panel("SOS capture guide", icon: "cross.case") {
                Text("1. Run the control and primary baselines in Paired Diagnostics.")
                Text("2. Arm the primary SOS watcher while service is available. Keep the Mac on and connected.")
                Text("3. When SOS appears, mark the time in SOS Capture. The watcher keeps earlier logs.")
                Text("4. Mark service restored and compare the before, during, and after windows.")
                Text("A matching word is a clue. It is not proof that the modem, SIM, or AT&T caused the fault.")
                    .foregroundStyle(.secondary)
            }
            panel("Event note", icon: "square.and.pencil") {
                TextField("Example: SOS appeared at 4:12 PM; airplane mode was off", text: $note)
                Button("Add timestamped note") { store.addNote(note); note = "" }
                    .disabled(store.selectedSession == nil || note.isEmpty)
            }
            eventList(store.selectedSession?.events.filter { [.cellular, .modem, .esim, .airplane, .call].contains($0.kind) } ?? [])
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Mac network check", icon: "network") {
                Text("This check makes one HTTPS request from the Mac. It measures the Mac connection only.")
                Button("Run Mac HTTPS check") { Task { await store.runNetworkTest() } }
                    .buttonStyle(.borderedProminent)
                Text(store.networkResult).font(.system(.body, design: .monospaced))
            }
            panel("iPhone cellular check", icon: "iphone.radiowaves.left.and.right") {
                Text("On the iPhone, turn Wi‑Fi off. Open a web page with cellular data. Add the result and time to the SOS session. Turn Wi‑Fi back on when finished.")
                Text("The Mac cannot route this test through the iPhone cellular radio with the public interfaces used here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var crashes: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Crash and analytics files", icon: "doc.text.magnifyingglass") {
                Text("Import .ips, .crash, .log, .txt, or a folder of these files. The app scans for crash, panic, jetsam, and cellular terms.")
                Button("Import files or folder") { chooseImport() }
                Button("Copy reports from connected iPhone") { Task { await store.importDeviceCrashes() } }
                    .disabled(store.device == nil)
                Text("To find iPhone analytics files: Settings → Privacy & Security → Analytics & Improvements → Analytics Data. Share selected files to the Mac.")
                    .foregroundStyle(.secondary)
            }
            eventList(store.selectedSession?.events.filter { $0.kind == .crash } ?? [])
        }
    }

    private var sysdiagnose: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Import sysdiagnose", icon: "shippingbox") {
                Text("Choose a sysdiagnose .tar.gz archive, an extracted folder, a .logarchive folder, or a text log. The app scans a bounded set of related text files.")
                Button("Choose sysdiagnose or log") { chooseImport() }
                    .buttonStyle(.borderedProminent)
                Text(store.importProgress).foregroundStyle(.secondary)
            }
            panel("What the importer reads", icon: "info.circle") {
                Text("A .tar.gz import scans up to 30 text members whose paths contain cellular terms. A folder import scans up to 200 small text files. A .logarchive import asks Apple's log tool for the last day of selected messages.")
                Text("The app does not copy the full archive into session history or the export. Keep the original archive if you need a full forensic review.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Session timeline", icon: "clock") {
                Text("Events appear in time order. The source shows whether an event came from a live log, an imported file, or your note.")
                Text("\(store.selectedSession?.events.count ?? 0) events in selected session")
                    .foregroundStyle(.secondary)
            }
            eventList((store.selectedSession?.events ?? []).sorted { $0.date < $1.date })
        }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Choose runs", icon: "square.split.2x1") {
                HStack {
                    Picker("Good service", selection: $goodID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(store.state.sessions.filter { $0.kind == .goodService }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("SOS", selection: $sosID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(store.state.sessions.filter { $0.kind == .sos }) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
            }
            if let good = store.state.sessions.first(where: { $0.id == goodID }),
               let sos = store.state.sessions.first(where: { $0.id == sosID }) {
                panel("Event comparison", icon: "chart.bar.xaxis") {
                    detail("Metric", "Good service                         SOS")
                    ForEach(EventKind.allCases, id: \.self) { kind in
                        detail(kind.rawValue, "\(Analysis.count(kind, in: good))                                      \(Analysis.count(kind, in: sos))")
                    }
                    Text("Run length and log volume can differ. Event counts alone cannot identify a cause.")
                        .foregroundStyle(.secondary)
                }
            } else {
                panel("Start with two runs", icon: "square.split.2x1") {
                    Text("Capture a Good service run and an SOS / No service run. Then choose both runs here.")
                }
            }
        }
    }

    private var export: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Export review bundle", icon: "square.and.arrow.up") {
                Picker("Export mode", selection: $exportMode) {
                    ForEach(ExportMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(exportMode == .shareSafe ? "Exports normalized facts. Omits free text, identifiers, and raw evidence." : "Exports all retained session data. Contains private information. Do not upload publicly.")
                Button("Export selected session") { chooseExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedSession == nil)
            }
            panel("Privacy", icon: "hand.raised") {
                Text("Sessions stay on this Mac in Application Support. Live lines and imported event text get basic phone, email, network address, and device ID redaction before storage.")
                Text("Redaction is pattern based. Review the bundle before sharing it. A log can contain personal data that the patterns do not detect.")
                    .foregroundStyle(.secondary)
                Text("Local store: ~/Library/Application Support/Device Diagnostic Suite Public/sessions.json")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private func eventList(_ events: [DiagnosticEvent]) -> some View {
        panel("Events", icon: "list.bullet.rectangle") {
            if events.isEmpty { Text("No related events in this session yet.").foregroundStyle(.secondary) }
            else {
                ForEach(events.suffix(300).reversed(), id: \.id) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.kind.rawValue).font(.caption.weight(.bold)).foregroundStyle(.blue)
                            Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(event.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.summary).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07)))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detail(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url { Task { await store.importFile(url) } }
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Device-Diagnostic-\(Date().formatted(.iso8601.year().month().day())).zip"
        panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let url = panel.url { Task { await store.exportSelected(to: url, mode: exportMode) } }
    }
}
