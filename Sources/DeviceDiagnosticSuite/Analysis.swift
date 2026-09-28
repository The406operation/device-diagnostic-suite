import Foundation

enum Analysis {
    static let cellularTerms = ["commcenter", "coretelephony", "baseband", "radio", "registration", "no service", "sos", "cellular"]

    static func redact(_ input: String) -> String {
        var text = input
        let patterns: [(String, String)] = [
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#, "[identifier]"),
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b"#, "[device id]"),
            (#"\b(?:serial(?:number)?|imei|imsi|iccid)\s*[:=]\s*[A-Z0-9-]+\b"#, "[device identifier]"),
            (#"\b\d{15,22}\b"#, "[long number]"),
            (#"\b(?:\+?1[-. ]?)?\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}\b"#, "[phone]"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "[ip address]"),
            (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[email]")
        ]
        for (pattern, replacement) in patterns {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return String(text.prefix(2000))
    }

    static func event(from line: String, source: String, redact: Bool = true) -> DiagnosticEvent? {
        let lower = line.lowercased()
        let kind: EventKind
        if lower.contains("airplane") || lower.contains("flight mode") { kind = .airplane }
        else if lower.contains("esim") || lower.contains("euicc") || lower.contains("simstatus") { kind = .esim }
        else if lower.contains("baseband") || lower.contains("modem") { kind = .modem }
        else if lower.contains("call failed") || lower.contains("call dropped") || lower.contains("call failure") { kind = .call }
        else if lower.contains("crash") || lower.contains("panic") || lower.contains("jetsam") { kind = .crash }
        else if ["registration", "no service", "sos", "cellular", "radio access"].contains(where: lower.contains) ||
                    (["commcenter", "coretelephony"].contains(where: lower.contains) &&
                     ["attach", "detach", "reject", "failed", "error", "signal", "service"].contains(where: lower.contains)) { kind = .cellular }
        else { return nil }
        let value = redact ? self.redact(line) : String(line.prefix(2000))
        return DiagnosticEvent(date: date(in: line) ?? Date(), kind: kind,
                               summary: String(value.prefix(180)), source: source, detail: value)
    }

    static func date(in line: String, referenceDate: Date = Date(), timeZone: TimeZone = .current) -> Date? {
        let prefix = String(line.prefix(32))
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "MMM dd HH:mm:ss.SSSSSS", "MMM dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            formatter.defaultDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: referenceDate), month: 1, day: 1))
            let count = format.count
            if prefix.count >= count, let date = formatter.date(from: String(prefix.prefix(count))) { return date }
        }
        return nil
    }

    static func count(_ kind: EventKind, in session: CaptureSession?) -> Int {
        session?.events.filter { $0.kind == kind }.count ?? 0
    }
}
