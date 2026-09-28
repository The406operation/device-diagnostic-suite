import Foundation

enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case goodService = "Good service"
    case sos = "SOS / No service"
    case general = "General"
    var id: String { rawValue }
}

enum EventKind: String, Codable, CaseIterable {
    case cellular = "Cellular"
    case airplane = "Airplane mode"
    case call = "Call"
    case esim = "eSIM"
    case modem = "Modem"
    case network = "Network"
    case crash = "Crash"
    case note = "Note"
}

struct DiagnosticEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: EventKind
    var summary: String
    var source: String
    var detail: String
}

struct DeviceSnapshot: Codable, Hashable {
    var capturedAt = Date()
    var name = "Unknown"
    var model = "Unknown"
    var productType = "Unknown"
    var ios = "Unknown"
    var build = "Unknown"
    var baseband = "Unavailable"
    var simStatus = "Unavailable"
    var battery = "Unavailable"
    var storage = "Unavailable"
    var paired = false
    var connected = false
    var developerMode = "Unknown"
    var identifier = ""
}

struct CaptureSession: Identifiable, Codable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var kind: SessionKind
    var title: String
    var note = ""
    var device: DeviceSnapshot?
    var events: [DiagnosticEvent] = []
    var importedFiles: [String] = []
    var logLines = 0
}

struct AppState: Codable {
    var sessions: [CaptureSession] = []
    var selectedSessionID: UUID?
    var redact = true
}

enum Section: String, CaseIterable, Identifiable {
    case overview = "Device Overview"
    case paired = "Paired Devices"
    case sosCapture = "SOS Watcher"
    case fault = "Fault Isolation"
    case liveLogs = "Live Logs"
    case cellular = "Cellular / SOS"
    case network = "Network Tests"
    case crashes = "Crash & Analytics"
    case sysdiagnose = "Sysdiagnose Import"
    case timeline = "Event Timeline"
    case comparison = "Baseline / Comparison"
    case export = "Export & Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "iphone.gen3"
        case .paired: "iphone.gen3.radiowaves.left.and.right"
        case .sosCapture: "waveform.path.ecg"
        case .fault: "scope"
        case .liveLogs: "text.alignleft"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .network: "network"
        case .crashes: "exclamationmark.triangle"
        case .sysdiagnose: "shippingbox"
        case .timeline: "clock.arrow.circlepath"
        case .comparison: "square.split.2x1"
        case .export: "square.and.arrow.up"
        }
    }
}
