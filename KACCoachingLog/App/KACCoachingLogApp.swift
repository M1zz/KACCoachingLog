import SwiftData
import SwiftUI
import LeeoKit

@main
struct KACCoachingLogApp: App {
    @State private var transcriptionCenter = TranscriptionCenter()
    @State private var appLock: AppLock

    init() {
        // 백업 금고는 맨 먼저 — 예약된 복원을 저장소와 설정(UserDefaults)을 읽기 전에 적용한다.
        // AppLock 은 만들 때 설정을 읽으므로 그 뒤에 만든다.
        LeeoVault.start(KACCoachingLogSpec.self)
        _appLock = State(initialValue: AppLock())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(transcriptionCenter)
                .appLock(appLock)
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(KACCoachingLogSpec.self)
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
    static let container: ModelContainer = {
        let schema = Schema([CoachingSession.self])
        do {
            // 기록은 사용자의 iCloud(개인 데이터베이스)에 백업된다. 개발자는 볼 수 없다.
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.leeo.KACCoachingLog"))
            return try ModelContainer(for: schema, configurations: configuration)
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
    /// 녹음 파일도 iCloud 에 올릴지. 기본은 꺼짐 — 기록과 텍스트만 올라간다.
    static let backupAudioKey = "backupAudio"
    /// Start of the coach training, as seconds since 1970. 0 = not set.
    static let trainingStartKey = "trainingStartDate"
    static let appLockKey = "appLockEnabled"
    /// 직접 입력할 때 종료 시각을 채우는 코칭 길이(분).
    static let defaultSessionMinutesKey = "defaultSessionMinutes"
    static let defaultSessionMinutesFallback = 50

    /// 고를 수 있는 기본 시간. 한국코치협회는 인정 범위(30~120분) 안에서만.
    static func defaultSessionMinutesRange(for certification: Certification) -> ClosedRange<Int> {
        certification.limitsSessionLength ? KACValidator.minSessionMinutes...KACValidator.maxSessionMinutes : 5...240
    }

    /// 저장된 기본 시간. 자격증을 바꿔 범위를 벗어났으면 범위 안으로 맞춘다.
    static func defaultSessionMinutes(for certification: Certification) -> Int {
        let stored = UserDefaults.standard.object(forKey: defaultSessionMinutesKey) as? Int ?? defaultSessionMinutesFallback
        let range = defaultSessionMinutesRange(for: certification)
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    static func trainingStartDate(_ stored: Double) -> Date? {
        stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }
}
