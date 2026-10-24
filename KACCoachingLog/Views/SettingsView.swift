import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.trainingStartKey) private var trainingStart = 0.0
    @AppStorage(AppSettings.appLockKey) private var appLockEnabled = false
    @AppStorage(AppSettings.certificationKey) private var certification: Certification = .kac
    @AppStorage(AppSettings.autoTranscribeKey) private var autoTranscribe = true
    @AppStorage(AppSettings.requireOnDeviceKey) private var requireOnDevice = true
    @AppStorage(AppSettings.recordAudioByDefaultKey) private var recordAudioByDefault = true

    @State private var engineDescription = "확인 중…"
    @State private var storageText = ""
    @State private var lockMessage: String?

    /// Turning the lock on or off both require authentication, so nobody else can switch it off.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { newValue in
                Task {
                    let reason = newValue
                        ? String(localized: "앱 잠금을 켜려면 인증해 주세요.")
                        : String(localized: "앱 잠금을 끄려면 인증해 주세요.")
                    switch await AppLock.authenticate(reason: reason) {
                    case .success:
                        appLockEnabled = newValue
                        lockMessage = nil
                    case .failure(let message):
                        lockMessage = message
                    }
                }
            }
        )
    }

    private var hasTrainingStart: Binding<Bool> {
        Binding(
            get: { trainingStart > 0 },
            set: { trainingStart = $0 ? Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 : 0 }
        )
    }

    private var trainingStartBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: trainingStart) },
            set: { trainingStart = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("자격증", selection: $certification) {
                    Section(CertificationBody.kca.title) {
                        ForEach(Certification.allCases.filter { $0.body == .kca }) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Section(CertificationBody.icf.title) {
                        ForEach(Certification.allCases.filter { $0.body == .icf }) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
                LabeledContent("발급 기관", value: certification.body.title)
                ForEach(certification.requirementLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                }
            } header: {
                Text("준비 중인 자격증")
            } footer: {
                Text(certification.body == .kca
                     ? "목표 시간, 코치더코치 한도, 작성 점검 규칙이 이 자격증에 맞춰져요. 교육·멘토코칭 시간은 코칭일지와 따로 확인해 주세요."
                     : "ICF 코칭 로그 기준으로 유료·프로보노 시간을 모아요. 받은 코치더코치는 시간에 포함되지 않아요. 교육·멘토코칭 시간은 따로 확인해 주세요.")
            }

            Section {
                TextField("응시자 명", text: $candidateName)
            } header: {
                Text("응시자")
            } footer: {
                Text(certification.body == .kca
                     ? "코칭일지 상단 ‘응시자 명(필수작성)’ 칸에 들어가요."
                     : "코칭 로그 맨 위 코치 이름 칸에 들어가요.")
            }

            Section {
                Toggle("개인정보 보호 (앱 잠금)", isOn: appLockBinding)
                if let lockMessage {
                    Text(lockMessage)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("개인정보 보호")
            } footer: {
                Text("켜면 앱을 열 때마다 Face ID 또는 기기 암호로 잠금을 해제해야 해요. 앱을 나가면 다시 잠기고, 앱 전환 화면에도 내용이 보이지 않아요.")
            }

            Section {
                Toggle("코칭 교육 시작일 입력", isOn: hasTrainingStart)
                if trainingStart > 0 {
                    DatePicker("코칭 교육 시작일", selection: trainingStartBinding, displayedComponents: .date)
                }
            } header: {
                Text("코칭 교육")
            } footer: {
                Text("코칭 실습은 \(certification.title) 교육(\(certification.educationHours)시간)을 시작한 날 이후 기록만 인정돼요. 그 이전 코칭은 오류로 표시돼요.")
            }

            Section {
                Toggle("새 코칭은 오디오 녹음으로 시작", isOn: $recordAudioByDefault)
                Toggle("녹음이 끝나면 자동으로 텍스트 변환", isOn: $autoTranscribe)
                Toggle("기기 내 인식만 사용", isOn: $requireOnDevice)
                LabeledContent("변환 엔진", value: engineDescription)
                LabeledContent("녹음 파일 용량", value: storageText)
            } header: {
                Text("녹음 · 텍스트 변환")
            } footer: {
                Text("iOS 26 · macOS 26 이상에서는 기기 안에서 처리하는 SpeechAnalyzer를 사용해요. 이전 버전에서 ‘기기 내 인식만 사용’을 끄면 음성이 Apple 서버로 전송될 수 있어요. 코칭 녹음은 고객 동의를 받은 경우에만 사용해 주세요.")
            }

            Section {
                if certification.body == .kca {
                    LabeledContent("코칭일지 양식", value: KACTemplateParts.templateVersion)
                    LabeledContent("점검 규칙", value: "작성 시 유의사항 1~9번")
                } else {
                    LabeledContent("코칭 로그 양식", value: "ICF Coaching Log (CSV)")
                }
            } header: {
                Text("양식")
            } footer: {
                Text("응시 요건은 바뀔 수 있어요. 응시 전에 \(certification.body.title)의 최신 안내를 확인해 주세요.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("설정")
        .task {
            storageText = AudioStorage.totalSizeText()
            engineDescription = await TranscriptionService.engineDescription()
        }
    }
}
