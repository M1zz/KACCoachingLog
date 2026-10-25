import Foundation

// MARK: - Session classification

/// Which column of the KAC coaching log a session belongs to.
enum SessionKind: String, CaseIterable, Codable, Identifiable {
    case paid
    case free
    case coachTheCoach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paid: return String(localized: "유료 코칭")
        case .free: return String(localized: "무료 코칭")
        case .coachTheCoach: return String(localized: "받은 코치더코치")
        }
    }

    var shortTitle: String {
        switch self {
        case .paid: return String(localized: "유료")
        case .free: return String(localized: "무료")
        case .coachTheCoach: return "CTC"
        }
    }
}

/// Rule 8: only face-to-face or remote (phone / video call / Zoom) sessions count.
enum CoachingFormat: String, CaseIterable, Codable, Identifiable {
    case faceToFace
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faceToFace: return String(localized: "대면")
        case .remote: return String(localized: "비대면")
        }
    }

    /// The wording of the official Korean form, whatever the app language.
    var formLabel: String {
        switch self {
        case .faceToFace: return "대면"
        case .remote: return "비대면"
        }
    }
}

/// Rule 6: composition of a received coach-the-coach session.
enum CTCComposition: String, CaseIterable, Codable, Identifiable {
    case oneOnOne
    case oneOnTwo
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneOnOne: return String(localized: "1:1 (2배 인정)")
        case .oneOnTwo: return String(localized: "1:2 (2배 인정)")
        case .group: return String(localized: "그룹 3-5명 (1배 인정)")
        }
    }

    /// Rule 6-③/④: 1:1 and 1:2 count double, group counts once.
    var multiplier: Int {
        switch self {
        case .oneOnOne, .oneOnTwo: return 2
        case .group: return 1
        }
    }

    /// Number of candidates (응시자) in the session.
    func participantCount(groupSize: Int) -> Int {
        switch self {
        case .oneOnOne: return 1
        case .oneOnTwo: return 2
        case .group: return min(max(groupSize, 3), 5)
        }
    }
}

// MARK: - Log entry (framework-free value type used for validation and export)

struct LogEntry: Equatable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    /// For regular coaching: client names. For coach-the-coach: the coach's name (first element).
    var clientNames: [String]
    /// Total number of clients in the session (1 = 1:1). For group CTC: number of candidates.
    var groupSize: Int
    var kind: SessionKind
    var format: CoachingFormat
    var ctcComposition: CTCComposition
    var ctcLicenseNumber: String
    /// When set, replaces the minutes derived from the time range.
    var minutesOverride: Int?

    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        clientNames: [String],
        groupSize: Int = 1,
        kind: SessionKind = .paid,
        format: CoachingFormat = .faceToFace,
        ctcComposition: CTCComposition = .oneOnOne,
        ctcLicenseNumber: String = "",
        minutesOverride: Int? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.clientNames = clientNames
        self.groupSize = groupSize
        self.kind = kind
        self.format = format
        self.ctcComposition = ctcComposition
        self.ctcLicenseNumber = ctcLicenseNumber
        self.minutesOverride = minutesOverride
    }

    /// Trimmed, non-empty client names.
    var cleanedClientNames: [String] {
        clientNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Minutes covered by the written time range (HH:mm-HH:mm), computed on whole minutes
    /// so the minutes column always agrees with the time column.
    var rangeMinutes: Int {
        let startMinute = Int((start.timeIntervalSince1970 / 60).rounded(.down))
        let endMinute = Int((end.timeIntervalSince1970 / 60).rounded(.down))
        return endMinute - startMinute
    }

    /// Minutes written to the sheet (CTC 1:1 / 1:2 are doubled per rule 6-③).
    var recordedMinutes: Int {
        if let minutesOverride { return minutesOverride }
        switch kind {
        case .paid, .free:
            return rangeMinutes
        case .coachTheCoach:
            return rangeMinutes * ctcComposition.multiplier
        }
    }

    var paidMinutes: Int { kind == .paid ? recordedMinutes : 0 }
    var freeMinutes: Int { kind == .free ? recordedMinutes : 0 }
    var ctcMinutes: Int { kind == .coachTheCoach ? recordedMinutes : 0 }

    /// Number of people on the "client" side, used for the 1:N label.
    var participantCount: Int {
        switch kind {
        case .paid, .free:
            return max(groupSize, cleanedClientNames.count, 1)
        case .coachTheCoach:
            return ctcComposition.participantCount(groupSize: groupSize)
        }
    }
}

// MARK: - Sheet text formatting

struct KACFormatter {
    var calendar: Calendar
    var timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// Column A — e.g. "2026-09-11"
    func dateText(_ entry: LogEntry) -> String {
        let c = components(entry.start)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Column B — e.g. "10:00-10:50"
    func timeText(_ entry: LogEntry) -> String {
        let s = components(entry.start)
        let e = components(entry.end)
        return String(format: "%02d:%02d-%02d:%02d", s.hour ?? 0, s.minute ?? 0, e.hour ?? 0, e.minute ?? 0)
    }

    /// Column C — client names (max 3 lines) or "coach name\n/license" for CTC.
    func clientText(_ entry: LogEntry) -> String {
        switch entry.kind {
        case .paid, .free:
            return entry.cleanedClientNames.prefix(3).joined(separator: "\n")
        case .coachTheCoach:
            let coach = entry.cleanedClientNames.first ?? ""
            let license = entry.ctcLicenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if license.isEmpty { return coach }
            return "\(coach)\n/\(license)"
        }
    }

    /// Column G — e.g. "1:1 대면", "1:6 비대면\n(총6명)"
    func formatText(_ entry: LogEntry) -> String {
        let count = entry.participantCount
        let base = "1:\(count) \(entry.format.formLabel)"
        if entry.kind != .coachTheCoach && count >= 3 {
            return "\(base)\n(총\(count)명)"
        }
        return base
    }

    /// Column G in the app language, on one line, e.g. "1:6 Remote (6 total)".
    func formatSummary(_ entry: LogEntry) -> String {
        let count = entry.participantCount
        let base = String(localized: "1:\(count) \(entry.format.title)")
        if entry.kind != .coachTheCoach && count >= 3 {
            return base + " " + String(localized: "(총\(count)명)")
        }
        return base
    }

    /// Whether a row needs the taller (two-line+) height.
    func isMultiline(_ entry: LogEntry) -> Bool {
        clientText(entry).contains("\n") || formatText(entry).contains("\n")
    }

    func dayKey(_ date: Date) -> String {
        let c = components(date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Duration helpers

enum KACDuration {
    /// 170 -> "2시간 50분" (in the app language)
    static func hoursMinutes(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let value = abs(minutes)
        return sign + String(localized: "\(value / 60)시간 \(value % 60)분")
    }

    /// 170 -> "2시간 50분" — the official Korean form's wording, whatever the app language.
    static func formHoursMinutes(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let value = abs(minutes)
        return "\(sign)\(value / 60)시간 \(value % 60)분"
    }

    /// 3725 seconds -> "1:02:05", 125 -> "02:05"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
