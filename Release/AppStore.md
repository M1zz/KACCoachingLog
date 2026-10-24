# App Store 제출 자료 (1.0)

App Store Connect에 그대로 붙여넣을 수 있게 정리했습니다. 글자 수 제한은 괄호 안에 적었습니다.

## 기본 정보

| 항목 | 값 |
| --- | --- |
| 번들 ID | com.leeo.KACCoachingLog |
| 버전 / 빌드 | 1.0 / 1 |
| 플랫폼 | iOS 17 이상, macOS 14 이상 (같은 타깃, 유니버설 구입 가능) |
| 카테고리 | 생산성 (보조: 비즈니스) |
| 연령 등급 | 4+ (설문 전 항목 "없음") |
| 가격 | 무료 |
| 개인정보처리방침 URL | https://m1zz.github.io/KACCoachingLog/privacy.html |
| 마케팅 URL | https://m1zz.github.io/KACCoachingLog/ |
| 지원 URL | https://github.com/M1zz/KACCoachingLog/issues |
| 수출 규정 | 암호화 사용 안 함 (Info.plist `ITSAppUsesNonExemptEncryption = NO`, 제출 시 질문 없음) |

## 앱 개인정보 보호 (영양성분표)

"데이터를 수집하지 않음"을 선택합니다.
근거: 서버·분석·광고 SDK 없음, 모든 기록과 녹음은 기기에만 저장. `PrivacyInfo.xcprivacy`에도 수집 데이터 없음, 추적 없음으로 선언되어 있습니다.

## 한국어 (기본 언어)

**이름** (30자)
```
코칭일지: 코치 자격 실습 기록
```

**부제** (30자)
```
녹음하면 코칭일지가 완성돼요
```

**프로모션 텍스트** (170자)
```
KAC KPC KSC부터 ICF ACC PCC MCC까지, 준비 중인 코치 자격증을 고르면 필요한 실습 시간과 작성 규칙에 맞춰 코칭 기록을 점검해 드려요.
```

**키워드** (100자, 쉼표 구분 공백 없이)
```
코치,코칭,코칭일지,코칭로그,실습시간,코치더코치,자격증,녹음,텍스트변환,한국코치협회,멘토코칭
```

**설명** (4000자)
```
코칭을 녹음하면 날짜와 시간, 분이 자동으로 기록되고 대화는 텍스트로 변환돼요. 버튼 한 번으로 제출용 코칭일지 엑셀 파일을 만들 수 있어요.

준비 중인 자격증에 맞춰요
한국코치협회 KAC, KPC, KSC와 국제코칭연맹(ICF) ACC, PCC, MCC 중에서 고르면 목표 실습 시간, 코치더코치 인정 한도, 유료 코칭 최소 시간, 고객 수 기준에 맞춰 기록을 점검해요.

코칭 녹음과 타이머
시작 버튼을 누른 순간이 시작 시각, 종료 버튼을 누른 순간이 종료 시각이 돼요. 녹음 동의가 없을 때는 타이머로 시간만 기록할 수 있어요. 전화가 오면 일시정지되고, 잠금 화면에서도 녹음이 이어져요.

기기 안에서 텍스트 변환
iOS 26과 macOS 26 이상에서는 기기 안에서 음성을 텍스트로 변환해요. 변환된 문장을 누르면 그 위치부터 다시 들을 수 있어요.

작성 오류를 미리 찾아요
한국코치협회 코칭일지 작성 유의사항을 기준으로 세션 길이 30분에서 120분, 같은 날 같은 고객 2회까지, 코치더코치 2배 계산, 그룹코칭 인원, 시간 겹침, 교육 시작일 이전 코칭을 확인해요. 넘친 시간은 한 번에 고칠 수 있어요.

제출용 파일 내보내기
한국코치협회 자격증은 공식 코칭일지 양식과 같은 서식의 엑셀 파일로, ICF 자격증은 ICF 코칭 로그 칸 순서의 CSV 파일로 저장해요. 날짜순 정렬과 합계도 자동으로 채워져요.

지난 코칭도 쉽게
직접 입력 화면에서 엑셀 칸 순서대로 입력하거나, Zoom이나 음성 메모로 녹음한 파일을 가져와 기록으로 만들 수 있어요.

고객 정보 보호
모든 기록과 녹음은 이 기기에만 저장되고, 앱은 어떤 정보도 수집하지 않아요. 앱 잠금을 켜면 Face ID나 기기 암호로 열 수 있고, 앱 전환 화면에서도 내용이 가려져요.

코칭 녹음은 고객의 동의를 받은 경우에만 사용해 주세요. 응시 요건은 바뀔 수 있으니 응시 전에 각 협회의 최신 안내를 확인해 주세요. 이 앱은 한국코치협회나 국제코칭연맹이 만든 앱이 아니에요.
```

**새로운 기능** (1.0은 표시되지 않지만 다음 버전용으로 보관)
```
첫 버전이에요.
준비 중인 자격증을 KAC KPC KSC ACC PCC MCC 중에서 고를 수 있어요.
자격증마다 목표 시간과 작성 점검 규칙이 달라져요.
ICF 자격증은 코칭 로그 CSV 파일로 내보낼 수 있어요.
글자를 더 크게 보여 줘요.
```

## English

**Name** (30)
```
Coaching Log: Coach Hours
```

**Subtitle** (30)
```
Record a session, log done
```

**Promotional Text** (170)
```
Pick the coaching credential you are working toward, from KAC KPC KSC to ICF ACC PCC MCC, and your sessions are checked against its hours and logging rules.
```

**Keywords** (100)
```
coach,coaching,log,hours,credential,mentor,recording,transcription,practice,client,session
```

**Description**
```
Record a coaching session and the date, time, and minutes are logged automatically while the conversation is transcribed. One tap exports a coaching log file ready to submit.

Built for your credential
Choose Korea Coach Association KAC, KPC, or KSC, or ICF ACC, PCC, or MCC. Goal hours, the coach-the-coach limit, minimum paid hours, and client counts follow your choice.

Recording and timer
The start and end times are set when you tap Start and End. Without consent to record, use the timer to log time only. Calls pause the session and recording continues on the lock screen.

On-device transcription
On iOS 26 and macOS 26 or later, speech is transcribed on device. Tap a sentence to play from that point.

Catch logging errors early
Session length, sessions per client per day, doubled coach-the-coach time, group size, overlapping sessions, and sessions before your training started are all checked, with one-tap fixes.

Export for submission
Korea Coach Association credentials export an Excel file matching the official coaching log form. ICF credentials export a CSV in ICF coaching log column order.

Your clients' privacy
Everything stays on your device and the app collects no data. Turn on App Lock to require Face ID or your passcode.

Record sessions only with your client's consent. Requirements can change, so check the latest guidance from each association. This app is not made by or affiliated with the Korea Coach Association or the International Coaching Federation.
```

**What's New**
```
First release.
Choose your credential from KAC KPC KSC ACC PCC MCC.
Goal hours and log checks follow the credential you choose.
ICF credentials export a coaching log CSV.
Larger text throughout the app.
```

## 심사 메모 (App Review Information)

로그인 없음. 데모 계정 필요 없음.

```
No account is required. To try the app: tap the record button, enter a client name, and start a session (or use the timer if you prefer not to record audio). End the session to create a log entry, then tap the share button to export the coaching log file. The credential can be changed in Settings. All data stays on the device. The microphone is used only to record coaching sessions, and speech recognition is used only to transcribe them.
```

## 스크린샷 체크리스트

| 기기 | 크기 | 장면 |
| --- | --- | --- |
| iPhone 6.9형 | 1320 x 2868 | 요약 카드, 녹음 중, 세션 상세(작성 점검), 내보내기, 설정(자격증 선택) |
| iPad 13형 | 2064 x 2752 | iPad를 지원하므로 필요 |
| Mac | 2880 x 1800 | Mac 앱도 제출할 경우 |

샘플 데이터로 찍고, 실제 고객 이름이 보이지 않게 해 주세요.
