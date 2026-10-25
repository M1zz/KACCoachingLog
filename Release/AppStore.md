# App Store 제출 자료 (1.0)

스토어 문구는 `APPSTORE.md`, 릴리즈 노트는 `RELEASE_NOTES.md`, 스크린샷은 `docs/screenshots/`가 원본이고 DeployBar가 배포할 때 올립니다.
여기에는 App Store Connect에서 사람이 한 번 답하는 항목과 심사 메모만 남깁니다.

## 기본 정보

| 항목 | 값 |
| --- | --- |
| 번들 ID | com.leeo.KACCoachingLog |
| 버전 / 빌드 | 1.0 / 1 |
| 플랫폼 | iOS 17 이상, macOS 14 이상 (같은 타깃, 유니버설 구입 가능) |
| 카테고리 | 생산성 (보조: 비즈니스) |
| 연령 등급 | 4+ (설문 전 항목 "없음") |
| 가격 | 무료 |
| 수출 규정 | 암호화 사용 안 함 (Info.plist `ITSAppUsesNonExemptEncryption = NO`, 제출 시 질문 없음) |

## 앱 개인정보 보호 (영양성분표)

"데이터를 수집하지 않음"을 선택합니다.
근거: 서버·분석·광고 SDK 없음, 모든 기록과 녹음은 기기에만 저장. `PrivacyInfo.xcprivacy`에도 수집 데이터 없음, 추적 없음으로 선언되어 있습니다.

## 심사 메모 (App Review Information)

로그인 없음. 데모 계정 필요 없음.

```
No account is required. To try the app: tap the record button, enter a client name, and start a session (or use the timer if you prefer not to record audio). End the session to create a log entry, then tap the share button to export the coaching log file. The credential can be changed in Settings. All data stays on the device. The microphone is used only to record coaching sessions, and speech recognition is used only to transcribe them.
```

## 스크린샷 다시 만들기

```
Scripts/capture_screenshots.sh <시뮬레이터용 Debug 빌드의 KACCoachingLog.app>
python3 Scripts/make_marketing_screenshots.py
python3 Scripts/make_creative_assets.py
```

캡처는 Debug 빌드의 스크린샷 모드(`App/ScreenshotSupport.swift`)로 언어마다 가상의 샘플 데이터를 띄웁니다.
한국어는 KAC, 영어는 ICF ACC 화면입니다.
