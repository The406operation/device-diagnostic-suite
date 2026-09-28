import Foundation

enum CampaignAnalysis {
    static let fields = [
        "model", "productType", "hardwareModel", "serialNumber", "deviceIdentifier",
        "iOS", "build", "modemFirmware", "carrierBundleID", "carrierBundleVersion",
        "simState", "esimEmbedded", "carrierMCCMNC", "registrationState", "radioAccessTechnology",
        "imsVoiceRegistration", "serviceState", "signalBars", "fieldTestSNR", "networkInterface", "cellularPathEvent", "dnsResult", "connectivityResult",
        "callResult", "smsResult", "cellularDataResult", "rebootRecovery", "airplaneRecovery",
        "crashReports", "deviceLogArchive", "archiveWindowLines", "sysdiagnose"
    ]

    static func signal(in line: String) -> FaultSignal? {
        let x = line.lowercased()
        if !["next airplane mode toggle or baseband reset", "deferring baseband resets", "baseband reset capable"].contains(where: x.contains) &&
            ["baseband crash", "baseband reset detected", "baseband has reset", "modem reset detected", "modem not responding", "baseband disappeared", "panic-full"].contains(where: x.contains) { return .modemReset }
        if x.contains("registration status: kregisteredhome") { return .registeredService }
        if ["registration reject", "registration denied", "attach reject", "network reject", "emm reject", "5gmm reject"].contains(where: x.contains) { return .networkReject }
        if x.contains("registration status: kemergencyonly") || x.contains("registration status: ksearching") { return .registrationLoss }
        if x.contains("imsregistrationstate") && (x.contains("registered: knotregistered") || x.contains("ue is not registered")) { return .imsLoss }
        if x.contains("ims") && ["deregister", "registration failed", "unregistered", "registration lost"].contains(where: x.contains) { return .imsLoss }
        if x.contains("nepathevent cellular failed") { return .dataLoss }
        if ["pdp deactivated", "data interface down", "cellular data failed", "pdp failure", "pdu session reject"].contains(where: x.contains) { return .dataLoss }
        if ["no service", "sos only", "service unavailable", "registration lost"].contains(where: x.contains) { return .serviceLoss }
        if ["sim removed", "sim absent", "esim changed", "simstatus changed"].contains(where: x.contains) { return .simChange }
        if (x.contains("interface") || x.contains("network path")) && ["down", "changed", "lost"].contains(where: x.contains) { return .networkPath }
        if ["call failed", "call dropped", "call failure"].contains(where: x.contains) { return .callFailure }
        return nil
    }

    static func events(from text: String, source: String, referenceDate: Date = Date(), timeZone: TimeZone = .current, limit: Int = 5000) -> [CampaignEvent] {
        var found: [CampaignEvent] = []
        for line in text.components(separatedBy: .newlines) {
            if let signal = signal(in: line), let at = Analysis.date(in: line, referenceDate: referenceDate, timeZone: timeZone) {
                found.append(CampaignEvent(at: at, signal: signal,
                                           summary: Analysis.redact(line), source: source))
                if found.count >= limit { break }
            }
        }
        return found
    }

    static func observation(_ field: String, in run: CampaignRun?) -> FieldObservation? {
        run?.observations.filter { $0.field == field }.max { $0.observedAt < $1.observedAt }
    }

    static func assess(primary: CampaignRun, control: CampaignRun?) -> FaultAssessment {
        let ordered = primary.events.sorted { $0.at < $1.at }
        let incident = primary.markers.first { $0.kind == .sos }
        let lastGood = incident.flatMap { mark in ordered.last { $0.signal == .registeredService && $0.at <= mark.at } }
        let window = incident.map { mark in
            ordered.filter { $0.signal != .other && $0.signal != .registeredService &&
                $0.at >= (lastGood?.at ?? mark.at.addingTimeInterval(-300)) && $0.at <= mark.at.addingTimeInterval(300) }
        } ?? []
        let first = window.first
        var facts = ["Primary run: \(primary.startedAt.formatted(.iso8601)); \(primary.events.count) classified log events."]
        if let service = observation("serviceState", in: primary), service.basis != .unavailable {
            facts.append("Primary service report: \(service.value) at \(service.observedAt.formatted(.iso8601)) [\(service.basis.rawValue)].")
        }
        if let registration = observation("registrationState", in: primary), registration.basis != .unavailable {
            facts.append("Primary last logged registration: \(registration.value) at \(registration.observedAt.formatted(.iso8601)).")
        }
        if let first { facts.append("First classified event in the review window: \(first.signal.rawValue) at \(first.at.formatted(.iso8601)).") }
        if let lastGood { facts.append("Last recorded normal registration before SOS: \(lastGood.at.formatted(.iso8601)).") }
        if let incident { facts.append("SOS was marked at \(incident.at.formatted(.iso8601)).") }
        if let control {
            facts.append("Control run: \(control.startedAt.formatted(.iso8601)); \(control.events.count) classified log events.")
            if let registration = observation("registrationState", in: control), registration.basis != .unavailable {
                facts.append("Control last logged registration: \(registration.value) at \(registration.observedAt.formatted(.iso8601)).")
            }
        }
        var conflicts: [String] = []
        if let lastGood, let priorIMS = ordered.last(where: {
            $0.signal == .imsLoss && $0.at < lastGood.at && $0.at >= lastGood.at.addingTimeInterval(-10)
        }) {
            conflicts.append("IMS was recorded not registered at \(priorIMS.at.formatted(.iso8601)), just before the last normal serving registration. A normal serving-registration entry does not establish that IMS recovered.")
        }
        if let first, let control, control.events.contains(where: { $0.signal == first.signal }) { conflicts.append("The control run also contains \(first.signal.rawValue.lowercased()) events.") }
        if let control, control.events.contains(where: { $0.signal == .imsLoss }) {
            conflicts.append("The control has an IMS non-registration log entry. An IMS entry alone is not specific to the primary fault.")
        }
        let inference = first.map { "\($0.signal.rawValue) appears first among classified events after the last normal serving-registration entry in the review window. Earlier impairment can remain active across that entry. This does not establish the root cause." } ?? "No SOS-linked fault sequence is available yet. The baseline cannot identify the first failed subsystem."
        let confidence = first == nil ? "None for fault isolation" :
            (lastGood == nil ? "Low for event order; low for cause" : "Moderate for event order; low for cause")
        return FaultAssessment(
            observedFacts: facts, inference: inference, confidence: confidence,
            contradictoryEvidence: conflicts.isEmpty ? ["No contradictory event was established in the available runs."] : conflicts,
            remainingUncertainty: ["The logs do not show why registration changed to emergency only.", "SIM ready does not establish network service, and the public Mac tools do not expose all radio and IMS state.", "An AT&T line, local network, software, or hardware fault remains possible."],
            nextTest: incident == nil ? "Keep the primary SOS watcher active and mark the next visible SOS transition." :
                "Proposed, not authorized: a matched two-line, two-phone crossover to test whether the fault follows the phone or the AT&T line. Obtain owner approval before any eSIM or carrier change."
        )
    }
}
