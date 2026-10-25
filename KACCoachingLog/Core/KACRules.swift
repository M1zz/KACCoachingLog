import Foundation

// MARK: - Summary

struct KACSummary: Equatable {
    var entryCount: Int = 0
    var paidMinutes: Int = 0
    /// Free coaching only (column E).
    var freeCoachingMinutes: Int = 0
    /// Received coach-the-coach (column F).
    var ctcMinutes: Int = 0
    var uniqueClientCount: Int = 0

    /// Rule 6-②: received coach-the-coach time is part of the total free time.
    var totalFreeMinutes: Int { freeCoachingMinutes + ctcMinutes }
    var totalMinutes: Int { paidMinutes + totalFreeMinutes }

    init() {}

    /// ICF logs have no coach-the-coach column, so those sessions are left out of the totals.
    init(entries: [LogEntry], certification: Certification = .kac) {
        let counted = certification.countsCoachTheCoach ? entries : entries.filter { $0.kind != .coachTheCoach }
        entryCount = counted.count
        paidMinutes = counted.reduce(0) { $0 + $1.paidMinutes }
        freeCoachingMinutes = counted.reduce(0) { $0 + $1.freeMinutes }
        ctcMinutes = counted.reduce(0) { $0 + $1.ctcMinutes }
        uniqueClientCount = KACValidator.uniqueClients(in: entries).count
    }
}

// MARK: - Validation

struct ValidationIssue: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case warning
        case error

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var id: String { "\(entryID?.uuidString ?? "global")-\(rule)-\(code)" }
    var entryID: UUID?
    var severity: Severity
    /// Rule number from the official notice (1–9). 0 = app-level check.
    var rule: Int
    var code: String
    var message: String
}

enum KACValidator {
    static let minSessionMinutes = 30
    static let maxSessionMinutes = 120
    static let maxSameClientSessionsPerDay = 2

    static func uniqueClients(in entries: [LogEntry]) -> Set<String> {
        var names = Set<String>()
        for entry in entries where entry.kind != .coachTheCoach {
            for name in entry.cleanedClientNames {
                names.insert(normalize(name))
            }
        }
        return names
    }

    static func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "").lowercased()
    }

    static func sorted(_ entries: [LogEntry]) -> [LogEntry] {
        entries.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
    }

    // MARK: Session length

    /// Minutes that may be written to the sheet for one session.
    /// Rule 3: 30...120. Rule 6-③: 1:1·1:2 coach-the-coach is doubled, and the doubled value must be 60...120.
    static func allowedRecordedMinutes(for entry: LogEntry) -> ClosedRange<Int> {
        if entry.kind == .coachTheCoach && entry.ctcComposition.multiplier > 1 {
            return 60...maxSessionMinutes
        }
        return minSessionMinutes...maxSessionMinutes
    }

    /// Real (clock) minutes the written time range may cover. 1:1·1:2 coach-the-coach: 30...60.
    static func allowedRangeMinutes(for entry: LogEntry) -> ClosedRange<Int> {
        let multiplier = entry.kind == .coachTheCoach ? entry.ctcComposition.multiplier : 1
        let recorded = allowedRecordedMinutes(for: entry)
        return (recorded.lowerBound / multiplier)...(recorded.upperBound / multiplier)
    }

    /// Longest real time range the end-time picker allows. Without a length rule (ICF) it is the rest of the day.
    static func maxRangeMinutes(for entry: LogEntry, certification: Certification) -> Int {
        certification.limitsSessionLength ? allowedRangeMinutes(for: entry).upperBound : 24 * 60 - 1
    }

    /// Minutes that may be typed by hand.
    static func typedMinutesRange(for entry: LogEntry, certification: Certification) -> ClosedRange<Int> {
        certification.limitsSessionLength ? allowedRecordedMinutes(for: entry) : 1...(24 * 60)
    }

    /// Human-readable allowed length, e.g. "30~120분" or "실제 30~60분 (2배 60~120분)".
    static func allowedLengthText(for entry: LogEntry) -> String {
        let recorded = allowedRecordedMinutes(for: entry)
        let range = allowedRangeMinutes(for: entry)
        if recorded == range {
            return String(localized: "\(recorded.lowerBound)~\(recorded.upperBound)분")
        }
        return String(localized: "실제 \(range.lowerBound)~\(range.upperBound)분 (2배 \(recorded.lowerBound)~\(recorded.upperBound)분)")
    }

    /// Whether the session length satisfies rule 3 / 6-③, both for the written minutes and the time range.
    static func hasValidLength(_ entry: LogEntry) -> Bool {
        allowedRecordedMinutes(for: entry).contains(entry.recordedMinutes)
            && allowedRangeMinutes(for: entry).contains(entry.rangeMinutes)
    }

    struct LengthFix: Equatable {
        var end: Date
        var minutesOverride: Int?
    }

    /// A safe automatic correction for a length error, or nil when none is needed or possible.
    /// Too long → end time is cut to the maximum. Too short is never padded: the user has to check it.
    static func lengthFix(for entry: LogEntry) -> LengthFix? {
        guard entry.end > entry.start, !hasValidLength(entry) else { return nil }
        let range = allowedRangeMinutes(for: entry)
        if entry.rangeMinutes > range.upperBound {
            let startMinute = (entry.start.timeIntervalSince1970 / 60).rounded(.down) * 60
            return LengthFix(end: Date(timeIntervalSince1970: startMinute + Double(range.upperBound * 60)), minutesOverride: nil)
        }
        if entry.minutesOverride != nil && range.contains(entry.rangeMinutes) {
            // Time range is fine; only the hand-typed minutes are off.
            return LengthFix(end: entry.end, minutesOverride: nil)
        }
        return nil
    }

    static func validate(
        entries: [LogEntry],
        candidateName: String,
        certification: Certification = .kac,
        trainingStartDate: Date? = nil,
        checkTotalHours: Bool = false,
        formatter: KACFormatter = KACFormatter()
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let ordered = sorted(entries)

        // Rule 1 — candidate name
        if candidateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(entryID: nil, severity: .error, rule: 1, code: "candidate",
                                message: String(localized: "응시자 명이 비어 있어요. 설정에서 입력해 주세요.")))
        }

        // Rule 2 — minimum number of clients (KAC 3명, ICF ACC 8명 · PCC 25명 · MCC 35명)
        if !ordered.isEmpty, let minimumClientCount = certification.minimumClientCount {
            let count = uniqueClients(in: ordered).count
            if count < minimumClientCount {
                // Below the final requirement is only a reminder while hours are still being collected.
                let severity: ValidationIssue.Severity = certification == .kac || checkTotalHours ? .error : .warning
                issues.append(.init(entryID: nil, severity: severity, rule: 2, code: "clients",
                                    message: String(localized: "\(certification.title)는 최소 \(minimumClientCount)명 이상의 고객이 필요해요. (현재 \(count)명)")))
            }
        }

        // Per-entry checks
        for entry in ordered {
            issues.append(contentsOf: validate(entry: entry, certification: certification, formatter: formatter))
        }

        // Rule 3 — same client, same day: max 2 sessions, max 120 minutes combined (KCA only)
        var perClientDay: [String: [LogEntry]] = [:]
        for entry in ordered where entry.kind != .coachTheCoach && certification.limitsSessionLength {
            let day = formatter.dayKey(entry.start)
            for name in Set(entry.cleanedClientNames.map(normalize)) {
                perClientDay["\(day)|\(name)", default: []].append(entry)
            }
        }
        for key in perClientDay.keys.sorted() {
            guard let group = perClientDay[key] else { continue }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let day = parts.first ?? ""
            let displayName = group.first?.cleanedClientNames.first { normalize($0) == parts.last } ?? (parts.last ?? "")
            if group.count > maxSameClientSessionsPerDay {
                for entry in group.dropFirst(maxSameClientSessionsPerDay) {
                    issues.append(.init(entryID: entry.id, severity: .error, rule: 3, code: "sameDayCount-\(key)",
                                        message: String(localized: "\(day)에 \(displayName) 님 코칭이 \(group.count)회예요. 같은 날 동일인은 2회까지만 인정돼요.")))
                }
            }
            let combined = group.prefix(maxSameClientSessionsPerDay).reduce(0) { $0 + $1.recordedMinutes }
            if group.count >= 2 && combined > maxSessionMinutes, let last = group.prefix(maxSameClientSessionsPerDay).last {
                issues.append(.init(entryID: last.id, severity: .error, rule: 3, code: "sameDayMinutes-\(key)",
                                    message: String(localized: "\(day)에 \(displayName) 님 코칭 합계가 \(combined)분이에요. 하루 2회 합산 최대 120분이에요.")))
            }
        }

        // App-level — overlapping sessions look like writing errors
        if ordered.count > 1 {
            for index in 1..<ordered.count {
                let previous = ordered[index - 1]
                let current = ordered[index]
                if current.start < previous.end {
                    issues.append(.init(entryID: current.id, severity: .warning, rule: 4, code: "overlap",
                                        message: String(localized: "\(formatter.dateText(current)) \(formatter.timeText(previous)) 세션과 시간이 겹쳐요.")))
                }
            }
        }

        // Practice only counts from the day the coach training started.
        if let trainingStartDate {
            let trainingDay = formatter.dayKey(trainingStartDate)
            for entry in ordered where formatter.dayKey(entry.start) < trainingDay {
                issues.append(.init(entryID: entry.id, severity: .error, rule: 0, code: "beforeTraining",
                                    message: String(localized: "\(formatter.dateText(entry)) \(formatter.timeText(entry)): 코칭 교육 시작일(\(trainingDay)) 이전 코칭은 인정되지 않아요. 삭제해 주세요.")))
            }
        } else if !ordered.isEmpty {
            issues.append(.init(entryID: nil, severity: .warning, rule: 0, code: "trainingStart",
                                message: String(localized: "코칭 교육 시작일을 설정에 입력하면 그 이전 코칭을 찾아드려요.")))
        }

        // Total hours — e.g. KAC 50 hours required, 55–60 hours recommended as a margin
        if checkTotalHours && !ordered.isEmpty {
            let summary = KACSummary(entries: ordered, certification: certification)
            let total = summary.totalMinutes
            let name = certification.title
            if total < certification.requiredTotalMinutes {
                issues.append(.init(entryID: nil, severity: .warning, rule: 0, code: "totalRequired",
                                    message: String(localized: "총 코칭시간이 \(KACDuration.hoursMinutes(total))이에요. \(name)는 \(certification.practiceHours)시간이 필요해요.")))
            } else if total < certification.recommendedTotalMinutes {
                let recommendedHours = certification.recommendedTotalMinutes / 60
                issues.append(.init(entryID: nil, severity: .warning, rule: 0, code: "totalMargin",
                                    message: String(localized: "총 코칭시간이 \(KACDuration.hoursMinutes(total))이에요. 일부 세션이 탈락할 수 있으니 \(recommendedHours)시간 이상으로 넉넉히 채우는 것이 안전해요.")))
            }
            // ICF — paid hours within the total
            if let minimumPaidHours = certification.minimumPaidHours, summary.paidMinutes < minimumPaidHours * 60 {
                issues.append(.init(entryID: nil, severity: .warning, rule: 0, code: "paidRequired",
                                    message: String(localized: "유료 코칭이 \(KACDuration.hoursMinutes(summary.paidMinutes))이에요. \(name)는 유료 \(minimumPaidHours)시간 이상이 필요해요.")))
            }
        }

        // Rule 6-① — received coach-the-coach cap (KAC 25 · KPC 80 · KSC 100시간)
        let ctcTotal = ordered.reduce(0) { $0 + $1.ctcMinutes }
        if let maxCTCHours = certification.maxCTCHours, ctcTotal > maxCTCHours * 60 {
            issues.append(.init(entryID: nil, severity: .error, rule: 6, code: "ctcTotal",
                                message: String(localized: "받은 코치더코치가 \(KACDuration.hoursMinutes(ctcTotal))이에요. \(certification.title)는 최대 \(maxCTCHours)시간까지만 작성할 수 있어요.")))
        }

        return issues.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.rule < $1.rule
        }
    }

    static func validate(
        entry: LogEntry,
        certification: Certification = .kac,
        formatter: KACFormatter = KACFormatter()
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func add(_ severity: ValidationIssue.Severity, _ rule: Int, _ code: String, _ message: String) {
            issues.append(.init(entryID: entry.id, severity: severity, rule: rule, code: code, message: message))
        }
        let label = "\(formatter.dateText(entry)) \(formatter.timeText(entry))"

        if entry.end <= entry.start {
            add(.error, 1, "range", String(localized: "\(label): 종료 시각이 시작 시각보다 늦어야 해요."))
            return issues
        }
        if formatter.dayKey(entry.start) != formatter.dayKey(entry.end) {
            add(.warning, 1, "crossDay", String(localized: "\(label): 날짜를 넘기는 세션이에요. 날짜별로 나눠 적는 것이 안전해요."))
        }
        if entry.recordedMinutes <= 0 {
            add(.error, 1, "minutes", String(localized: "\(label): 코칭 시간(분)이 비어 있어요."))
        }

        if certification.body == .icf {
            validateICF(entry, label: label, certification: certification, add: add)
            return issues
        }

        switch entry.kind {
        case .paid, .free:
            // Rule 1 — client name
            if entry.cleanedClientNames.isEmpty {
                add(.error, 1, "clientName", String(localized: "\(label): 고객명이 비어 있어요."))
            }
            // Rule 3 — 30...120 minutes
            checkLength(entry, label: label, code: "length", add: add)
            // Minutes must agree with the time range
            if entry.minutesOverride != nil && entry.minutesOverride != entry.rangeMinutes {
                add(.warning, 1, "mismatch", String(localized: "\(label): 적은 시간(\(entry.recordedMinutes)분)이 시간 범위(\(entry.rangeMinutes)분)와 달라요."))
            }
            // Rule 7 — group coaching up to 1:9
            if entry.participantCount > certification.maxGroupSize {
                add(.error, 7, "groupSize", String(localized: "\(label): 그룹코칭은 최대 1:9(총 9명)까지만 작성할 수 있어요."))
            }
            if entry.participantCount > 1 && entry.cleanedClientNames.count < min(entry.participantCount, 3) {
                add(.warning, 1, "groupNames", String(localized: "\(label): 그룹코칭은 고객명을 3명(3인 미만이면 전원)까지 적어야 해요."))
            }

        case .coachTheCoach:
            if entry.cleanedClientNames.isEmpty {
                add(.error, 6, "ctcCoach", String(localized: "\(label): 코치더코치를 해준 코치 이름이 비어 있어요."))
            }
            let license = entry.ctcLicenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if license.isEmpty {
                add(.error, 6, "ctcLicense", String(localized: "\(label): 코치더코치 코치의 인증자격번호가 비어 있어요."))
            } else if license.range(of: "^K[APS]C[0-9]+$", options: .regularExpression) == nil {
                add(.warning, 6, "ctcLicenseFormat", String(localized: "\(label): 자격번호 형식(예: KPC00000)을 확인해 주세요. 한국코치협회 인증 코치만 인정돼요."))
            }
            switch entry.ctcComposition {
            case .oneOnOne, .oneOnTwo:
                // Rule 6-③ — doubled minutes must be 60...120 (real time 30...60)
                checkLength(entry, label: label, code: "ctcDoubled", add: add)
            case .group:
                checkLength(entry, label: label, code: "ctcLength", add: add)
                if entry.groupSize < 3 || entry.groupSize > 5 {
                    add(.warning, 6, "ctcGroupSize", String(localized: "\(label): 그룹 코치더코치는 응시자 3-5명 구성이에요."))
                }
            }
            if entry.minutesOverride != nil && entry.minutesOverride != entry.rangeMinutes * entry.ctcComposition.multiplier {
                add(.warning, 6, "ctcMismatch", String(localized: "\(label): 적은 시간이 시간 범위×\(entry.ctcComposition.multiplier)배와 달라요."))
            }
        }
        return issues
    }

    /// ICF log: client name, group size and paid / pro bono hours. No per-session length limit.
    private static func validateICF(
        _ entry: LogEntry,
        label: String,
        certification: Certification,
        add: (ValidationIssue.Severity, Int, String, String) -> Void
    ) {
        if entry.kind == .coachTheCoach {
            add(.warning, 0, "icfCTC", String(localized: "\(label): 받은 코치더코치는 ICF 코칭 로그 시간에 포함되지 않아요."))
            return
        }
        if entry.cleanedClientNames.isEmpty {
            add(.error, 1, "clientName", String(localized: "\(label): 고객명이 비어 있어요."))
        }
        if entry.participantCount > certification.maxGroupSize {
            add(.error, 7, "groupSize", String(localized: "\(label): ICF 그룹코칭은 최대 \(certification.maxGroupSize)명까지예요."))
        }
        if entry.minutesOverride != nil && entry.minutesOverride != entry.rangeMinutes {
            add(.warning, 1, "mismatch", String(localized: "\(label): 적은 시간(\(entry.recordedMinutes)분)이 시간 범위(\(entry.rangeMinutes)분)와 달라요."))
        }
    }

    /// Rule 3 / 6-③ — length of one session, checked on the written minutes and on the real time range.
    private static func checkLength(
        _ entry: LogEntry,
        label: String,
        code: String,
        add: (ValidationIssue.Severity, Int, String, String) -> Void
    ) {
        let rule = code == "ctcDoubled" ? 6 : 3
        let minutes = entry.recordedMinutes
        let allowed = allowedRecordedMinutes(for: entry)
        let lengthText = allowedLengthText(for: entry)
        let isDoubled = allowed != allowedRangeMinutes(for: entry)
        let limit = isDoubled
            ? String(localized: "1:1·1:2 코치더코치는 \(lengthText)만 인정돼요.")
            : String(localized: "한 세션은 \(lengthText)만 인정돼요.")
        guard minutes > 0 else { return }

        if minutes > allowed.upperBound {
            add(.error, rule, code, String(localized: "\(label): \(minutes)분이에요. \(limit) 종료 시각을 줄여 주세요."))
        } else if minutes < allowed.lowerBound {
            add(.error, rule, code, String(localized: "\(label): \(minutes)분이에요. \(limit) 시간을 확인하거나 이 기록을 삭제해 주세요."))
        } else if entry.minutesOverride != nil && !allowedRangeMinutes(for: entry).contains(entry.rangeMinutes) {
            // Typed minutes look fine, but the written time range breaks the limit.
            add(.error, rule, "\(code)Range", String(localized: "\(label): 분은 \(minutes)분으로 적었지만 시간 범위가 \(entry.rangeMinutes)분이에요. 시간 범위도 \(lengthText) 안이어야 해요."))
        }
    }
}
