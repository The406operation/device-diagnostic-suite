import Foundation

enum DeviceRole: String, Codable, CaseIterable, Identifiable {
    case control = "Control"
    case primary = "Primary"
    var id: String { rawValue }
}

enum EvidenceBasis: String, Codable {
    case device = "Device query"
    case log = "Device log"
    case mac = "Mac test"
    case user = "User report"
    case unavailable = "Unavailable"
}

struct FieldObservation: Identifiable, Codable, Hashable {
    var id = UUID()
    var field: String
    var value: String
    var basis: EvidenceBasis
    var source: String
    var observedAt = Date()
    var note = ""
}

struct RawEvidence: Identifiable, Codable, Hashable {
    var id = UUID()
    var relativePath: String
    var sha256: String
    var bytes: Int64
    var capturedAt = Date()
    var source: String
}

enum MarkerKind: String, Codable, CaseIterable, Identifiable {
    case airplaneOn = "Airplane mode on"
    case airplaneOff = "Airplane mode off"
    case cellularOn = "Cellular on"
    case cellularOff = "Cellular off"
    case reboot = "Reboot"
    case call = "Attempted call"
    case sms = "Attempted SMS"
    case data = "Cellular data test"
    case wifiOff = "Wi-Fi off"
    case wifiOn = "Wi-Fi on"
    case fiveG = "Observed 5G"
    case lte = "Observed LTE"
    case sos = "Observed SOS / No service"
    case serviceRestored = "Service restored"
    case other = "Other action"
    var id: String { rawValue }
}

struct ActionMarker: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: MarkerKind
    var at = Date()
    var outcome: String
    var note: String
    var role: DeviceRole? = nil
}

enum FaultSignal: String, Codable {
    case registeredService = "Registered service"
    case registrationLoss = "Registration lost or emergency only"
    case modemReset = "Modem reset or disappearance"
    case networkReject = "Registration rejection"
    case imsLoss = "IMS or voice registration loss"
    case dataLoss = "Cellular data interface loss"
    case serviceLoss = "Service loss"
    case simChange = "SIM or eSIM change"
    case networkPath = "Network path change"
    case callFailure = "Call failure"
    case other = "Other"
}

struct CampaignEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var at: Date
    var signal: FaultSignal
    var summary: String
    var source: String
}

struct MatchedContext: Codable, Hashable {
    var location = "Not recorded"
    var wifi = "Not recorded"
    var cellular = "Not recorded"
    var testWindow = "Not recorded"
    var notes = ""
}

struct CampaignRun: Identifiable, Codable {
    var id = UUID()
    var role: DeviceRole
    var deviceID: String
    var startedAt = Date()
    var endedAt: Date?
    var timeZoneOffsetSeconds: Int? = nil
    var context: MatchedContext
    var observations: [FieldObservation] = []
    var events: [CampaignEvent] = []
    var markers: [ActionMarker] = []
    var evidence: [RawEvidence] = []
    var status = "In progress"
    var errors: [String] = []
}

struct MatchedSession: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date()
    var context = MatchedContext()
    var controlRunID: UUID?
    var primaryRunID: UUID?
}

struct CampaignState: Codable {
    var primaryID: String?
    var controlID: String?
    var runs: [CampaignRun] = []
    var matchedSessions: [MatchedSession] = []
    var markers: [ActionMarker] = []
    var autoResumeWatcher = false
    var lastIncidentID: UUID?
}

struct DeviceCandidate: Identifiable, Hashable {
    var id: String
    var name: String
    var productType: String
    var ios: String
    var connectedAt = Date()
}

struct FaultAssessment: Codable {
    var observedFacts: [String]
    var inference: String
    var confidence: String
    var contradictoryEvidence: [String]
    var remainingUncertainty: [String]
    var nextTest: String
}

struct WatcherIncidentEntry: Identifiable {
    var id: String
    var at: String
    var status: String
    var complete: Bool
    var path: URL
}
