import Foundation

/// Builds a CSV with the columns of the ICF coaching log (Client Name … Pro Bono Hours), one row per session.
/// Excel opens it directly; the UTF-8 BOM keeps Korean names readable.
struct ICFLogBuilder {
    var candidateName: String
    var entries: [LogEntry]
    var formatter: KACFormatter = KACFormatter()

    static let header = [
        "Client Name", "Contact Information", "Individual/Group", "Number in Group",
        "Start Date", "End Date", "Paid Hours", "Pro Bono Hours",
    ]

    /// Coach-the-coach is not part of an ICF log.
    var rows: [[String]] {
        KACValidator.sorted(entries)
            .filter { $0.kind != .coachTheCoach }
            .map { entry in
                let count = entry.participantCount
                let date = formatter.dateText(entry)
                return [
                    entry.cleanedClientNames.joined(separator: ", "),
                    "",
                    count > 1 ? "Group" : "Individual",
                    count > 1 ? "\(count)" : "",
                    date,
                    date,
                    entry.kind == .paid ? Self.hours(entry.recordedMinutes) : "",
                    entry.kind == .free ? Self.hours(entry.recordedMinutes) : "",
                ]
            }
    }

    func csv() -> String {
        let summary = KACSummary(entries: entries, certification: .acc)
        var lines: [[String]] = []
        if !candidateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(["Coach Name", candidateName.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        lines.append(Self.header)
        lines.append(contentsOf: rows)
        lines.append(["Total", "", "", "", "", "",
                      Self.hours(summary.paidMinutes), Self.hours(summary.freeCoachingMinutes)])
        return lines.map { $0.map(Self.escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    func build() -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv().utf8)
    }

    /// 50 → "0.83", 90 → "1.5"
    static func hours(_ minutes: Int) -> String {
        let value = (Double(minutes) / 60 * 100).rounded() / 100
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
