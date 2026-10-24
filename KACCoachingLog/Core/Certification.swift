import Foundation

/// Who issues the credential. The two bodies use different coaching logs and rules.
enum CertificationBody: String, Codable {
    /// (사)한국코치협회 — the 코칭일지 xlsx form, 30~120 minute sessions, coach-the-coach column.
    case kca
    /// International Coaching Federation — the ICF coaching log (paid / pro bono hours).
    case icf

    var title: String {
        switch self {
        case .kca: return "(사)한국코치협회"
        case .icf: return "국제코칭연맹(ICF)"
        }
    }
}

/// Credential the coach is preparing for. Hours follow the associations' published requirements.
enum Certification: String, CaseIterable, Codable, Identifiable {
    case kac, kpc, ksc
    case acc, pcc, mcc

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var body: CertificationBody {
        switch self {
        case .kac, .kpc, .ksc: return .kca
        case .acc, .pcc, .mcc: return .icf
        }
    }

    /// Coach-specific training hours.
    var educationHours: Int {
        switch self {
        case .kac: return 20
        case .kpc: return 60
        case .ksc: return 150
        case .acc: return 60
        case .pcc: return 125
        case .mcc: return 200
        }
    }

    /// Coaching practice hours to log.
    var practiceHours: Int {
        switch self {
        case .kac: return 50
        case .kpc: return 200
        case .ksc: return 800
        case .acc: return 100
        case .pcc: return 500
        case .mcc: return 2500
        }
    }

    /// KCA: received coach-the-coach that may count toward practice hours.
    var maxCTCHours: Int? {
        switch self {
        case .kac: return 25
        case .kpc: return 80
        case .ksc: return 100
        case .acc, .pcc, .mcc: return nil
        }
    }

    /// ICF: paid hours required within the practice hours.
    var minimumPaidHours: Int? {
        switch self {
        case .acc: return 75
        case .pcc: return 450
        case .mcc: return 2250
        case .kac, .kpc, .ksc: return nil
        }
    }

    /// Mentor coaching hours, outside the log.
    var mentorCoachingHours: Int? {
        switch self {
        case .kac: return nil
        case .kpc: return 5
        case .ksc, .acc, .pcc, .mcc: return 10
        }
    }

    /// KCA: coach-the-coach hours required besides the log (KPC·KSC).
    var requiredCoachTheCoachHours: Int? {
        switch self {
        case .kpc: return 5
        case .ksc: return 10
        case .kac, .acc, .pcc, .mcc: return nil
        }
    }

    /// Minimum number of different clients. Only enforced where the requirement is known.
    var minimumClientCount: Int? {
        switch self {
        case .kac: return 3
        case .acc: return 8
        case .pcc: return 25
        case .mcc: return 35
        case .kpc, .ksc: return nil
        }
    }

    /// KCA form: group coaching up to 1:9. ICF: groups up to 15 people.
    var maxGroupSize: Int { body == .kca ? 9 : 15 }

    /// KCA only accepts 30~120 minute sessions and limits sessions per client per day.
    var limitsSessionLength: Bool { body == .kca }

    /// ICF logs have no coach-the-coach column.
    var countsCoachTheCoach: Bool { body == .kca }

    var sessionKinds: [SessionKind] {
        countsCoachTheCoach ? SessionKind.allCases : [.paid, .free]
    }

    var requiredTotalMinutes: Int { practiceHours * 60 }

    /// KCA rejects sessions with writing errors, so about 10% extra is the safe target (KAC 50 → 55시간).
    var recommendedTotalMinutes: Int {
        body == .kca ? practiceHours * 66 : requiredTotalMinutes
    }

    /// One line per requirement, e.g. ["교육 20시간", "실습 50시간 (CTC 최대 25시간)"].
    var requirementLines: [String] {
        var lines = ["교육 \(educationHours)시간"]
        if let maxCTCHours {
            lines.append("실습 \(practiceHours)시간 (CTC 최대 \(maxCTCHours)시간)")
        } else if let minimumPaidHours {
            lines.append("실습 \(practiceHours)시간 (유료 \(minimumPaidHours)시간 이상)")
        } else {
            lines.append("실습 \(practiceHours)시간")
        }
        if let mentorCoachingHours { lines.append("멘토코칭 \(mentorCoachingHours)시간") }
        if let requiredCoachTheCoachHours { lines.append("코치더코치 \(requiredCoachTheCoachHours)시간") }
        if let minimumClientCount { lines.append("고객 \(minimumClientCount)명 이상") }
        return lines
    }
}
