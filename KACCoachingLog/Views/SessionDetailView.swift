import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SessionDetailView: View {
    @Bindable var session: CoachingSession
    let knownClients: [String]
    let onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(TranscriptionCenter.self) private var transcriptionCenter
    @Query private var allSessions: [CoachingSession]

    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.requireOnDeviceKey) private var requireOnDevice = true

    @State private var player = AudioPlayer()
    @State private var showAudioImporter = false
    @State private var confirmRetranscribe = false
    @State private var confirmDeleteAudio = false
    @State private var importError: String?

    private let formatter = KACFormatter()

    var body: some View {
        Form {
            previewSection
            issuesSection
            timeSection
            kindSection
            ParticipantsEditor(
                kind: $session.kind,
                groupSize: $session.groupSize,
                clientNames: $session.clientNames,
                ctcComposition: $session.ctcComposition,
                ctcLicenseNumber: $session.ctcLicenseNumber,
                knownClients: knownClients
            )
            notesSection
            audioSection
            transcriptSection

            Section {
                Button(role: .destructive) {
                    player.stop()
                    onDelete()
                } label: {
                    Label("이 코칭 기록 삭제", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(session.displayTitle)
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
            attachAudio(result)
        }
        .confirmationDialog("텍스트를 다시 변환할까요?", isPresented: $confirmRetranscribe, titleVisibility: .visible) {
            Button("다시 변환") { startTranscription() }
        } message: {
            Text("직접 수정한 내용은 새 변환 결과로 바뀌어요.")
        }
        .confirmationDialog("녹음 파일을 삭제할까요?", isPresented: $confirmDeleteAudio, titleVisibility: .visible) {
            Button("녹음 파일 삭제", role: .destructive) {
                player.stop()
                session.deleteAudioFile()
                try? modelContext.save()
            }
        } message: {
            Text("변환된 텍스트와 코칭일지 항목은 그대로 남아요.")
        }
        .alert(
            "알림",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onDisappear {
            player.stop()
            try? modelContext.save()
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            SheetRowPreview(entry: session.logEntry)
        } header: {
            Text("코칭일지에 들어갈 내용")
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        let issues = KACValidator
            .validate(entries: allSessions.map(\.logEntry), candidateName: candidateName)
            .filter { $0.entryID == session.uuid }
        if !issues.isEmpty {
            Section("작성 점검") {
                ForEach(issues) { issue in
                    IssueRow(issue: issue)
                }
            }
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker("날짜", selection: dayBinding, displayedComponents: .date)
            DatePicker("시작", selection: startBinding, displayedComponents: .hourAndMinute)
            DatePicker("종료", selection: endBinding, displayedComponents: .hourAndMinute)
            LabeledContent("시간 범위", value: "\(session.logEntry.rangeMinutes)분")
            Toggle("분 직접 입력", isOn: overrideEnabledBinding)
            if session.minutesOverride != nil {
                Stepper(value: overrideValueBinding, in: 0...600, step: 5) {
                    LabeledContent("기록할 시간", value: "\(session.minutesOverride ?? 0)분")
                }
            }
        } header: {
            Text("일시")
        } footer: {
            if session.kind == .coachTheCoach {
                Text("1:1·1:2 코치더코치는 실제 시간의 2배(\(session.logEntry.recordedMinutes)분)로 기록돼요.")
            } else {
                Text("유료·무료 칸에는 시간 범위와 같은 분이 기록돼요. 시간 범위와 다른 값을 적으면 작성 오류로 볼 수 있어요.")
            }
        }
    }

    private var kindSection: some View {
        Section("구분") {
            Picker("구분", selection: $session.kind) {
                ForEach(SessionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Picker("형태", selection: $session.format) {
                ForEach(CoachingFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var notesSection: some View {
        Section("주제 · 메모") {
            TextField("주제", text: $session.topic)
            TextField("코칭 후 메모 (고객의 목표, 합의한 실천, 다음 세션 등)", text: $session.notes, axis: .vertical)
                .lineLimit(3...12)
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        Section("녹음") {
            if let url = session.audioFileURL {
                PlayerControls(player: player, url: url)
                ShareLink(item: url) {
                    Label("녹음 파일 공유", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    confirmDeleteAudio = true
                } label: {
                    Label("녹음 파일 삭제", systemImage: "trash")
                }
            } else {
                Text("녹음 파일이 없어요. Zoom·음성 메모 등으로 녹음한 파일을 붙일 수 있어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    showAudioImporter = true
                } label: {
                    Label("오디오 파일 첨부", systemImage: "waveform.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        Section {
            transcriptStatus
            if !session.transcript.isEmpty || session.transcriptionState == .completed {
                TextField("변환된 텍스트", text: $session.transcript, axis: .vertical)
                    .lineLimit(8...40)
                    .font(.body)
                if !session.transcript.isEmpty {
                    ShareLink(item: session.transcript, subject: Text("코칭 기록 텍스트")) {
                        Label("텍스트 공유", systemImage: "doc.on.doc")
                    }
                }
            }
            let segments = session.transcriptSegments
            if !segments.isEmpty, let url = session.audioFileURL {
                DisclosureGroup("구간별로 듣기 (\(segments.count))") {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Button {
                            player.load(url)
                            player.seek(to: segment.start)
                            if !player.isPlaying { player.togglePlay() }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(KACDuration.clock(segment.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(segment.text)
                                    .font(.callout)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("텍스트 변환 (STT)")
        } footer: {
            Text("화자는 구분되지 않아요. 고객 정보가 담긴 기록이니 공유할 때 주의해 주세요.")
        }
    }

    @ViewBuilder
    private var transcriptStatus: some View {
        if let progress = transcriptionCenter.progressValue(for: session) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("텍스트로 변환 중… \(Int(progress * 100))%")
                        .monospacedDigit()
                    Spacer()
                    Button("중지") { transcriptionCenter.cancel(session) }
                }
                ProgressView(value: progress)
                Text("처음 사용할 때는 한국어 음성 모델을 내려받느라 시간이 걸릴 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            switch session.transcriptionState {
            case .failed:
                Label(session.transcriptionError.isEmpty ? "변환에 실패했어요." : session.transcriptionError,
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                transcribeButton(title: "다시 시도")
            case .completed:
                HStack {
                    Text(session.transcriptionEngine.isEmpty ? "변환 완료" : "변환 완료 · \(session.transcriptionEngine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if session.audioFileURL != nil {
                        Button("다시 변환") { confirmRetranscribe = true }
                            .font(.caption)
                    }
                }
                if !session.transcriptionError.isEmpty {
                    Text(session.transcriptionError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .idle, .inProgress:
                if session.audioFileURL != nil {
                    transcribeButton(title: "텍스트로 변환")
                } else {
                    Text("녹음 파일이 있으면 텍스트로 변환할 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transcribeButton(title: String) -> some View {
        Button {
            startTranscription()
        } label: {
            Label(title, systemImage: "text.bubble")
        }
        .disabled(session.audioFileURL == nil)
    }

    // MARK: Bindings

    private var dayBinding: Binding<Date> {
        Binding(
            get: { session.startDate },
            set: { newDay in
                let calendar = Calendar.current
                session.startDate = calendar.combine(day: newDay, time: session.startDate)
                session.endDate = calendar.combine(day: newDay, time: session.endDate)
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { session.startDate },
            set: { session.startDate = Calendar.current.combine(day: session.startDate, time: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { session.endDate },
            set: { session.endDate = Calendar.current.combine(day: session.startDate, time: $0) }
        )
    }

    private var overrideEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.minutesOverride != nil },
            set: { enabled in
                session.minutesOverride = enabled ? session.logEntry.recordedMinutes : nil
            }
        )
    }

    private var overrideValueBinding: Binding<Int> {
        Binding(
            get: { session.minutesOverride ?? session.logEntry.recordedMinutes },
            set: { session.minutesOverride = $0 }
        )
    }

    // MARK: Actions

    private func startTranscription() {
        try? modelContext.save()
        transcriptionCenter.start(session, requireOnDevice: requireOnDevice)
    }

    private func attachAudio(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            do {
                let imported = try AudioImporter.importAudio(from: url)
                session.audioFileName = imported.fileName
                try? modelContext.save()
                startTranscription()
            } catch {
                importError = "오디오 파일을 가져오지 못했어요: \(error.localizedDescription)"
            }
        }
    }
}

struct PlayerControls: View {
    let player: AudioPlayer
    let url: URL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let current = player.loadedURL == url ? player.currentTime() : 0
            let duration = max(player.duration, 1)
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        player.load(url)
                        player.skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        player.load(url)
                        player.togglePlay()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        player.load(url)
                        player.skip(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text("\(KACDuration.clock(current)) / \(KACDuration.clock(player.duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { min(current, duration) },
                        set: { newValue in
                            player.load(url)
                            player.seek(to: newValue)
                        }
                    ),
                    in: 0...duration
                )
            }
        }
        .onAppear { player.load(url) }
    }
}
