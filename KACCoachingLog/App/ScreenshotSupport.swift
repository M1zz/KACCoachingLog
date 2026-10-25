#if DEBUG
import Foundation
import SwiftData

/// App Store screenshot mode, Debug builds only. Launch arguments:
///   -screenshotSeed            replace all records with fictional sample sessions
///   -screenshotSeedWithError   same, plus one over-long session to show the length check
///   -screenshotScreen <name>   open detail | recording | export | settings | manual
///   -screenshotCert <raw>      credential to select (default kac)
enum ScreenshotSupport {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isSeeding: Bool {
        arguments.contains("-screenshotSeed") || arguments.contains("-screenshotSeedWithError")
    }

    static var screen: String? { value(after: "-screenshotScreen") }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Sample text follows the app language so each App Store locale shows its own screens.
    private static let isKorean = Bundle.main.preferredLocalizations.first == "ko"

    private static let clients = isKorean
        ? ["김민준", "이서연", "박지호", "최하은", "정우진", "강예린", "윤도현", "한소율"]
        : ["Emma Clarke", "Noah Bennett", "Olivia Hayes", "Liam Foster", "Ava Mitchell", "Ethan Reed", "Mia Turner", "Lucas Grant"]
    private static let topics = isKorean
        ? ["리더십 전환", "커리어 방향", "팀 소통", "일과 삶의 균형", "목표 설정", "자기 확신"]
        : ["Leadership transition", "Career direction", "Team communication", "Work-life balance", "Goal setting", "Self-confidence"]
    private static let mentor = isKorean ? "오정민" : "Jordan Ellis"
    static var recordingClient: String { clients[1] }

    /// Wipes existing sessions and inserts about 38 hours of valid KAC practice. Returns the newest session.
    @discardableResult
    static func seed(_ context: ModelContext) -> CoachingSession? {
        try? context.delete(model: CoachingSession.self)

        let defaults = UserDefaults.standard
        let certification = value(after: "-screenshotCert") ?? Certification.kac.rawValue
        defaults.set(certification, forKey: AppSettings.certificationKey)
        defaults.set(isKorean ? "이하늘" : "Hannah Lee", forKey: AppSettings.candidateNameKey)
        defaults.set(false, forKey: AppSettings.appLockKey)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        let firstDay = calendar.date(byAdding: .day, value: -58, to: today) ?? today
        defaults.set(calendar.date(byAdding: .day, value: -3, to: firstDay)?.timeIntervalSince1970, forKey: AppSettings.trainingStartKey)

        let lengths = [50, 60, 45, 60, 90, 50, 60, 40]
        let hours = [10, 14, 19, 9, 20, 16, 11, 18]
        var newest: CoachingSession?
        for index in 0..<40 {
            guard let day = calendar.date(byAdding: .day, value: index * 58 / 40, to: firstDay),
                  let start = calendar.date(bySettingHour: hours[index % hours.count], minute: index % 3 == 0 ? 30 : 0, second: 0, of: day)
            else { continue }
            let minutes = lengths[index % lengths.count]
            let session = CoachingSession(
                startDate: start,
                endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
                clientNames: [clients[index % clients.count]],
                kind: index % 4 == 3 ? .free : .paid,
                format: index % 3 == 0 ? .faceToFace : .remote
            )
            if index % 9 == 4 {
                // Group coaching with three named clients
                session.groupSize = 4
                session.clientNames = [clients[(index + 1) % 8], clients[(index + 2) % 8], clients[(index + 3) % 8]]
            }
            if index % 10 == 7 && Certification(rawValue: certification)?.body == .kca {
                session.kind = .coachTheCoach
                session.clientNames = [mentor]
                session.ctcLicenseNumber = "KPC01234"
                session.endDate = start.addingTimeInterval(50 * 60)
            }
            session.topic = topics[index % topics.count]
            context.insert(session)
            newest = session
        }

        if let newest {
            newest.topic = topics[0]
            newest.notes = isKorean
                ? "새 팀장 역할에서 위임할 일 세 가지를 정함. 다음 세션에 실행 결과 나누기."
                : "Chose three tasks to delegate in the new team lead role. Review how it went next session."
            newest.transcriptionState = .completed
            newest.transcriptionEngine = "SpeechAnalyzer"
            let lines = isKorean
                ? ["오늘은 어떤 이야기를 나누고 싶으세요?",
                   "팀장이 되고 나서 일을 혼자 다 붙잡고 있는 것 같아요.",
                   "다 붙잡고 있다는 건 어떤 모습인가요?",
                   "보고서를 제가 다시 고치고, 회의도 제가 다 들어가요."]
                : ["What would you like to talk about today?",
                   "Since becoming a team lead, I feel like I'm holding on to everything myself.",
                   "What does holding on to everything look like?",
                   "I rewrite every report myself, and I sit in on every meeting."]
            let times: [(TimeInterval, TimeInterval)] = [(4, 12), (13, 31), (32, 44), (45, 70)]
            newest.transcriptSegments = zip(times, lines).map { TranscriptSegment(start: $0.0, end: $0.1, text: $1) }
            newest.transcript = newest.transcriptSegments.map(\.text).joined(separator: "\n")
        }

        if arguments.contains("-screenshotSeedWithError"), let last = newest {
            let start = last.startDate.addingTimeInterval(-26 * 3600)
            let long = CoachingSession(startDate: start, endDate: start.addingTimeInterval(135 * 60),
                                       clientNames: [clients[5]], kind: .paid, format: .remote)
            long.topic = topics[1]
            context.insert(long)
            newest = long
        }
        try? context.save()
        return newest
    }
}
#endif
