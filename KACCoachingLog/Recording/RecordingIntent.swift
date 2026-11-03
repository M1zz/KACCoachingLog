//
//  RecordingIntent.swift
//  KACCoachingLog
//
//  "코칭일지 세션 녹음 시작" — 코칭이 시작되면 말로 녹음 화면을 연다.
//  녹음은 사용자가 화면에서 직접 시작한다(상대의 동의를 확인하는 자리라 자동으로 켜지 않는다).
//

import AppIntents
import Foundation

@MainActor @Observable
final class RecordingRouter {
    static let shared = RecordingRouter()
    /// 늘어날 때마다 첫 화면이 녹음 화면을 연다.
    var request = 0
}

struct OpenRecordingIntent: AppIntent {
    static let title = LocalizedStringResource("세션 녹음", comment: "Siri: open the coaching session recorder")
    static let description = IntentDescription(
        LocalizedStringResource("코칭 세션 녹음 화면을 엽니다.", comment: "Siri: open recording description")
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingRouter.shared.request &+= 1
        return .result()
    }
}

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
