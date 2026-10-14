import LocalAuthentication
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Privacy lock: when enabled in Settings, the app opens locked and locks again in the background.
/// Unlocking uses Face ID / Touch ID with the device passcode as fallback.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var errorMessage: String?
    /// Prompt automatically once per lock, so cancelling doesn't bring the prompt back in a loop.
    private var didAutoPrompt = false

    init() {
        isLocked = Self.isEnabled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.appLockKey)
    }

    func lock() {
        guard Self.isEnabled, !isLocked else { return }
        isLocked = true
        didAutoPrompt = false
        errorMessage = nil
    }

    func promptIfNeeded() async {
        guard isLocked, !didAutoPrompt else { return }
        didAutoPrompt = true
        await unlock()
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await Self.authenticate(reason: String(localized: "코칭 기록을 보려면 잠금을 해제해 주세요."))
        switch result {
        case .success:
            isLocked = false
            errorMessage = nil
        case .failure(let message):
            errorMessage = message
        }
    }

    enum AuthResult {
        case success
        /// nil when the user cancelled.
        case failure(String?)
    }

    static func authenticate(reason: String) async -> AuthResult {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(String(localized: "이 기기에 암호가 설정되어 있지 않아 잠금을 사용할 수 없어요. 기기 설정에서 암호를 먼저 설정해 주세요."))
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return .success
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            return .failure(nil)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static var biometryIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open.fill"
        }
    }
}

// MARK: - Lock screen

struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("코칭일지가 잠겨 있어요")
                    .font(.title2.bold())
                if lock.isLocked {
                    Text("고객 정보 보호를 위해 Face ID 또는 기기 암호로 잠금을 해제해 주세요.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let message = lock.errorMessage {
                        Text(message)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("잠금 해제", systemImage: AppLock.biometryIcon)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.isAuthenticating)
                }
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
    }
}

// MARK: - Root modifier

extension View {
    /// Covers the app while locked, and (iOS) in the app switcher so no record is visible.
    func appLock(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

private struct AppLockModifier: ViewModifier {
    let lock: AppLock

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.appLockKey) private var enabled = false
    #if os(iOS)
    @State private var overlay = LockOverlayWindows()
    #endif

    private var showsShield: Bool {
        guard enabled else { return false }
        #if os(iOS)
        // Also hide content while inactive, so the app switcher snapshot shows nothing.
        return lock.isLocked || scenePhase != .active
        #else
        return lock.isLocked
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if showsShield {
                    LockScreen(lock: lock)
                }
            }
            #if os(iOS)
            .onChange(of: showsShield, initial: true) { _, show in
                // Sheets sit above the root view, so a separate window covers them too.
                overlay.update(show: show, lock: lock)
            }
            #endif
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    lock.lock()
                case .active:
                    Task { await lock.promptIfNeeded() }
                default:
                    break
                }
            }
    }
}

#if os(iOS)
@MainActor
private final class LockOverlayWindows {
    private var windows: [UIWindow] = []

    func update(show: Bool, lock: AppLock) {
        if show {
            guard windows.isEmpty else { return }
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.rootViewController = UIHostingController(rootView: LockScreen(lock: lock))
                window.isHidden = false
                windows.append(window)
            }
        } else {
            windows.forEach { $0.isHidden = true }
            windows.removeAll()
        }
    }
}
#endif
