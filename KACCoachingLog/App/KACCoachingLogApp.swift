import SwiftData
import SwiftUI
#if os(iOS)
import LeeoKit
#endif

@main
struct KACCoachingLogApp: App {
    @State private var transcriptionCenter = TranscriptionCenter()
    @State private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(transcriptionCenter)
                .appLock(appLock)
                // 팁 상품을 불러오고 끝나지 않은 팁을 마저 센다 (무료 앱이라 LeeoStore 대신 혼자)
                .task { await KACCoachingLogSpec.tipJar.startStandalone() }
                #if os(iOS)
                // 창 크기로 접힘을 재서 아래로 흘린다. 시트 · 알림창도 접힌 선을 비킨다 (LeeoKit Fold).
                .foldAware()
                #endif
                .storeFallbackNotice()
        }
        .modelContainer(Self.container)
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

    /// `.modelContainer(for:)` 는 저장소를 못 열면 앱을 죽인다 — 그러면 켤 때마다 죽고 고칠 길도 없다.
    /// 손으로 열고, 실패하면 디스크의 기록은 그대로 둔 채 이번 실행만 메모리에서 연다.
    private static let container: ModelContainer = {
        let schema = Schema([CoachingSession.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            return StoreFallback.memoryContainer(schema: schema, after: error)
        }
    }()
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
