import AppKit
import SwiftUI

struct CampaignView: View {
    @ObservedObject var campaign: CampaignStore
    var section: Section
    @State private var context = MatchedContext()
    @State private var markerKind: MarkerKind = .other
    @State private var markerOutcome = ""
    @State private var markerNote = ""
    @State private var markerRole: DeviceRole = .primary
    @State private var selectedMatchedID: UUID?

    private var selectedMatched: MatchedSession? {
        campaign.state.matchedSessions.first { $0.id == selectedMatchedID }
    }

    private func shownRun(_ role: DeviceRole) -> CampaignRun? {
        let id = role == .control ? selectedMatched?.controlRunID : selectedMatched?.primaryRunID
        return id.flatMap { target in campaign.state.runs.first { $0.id == target } } ?? campaign.latest(role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch section {
            case .paired: paired
            case .sosCapture: sos
            case .fault: fault
            default: EmptyView()
            }
        }
    }

    private var paired: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("Connected phones", "iphone.gen3.radiowaves.left.and.right") {
                HStack {
                    Text(campaign.status).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh phones") { Task { await campaign.refreshDevices() } }
                }
                ForEach(campaign.candidates) { phone in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phone.name).font(.headline)
                            Text("\(phone.productType) · iOS \(phone.ios) · \(String(phone.id.prefix(8)))…\(String(phone.id.suffix(4)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(campaign.state.controlID == phone.id ? "Control ✓" : "Set control") { campaign.assign(.control, id: phone.id) }
                        Button(campaign.state.primaryID == phone.id ? "Primary ✓" : "Set primary") { campaign.assign(.primary, id: phone.id) }
                    }
                    Divider()
                }
                if campaign.candidates.isEmpty { Text("Connect and trust both phones. The app can test them one at a time if needed.") }
            }
            if !campaign.state.matchedSessions.isEmpty {
                card("Saved matched sessions", "clock.arrow.circlepath") {
                    Picker("Compare", selection: $selectedMatchedID) {
                        ForEach(campaign.state.matchedSessions) { session in
                            Text(session.context.testWindow).tag(Optional(session.id))
                        }
                    }
                    if let selectedMatched {
                        Text("Wi-Fi: \(selectedMatched.context.wifi) · Cellular: \(selectedMatched.context.cellular) · \(selectedMatched.context.location)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            card("Matched test conditions", "checklist") {
                TextField("Location description", text: $context.location)
                HStack {
                    Picker("Wi-Fi", selection: $context.wifi) {
                        ForEach(["Not recorded", "On", "Off"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Cellular", selection: $context.cellular) {
                        ForEach(["Not recorded", "On", "Off"], id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField("Other matching conditions", text: $context.notes)
                HStack {
                    Button("Create matched session") {
                        campaign.startMatched(context)
                        selectedMatchedID = campaign.state.matchedSessions.first?.id
                    }
                    Button("Run control baseline") { Task { await campaign.startBaseline(.control, context: context) } }
                        .buttonStyle(.borderedProminent).disabled(campaign.baselineRunning || campaign.state.controlID == nil)
                    Button("Run primary baseline") { Task { await campaign.startBaseline(.primary, context: context) } }
                        .disabled(campaign.baselineRunning || campaign.state.primaryID == nil || campaign.latest(.control) == nil)
                }
                Text("The routine reads device details, selected cellular logs, safe diagnostics, crash reports, and a device log archive. The archive can use hundreds of megabytes. The routine does not change phone settings or place calls.")
                    .foregroundStyle(.secondary)
            }
            card("Field-by-field baseline", "square.split.2x1") {
                Text("Each value shows its source and observation time. An archive value is the last matching log entry in a window with a five-minute margin. It can precede or follow the baseline. Unavailable means the source did not expose that field.")
                    .font(.caption).foregroundStyle(.secondary)
                let control = shownRun(.control)
                let primary = shownRun(.primary)
                HStack {
                    Text("Field").frame(width: 185, alignment: .leading)
                    Text("Control").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Primary").frame(maxWidth: .infinity, alignment: .leading)
                }.font(.headline)
                Divider()
                ForEach(CampaignAnalysis.fields, id: \.self) { field in
                    HStack(alignment: .top) {
                        Text(field).frame(width: 185, alignment: .leading)
                        observationCell(CampaignAnalysis.observation(field, in: control))
                        observationCell(CampaignAnalysis.observation(field, in: primary))
                    }
                    Divider()
                }
            }
            runCard(shownRun(.control))
            runCard(shownRun(.primary))
        }
        .onAppear {
            if selectedMatchedID == nil { selectedMatchedID = campaign.state.matchedSessions.first?.id }
            if let selectedMatched { context = selectedMatched.context }
        }
    }

    private func observationCell(_ observation: FieldObservation?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(observation?.value ?? "Not recorded")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            if let observation {
                Text("\(observation.basis.rawValue) · \(observation.observedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runCard(_ run: CampaignRun?) -> some View {
        card(run?.role.rawValue ?? "Run not recorded", "doc.text") {
            if let run {
                Text("\(run.status) · \(run.startedAt.formatted(date: .abbreviated, time: .standard)) · \(run.evidence.count) raw evidence files · \(run.events.count) classified events")
                HStack {
                    Button("Collect sysdiagnose") { Task { await campaign.collectSysdiagnose(for: run.id) } }
                    Button("Collect log archive") { Task { await campaign.collectLogArchive(for: run.id) } }
                    Button("Attach raw evidence") { chooseEvidence(for: run.id) }
                    Button("Share-Safe Export") { chooseExport(for: run.id, mode: .shareSafe) }
                    Button("Private Diagnostic Export") { chooseExport(for: run.id, mode: .privateDiagnostic) }
                }
                if !run.errors.isEmpty { Text(run.errors.joined(separator: " · ")).foregroundStyle(.orange) }
            } else { Text("Run the baseline after assigning the phone.").foregroundStyle(.secondary) }
        }
    }

    private var sos: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("Primary SOS watcher", "waveform.path.ecg") {
                Text(campaign.watcherStatus).font(.headline)
                Text("The watcher keeps up to 20 raw log segments of 10 MB each. It records SIM and modem version checks every 15 seconds. An explicit SOS log entry or your marker freezes the earlier segments. The watcher then retains later logs for a review window.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Arm watcher") { campaign.startWatcher() }
                        .buttonStyle(.borderedProminent).disabled(campaign.watcherActive || campaign.state.primaryID == nil)
                    Button("Stop watcher") { campaign.stopWatcher() }.disabled(!campaign.watcherActive)
                    Button("Refresh status") { campaign.pollWatcher() }
                }
                Text("Keep this Mac on and the phone connected for continuous live logs. A cable disconnect is recorded as a connection change, not a proven phone reboot.")
                    .foregroundStyle(.secondary)
            }
            card("One-click fault markers", "pin") {
                HStack {
                    Button("Mark SOS now") { campaign.addMarker(.sos, outcome: "Visible SOS / no service", note: markerNote) }
                        .buttonStyle(.borderedProminent)
                    Button("Mark service restored") { campaign.addMarker(.serviceRestored, outcome: "Service visible", note: markerNote) }
                }
                HStack {
                    Picker("Phone", selection: $markerRole) { ForEach(DeviceRole.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Action", selection: $markerKind) { ForEach(MarkerKind.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Result, if known", text: $markerOutcome)
                }
                TextField("Short note", text: $markerNote)
                Button("Save timestamped marker") {
                    campaign.addMarker(markerKind, outcome: markerOutcome, note: markerNote, role: markerRole)
                    markerOutcome = ""; markerNote = ""
                }
                Text("A marker records when you pressed the button. Add a note if the phone action happened earlier.")
                    .foregroundStyle(.secondary)
            }
            card("Recent action markers", "clock") {
                ForEach(campaign.state.markers.suffix(25).reversed(), id: \.id) { marker in
                    Text("\(marker.at.formatted(date: .abbreviated, time: .standard)) · \(marker.role?.rawValue ?? "Reported action") · \(marker.kind.rawValue) · \(marker.outcome)")
                }
                if campaign.state.markers.isEmpty { Text("No markers yet.").foregroundStyle(.secondary) }
            }
            card("Saved SOS evidence", "externaldrive") {
                ForEach(campaign.watcherIncidents) { incident in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(incident.at) · \(incident.status)")
                            Text(String(incident.id.prefix(8))).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open raw evidence") { NSWorkspace.shared.open(incident.path) }
                        if incident.complete, let run = campaign.latest(.primary) {
                            Button("Attach to latest Primary run") { Task { await campaign.attachEvidence(incident.path, to: run.id) } }
                        }
                    }
                }
                if campaign.watcherIncidents.isEmpty { Text("No incident has been frozen yet.").foregroundStyle(.secondary) }
            }
        }
    }

    private var fault: some View {
        VStack(alignment: .leading, spacing: 18) {
            let primary = campaign.latest(.primary)
            let control = campaign.latest(.control)
            if let primary {
                let assessment = CampaignAnalysis.assess(primary: primary, control: control)
                card("Observed facts", "checkmark.circle") {
                    ForEach(assessment.observedFacts, id: \.self) { Text($0) }
                }
                card("Inference and confidence", "scope") {
                    Text(assessment.inference)
                    Text("Confidence: \(assessment.confidence)").font(.headline)
                }
                card("Contradictory evidence", "arrow.left.arrow.right") {
                    ForEach(assessment.contradictoryEvidence, id: \.self) { Text($0) }
                }
                card("Remaining uncertainty and next test", "questionmark.circle") {
                    ForEach(assessment.remainingUncertainty, id: \.self) { Text($0) }
                    Text("Next: \(assessment.nextTest)").font(.headline)
                }
            } else {
                card("Awaiting primary run", "info.circle") { Text("Run the control baseline, then the primary baseline.") }
            }
            card("Three fault domains", "square.grid.3x1") {
                Text("iPhone hardware · A modem disappearance or repeat fault tied to the primary device would support this domain. A line-specific result on the control would oppose it.")
                Text("iOS, modem firmware, carrier bundle · A version-specific fault on one or both phones would support this domain. Equal versions alone do not prove equal behavior.")
                Text("AT&T provisioning or network · A rejection tied to one line, or simultaneous same-area failures on both phones, would support this domain. A control that stays stable is useful but does not exclude a line-specific AT&T fault.")
            }
            card("Two-phone test matrix", "tablecells") {
                Text("1. Same place and settings: compare control and primary metadata, logs, calls, SMS, and data results. Safe now.")
                Text("2. At the next SOS event: note the control’s status at the same time and preserve both log windows. Safe now.")
                Text("3. If the fault follows an AT&T line after a controlled line transfer, provisioning becomes more likely. Hold: line/eSIM changes are not authorized yet.")
                Text("4. If the fault stays with the primary phone after a controlled line transfer, device or software becomes more likely. Hold: line/eSIM changes are not authorized yet.")
                Text("No eSIM deletion, reissue, erase, restore, or carrier-account change is part of this suite.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func card<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07)))
    }

    private func chooseEvidence(for runID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach raw evidence"
        if panel.runModal() == .OK, let url = panel.url { Task { await campaign.attachEvidence(url, to: runID) } }
    }

    private func chooseExport(for runID: UUID, mode: ExportMode) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = mode == .shareSafe ? "share-safe-diagnostic.zip" : "private-diagnostic.zip"
        if panel.runModal() == .OK, let url = panel.url { Task { await campaign.exportRun(runID, mode: mode, to: url) } }
    }
}
