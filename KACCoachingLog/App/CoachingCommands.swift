import SwiftUI

/// 메뉴 막대의 명령 — Mac 과 iPad(iPadOS 26 메뉴 막대)에서 앱이 하는 일을 모두 메뉴에 둔다(HIG).
/// 일은 지금 앞에 있는 창의 RootView 가 한다: 그 창이 `focusedSceneValue` 로 할 일을 건네준다.
struct CoachingActions {
    var record: () -> Void
    var manualEntry: () -> Void
    var importAudio: () -> Void
    var calendar: () -> Void
    var export: () -> Void
}

extension FocusedValues {
    @Entry var coachingActions: CoachingActions?
}

struct CoachingCommands: Commands {
    @FocusedValue(\.coachingActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("코칭 시작") { actions?.record() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("직접 입력") { actions?.manualEntry() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(actions == nil)
            Button("오디오 파일 가져오기") { actions?.importAudio() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("엑셀로 내보내기") { actions?.export() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("달력") { actions?.calendar() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions == nil)
            Divider()
        }
    }
}
