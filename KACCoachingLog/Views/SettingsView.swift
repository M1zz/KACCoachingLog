import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.trainingStartKey) private var trainingStart = 0.0
    @AppStorage(AppSettings.goalHoursKey) private var goalHours = AppSettings.defaultGoalHours
    @AppStorage(AppSettings.autoTranscribeKey) private var autoTranscribe = true
    @AppStorage(AppSettings.requireOnDeviceKey) private var requireOnDevice = true
    @AppStorage(AppSettings.recordAudioByDefaultKey) private var recordAudioByDefault = true

    @State private var engineDescription = "확인 중…"
    @State private var storageText = ""

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
                TextField("응시자 명", text: $candidateName)
            } header: {
                Text("응시자")
            } footer: {
                Text("코칭일지 상단 ‘응시자 명(필수작성)’ 칸에 들어가요.")
            }

            Section {
                Toggle("기초교육 시작일 입력", isOn: hasTrainingStart)
                if trainingStart > 0 {
                    DatePicker("기초교육 시작일", selection: trainingStartBinding, displayedComponents: .date)
                }
            } header: {
                Text("코칭 교육")
            } footer: {
                Text("코칭 실습은 기초교육(20시간)을 시작한 날 이후 기록만 인정돼요. 그 이전 코칭은 오류로 표시돼요.")
            }

            Section {
                Stepper(value: $goalHours, in: 5...500, step: 5) {
                    LabeledContent("목표 코칭시간", value: "\(goalHours)시간")
                }
            } header: {
                Text("목표")
            } footer: {
                Text("응시 요건(필요한 코칭시간과 유료·무료 구성)은 한국코치협회의 최신 ‘코치인증자격시험 세부사항’을 확인해 주세요.")
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

            Section("양식") {
                LabeledContent("코칭일지 양식", value: KACTemplateParts.templateVersion)
                LabeledContent("점검 규칙", value: "작성 시 유의사항 1~9번")
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
