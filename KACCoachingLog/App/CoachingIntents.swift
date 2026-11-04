//
//  CoachingIntents.swift
//  KACCoachingLog
//
//  코칭 기록을 Siri · Spotlight · 단축어가 알아보게 한다.
//
//  - "코칭일지 세션 녹음 시작" — 코칭이 시작되면 말로 녹음 화면을 연다.
//    녹음은 사용자가 화면에서 직접 시작한다(상대의 동의를 확인하는 자리라 자동으로 켜지 않는다).
//  - Spotlight · Siri: 코칭 기록마다 고객 이름 · 주제 · 메모를 싣는다(iOS 18+). 누르면 그 기록이 열린다.
//    앱 잠금을 켜 두면 기록을 내보이지 않는다 — 잠금 밖에서 고객 이름이 보이면 안 된다.
//

import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

@MainActor @Observable
final class SiriRouter {
    static let shared = SiriRouter()
    /// 늘어날 때마다 첫 화면이 녹음 화면을 연다.
    var recordingRequest = 0
    /// 열어 달라는 코칭 기록. 첫 화면이 고르고 비운다.
    var sessionID: UUID?
}

// MARK: - 녹음

struct OpenRecordingIntent: AppIntent {
    static let title = LocalizedStringResource("세션 녹음", comment: "Siri: open the coaching session recorder")
    static let description = IntentDescription(
        LocalizedStringResource("코칭 세션 녹음 화면을 엽니다.", comment: "Siri: open recording description")
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriRouter.shared.recordingRequest &+= 1
        return .result()
    }
}

// MARK: - 코칭 기록

struct SessionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("코칭 기록", comment: "Siri/Spotlight: one logged coaching session")
    )
    static let defaultQuery = SessionQuery()

    let id: UUID
    let title: String
    let date: String
    /// 고객 이름 · 주제 · 메모. 검색 · 색인에 쓴다.
    let text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(date)")
    }

    init(_ session: CoachingSession) {
        id = session.uuid
        title = session.displayTitle
        date = session.startDate.formatted(date: .abbreviated, time: .shortened)
        text = (session.clientNames + [session.topic, session.notes])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

@available(iOS 18.0, macOS 15.0, *)
extension SessionEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.textContent = text
        return set
    }
}

struct SessionQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SessionEntity] {
        let wanted = Set(identifiers)
        return CoachingLibrary.sessions().filter { wanted.contains($0.uuid) }.map(SessionEntity.init)
    }

    func entities(matching string: String) async throws -> [SessionEntity] {
        CoachingLibrary.search(string)
    }

    /// 최근 코칭부터.
    func suggestedEntities() async throws -> [SessionEntity] {
        CoachingLibrary.sessions().prefix(20).map(SessionEntity.init)
    }
}

/// 코칭 기록을 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenSessionIntent: OpenIntent {
    static let title = LocalizedStringResource("코칭 기록 열기", comment: "Siri/Spotlight: open a logged coaching session")
    static let description = IntentDescription(
        LocalizedStringResource("고른 코칭 기록을 앱에서 엽니다.", comment: "Siri: open session description")
    )

    @Parameter(title: LocalizedStringResource("코칭 기록", comment: "Siri: session parameter"),
               description: LocalizedStringResource("열 코칭 기록. 고객 이름이나 주제로 찾습니다.", comment: "Siri: session parameter description"))
    var target: SessionEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriRouter.shared.sessionID = target.id
        return .result()
    }
}

// MARK: - Siri 문구

struct CoachingLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRecordingIntent(),
            phrases: ["Record a session in \(.applicationName)", "Start a coaching session in \(.applicationName)"],
            shortTitle: "Record Session",
            systemImageName: "mic"
        )
    }
}

// MARK: - 읽기 · 색인

enum CoachingLibrary {
    /// 저장한 코칭 기록, 최근 것부터. '작성 중'은 뺀다. 앱 잠금을 켰으면 아무것도 내보이지 않는다.
    static func sessions() -> [CoachingSession] {
        guard !UserDefaults.standard.bool(forKey: AppSettings.appLockKey) else { return [] }
        let descriptor = FetchDescriptor<CoachingSession>(
            predicate: #Predicate { !$0.isDraft },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? ModelContext(KACCoachingLogApp.container).fetch(descriptor)) ?? []
    }

    /// 고객 이름 · 주제 · 메모에서 찾는다(대소문자 · 악센트 무시).
    static func search(_ raw: String) -> [SessionEntity] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return sessions().map(SessionEntity.init)
            .filter { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Spotlight 에 싣는 기록을 지금 것에 맞춘다. 앱을 열 때와 뒤로 보낼 때 부른다.
    static func reindex() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: SessionEntity.self)
        try? await index.indexAppEntities(sessions().map(SessionEntity.init))
    }
}
