import SwiftData
import SwiftUI

@main
struct KACCoachingLogApp: App {
    @State private var transcriptionCenter = TranscriptionCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(transcriptionCenter)
        }
        .modelContainer(for: CoachingSession.self)
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 520, height: 560)
        }
        #endif
    }
}

enum AppSettings {
    static let candidateNameKey = "candidateName"
    static let goalHoursKey = "goalHours"
    static let autoTranscribeKey = "autoTranscribe"
    static let requireOnDeviceKey = "requireOnDevice"
    static let recordAudioByDefaultKey = "recordAudioByDefault"

    static let defaultGoalHours = 50
}
