import Foundation
import LeeoKit

/// LeeoKit 은 팁 화면에만 쓴다.
/// ⚠️ 여기서 bootstrap · 피드백 · 분석을 켜지 않는다 — 계약을 채우는 값일 뿐 아무것도 돌지 않는다.
/// 코칭 기록은 기기 밖으로 나가지 않는다는 약속(PRIVACY.md)을 그대로 지킨다.
enum KACCoachingLogSpec: LeeoAppSpec {
    static let appName = "코칭일지"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(
        containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
        appIdentifier: "com.leeo.KACCoachingLog"
    )
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/KACCoachingLog/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/KACCoachingLog/support.html")!
    )
    static let monetization = LeeoMonetization.free

    /// 무료 앱이라 LeeoStore 가 없다 — 팁만 혼자 받는다(앱을 열 때 `startStandalone()`, → KACCoachingLogApp).
    /// 소모성 상품 셋, 작은 것부터. ⚠️ 기능을 여는 상품이 아니다.
    @MainActor static let tipJar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: [
        "com.leeo.KACCoachingLog.tip.small",
        "com.leeo.KACCoachingLog.tip.medium",
        "com.leeo.KACCoachingLog.tip.large",
    ]))
}

/// 팁을 부탁할 만한 순간 — 이 앱에 기록한 코칭 시간. 코칭 하나를 마칠 때마다 는다.
enum KACCoachingLogTipMoments {
    /// 기록한 코칭 시간(시간). 큰 것부터.
    static let hours = [100, 50, 20]

    /// 넘어선 순간, 인상적인 것부터.
    static func reached(totalMinutes: Int) -> [LeeoTipMoment] {
        let h = totalMinutes / 60
        return hours.filter { h >= $0 }.map { threshold in
            LeeoTipMoment(id: "hours.\(threshold)",
                          message: String(localized: "지금까지 코칭 \(h)시간을 기록했어요",
                                          comment: "Tip ask card: total coaching hours the person has logged"))
        }
    }
}
