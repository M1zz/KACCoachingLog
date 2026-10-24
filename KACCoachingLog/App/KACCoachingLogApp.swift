import SwiftData
import SwiftUI

@main
struct KACCoachingLogApp: App {
    @State private var transcriptionCenter = TranscriptionCenter()
    @State private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(transcriptionCenter)
                .appLock(appLock)
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
    /// Credential being prepared for (`Certification.rawValue`).
    static let certificationKey = "certification"
    static let autoTranscribeKey = "autoTranscribe"
    static let requireOnDeviceKey = "requireOnDevice"
    static let recordAudioByDefaultKey = "recordAudioByDefault"
    /// Start of the coach training, as seconds since 1970. 0 = not set.
    static let trainingStartKey = "trainingStartDate"
    static let appLockKey = "appLockEnabled"

    static func trainingStartDate(_ stored: Double) -> Date? {
        stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }
}
