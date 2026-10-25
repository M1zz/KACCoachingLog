import SwiftData
import SwiftUI

/// Values chosen before a session starts. Everything can be edited afterwards.
struct SessionDraft {
    var kind: SessionKind = .paid
    var format: CoachingFormat = .faceToFace
    var groupSize: Int = 1
    var clientNames: [String] = [""]
    var ctcComposition: CTCComposition = .oneOnOne
    var ctcLicenseNumber: String = ""
    var topic: String = ""

    /// Entry used to check the session length while coaching.
    func entry(start: Date, end: Date) -> LogEntry {
        LogEntry(start: start, end: end, clientNames: clientNames, groupSize: groupSize,
                 kind: kind, format: format, ctcComposition: ctcComposition)
    }

    var title: String {
        let names = clientNames
            .prefix(kind == .coachTheCoach ? 1 : 3)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if names.isEmpty { return kind.title }
        if kind == .coachTheCoach { return String(localized: "\(names[0]) 코치 · 코치더코치") }
        let extra = max(groupSize - 1, 0)
        return extra > 0 ? String(localized: "\(names[0]) 외 \(extra)명 · \(kind.title)") : "\(names[0]) · \(kind.title)"
    }
}

struct RecordingView: View {
    let knownClients: [String]
    let onSaved: (CoachingSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TranscriptionCenter.self) private var transcriptionCenter

    @AppStorage(AppSettings.autoTranscribeKey) private var autoTranscribe = true
    @AppStorage(AppSettings.requireOnDeviceKey) private var requireOnDevice = true
    @AppStorage(AppSettings.recordAudioByDefaultKey) private var recordAudioByDefault = true
    @AppStorage(AppSettings.certificationKey) private var certification: Certification = .kac

    @State private var recorder = AudioRecorder()
    @State private var draft = SessionDraft()
    @State private var recordAudio = true
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var confirmClose = false
    @State private var confirmShortStop = false
    @State private var overLimitResult: RecordingResult?

    var body: some View {
        NavigationStack {
            Group {
                if recorder.state == .idle {
                    setupForm
                } else {
                    recordingPanel
                }
            }
            .navigationTitle(recorder.state == .idle ? "새 코칭" : "코칭 중")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recorder.state == .idle ? "취소" : "닫기") {
                        if recorder.state == .idle {
                            dismiss()
                        } else {
                            confirmClose = true
                        }
                    }
                }
            }
            .confirmationDialog("진행 중인 코칭을 어떻게 할까요?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("저장하고 닫기") { stopAndSave() }
                Button("기록 삭제", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
                Button("계속 코칭", role: .cancel) {}
            }
            .confirmationDialog("아직 \(KACValidator.minSessionMinutes)분이 안 됐어요", isPresented: $confirmShortStop, titleVisibility: .visible) {
                Button("그래도 종료하고 저장") { stopAndSave(force: true) }
                Button("계속 코칭", role: .cancel) {}
            } message: {
                Text("\(KACValidator.minSessionMinutes)분 미만 코칭은 코칭일지에 인정되지 않아요.")
            }
            .confirmationDialog(
                "최대 인정 시간을 넘었어요",
                isPresented: Binding(get: { overLimitResult != nil }, set: { if !$0 { overLimitResult = nil } }),
                titleVisibility: .visible
            ) {
                if let result = overLimitResult {
                    let maxMinutes = KACValidator.allowedRangeMinutes(for: draft.entry(start: result.startDate, end: result.endDate)).upperBound
                    Button("\(maxMinutes)분으로 맞춰 저장") {
                        var capped = result
                        if let fix = KACValidator.lengthFix(for: draft.entry(start: result.startDate, end: result.endDate)) {
                            capped.endDate = fix.end
                        }
                        save(capped)
                    }
                    Button("실제 시간 그대로 저장") { save(result) }
                }
            } message: {
                if let result = overLimitResult {
                    let entry = draft.entry(start: result.startDate, end: result.endDate)
                    Text("이 코칭은 \(KACValidator.allowedLengthText(for: entry))만 인정돼요. 그대로 저장하면 작성 오류로 표시돼요. 녹음 파일은 그대로 남아요.")
                }
            }
            .alert(
                "시작할 수 없어요",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(recorder.state != .idle)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
        .onAppear {
            recordAudio = recordAudioByDefault
            if !certification.sessionKinds.contains(draft.kind) { draft.kind = .paid }
            #if DEBUG
            if ScreenshotSupport.screen == "recording" {
                draft.clientNames = [ScreenshotSupport.recordingClient]
                draft.format = .remote
                recorder.startPreview(elapsed: 47 * 60 + 12)
            }
            #endif
        }
    }

    // MARK: Setup

    private var setupForm: some View {
        Form {
            Section("코칭 구분") {
                Picker("구분", selection: $draft.kind) {
                    ForEach(certification.sessionKinds) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.kind) { _, newKind in
                    if newKind == .coachTheCoach && draft.ctcComposition == .group {
                        draft.groupSize = max(3, min(draft.groupSize, 5))
                    }
                }

                Picker("형태", selection: $draft.format) {
                    ForEach(CoachingFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            ParticipantsEditor(
                kind: $draft.kind,
                groupSize: $draft.groupSize,
                clientNames: $draft.clientNames,
                ctcComposition: $draft.ctcComposition,
                ctcLicenseNumber: $draft.ctcLicenseNumber,
                knownClients: knownClients
            )

            Section("주제 (선택)") {
                TextField("오늘 코칭의 주제", text: $draft.topic)
            }

            Section {
                Toggle("오디오 녹음", isOn: $recordAudio)
            } footer: {
                Text(recordAudio
                     ? "녹음 전에 고객에게 녹음과 텍스트 변환에 대한 동의를 받아 주세요. 녹음과 변환은 이 기기 안에 저장돼요."
                     : "녹음 없이 시작·종료 시각만 기록해요.")
            }

            Section {
                Button {
                    Task { await start() }
                } label: {
                    Label(recordAudio ? "녹음하며 코칭 시작" : "타이머로 코칭 시작",
                          systemImage: recordAudio ? "record.circle.fill" : "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(recordAudio ? Color.red : Color.accentColor)
                .disabled(isStarting)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("시작 시각은 버튼을 누른 순간, 종료 시각은 ‘종료’를 누른 순간으로 기록돼요. 코칭교육 시간 중 실습은 코칭일지에 넣지 않아요.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Recording

    private var recordingPanel: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(draft.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let startDate = recorder.startDate {
                    Text("시작 \(startDate.formatted(date: .omitted, time: .shortened)) · \(draft.format.title)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                VStack(spacing: 18) {
                    Text(KACDuration.clock(recorder.elapsed(at: context.date)))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                    if recorder.isRecordingAudio {
                        LevelMeter(level: recorder.currentLevel())
                            .frame(height: 8)
                            .frame(maxWidth: 260)
                    }
                    Text(KACDuration.hoursMinutes(Int(recorder.elapsed(at: context.date) / 60)))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            statusLabel

            TimelineView(.periodic(from: .now, by: 1)) { context in
                lengthGuide(at: context.date)
            }

            HStack(spacing: 40) {
                Button {
                    if recorder.state == .recording {
                        recorder.pause()
                    } else {
                        recorder.resume()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: recorder.state == .recording ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 72, height: 72)
                            .background(.quaternary, in: Circle())
                        Text(recorder.state == .recording ? "일시정지" : "계속")
                            .font(.body)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    stopAndSave(force: false)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.red, in: Circle())
                        Text("종료 및 저장")
                            .font(.body)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch recorder.state {
        case .paused:
            Label(recorder.wasInterrupted ? "전화 등으로 일시정지됐어요" : "일시정지됨", systemImage: "pause.circle")
                .foregroundStyle(.orange)
        case .recording:
            Label(recorder.isRecordingAudio ? "녹음 중" : "타이머 작동 중",
                  systemImage: recorder.isRecordingAudio ? "record.circle" : "timer")
                .foregroundStyle(recorder.isRecordingAudio ? Color.red : Color.secondary)
        case .idle:
            EmptyView()
        }
    }

    /// Tells the coach how much recognised time is left (120분, CTC 1:1·1:2는 실제 60분).
    @ViewBuilder
    private func lengthGuide(at date: Date) -> some View {
        if let start = recorder.startDate, certification.limitsSessionLength {
            let entry = draft.entry(start: start, end: date)
            let range = KACValidator.allowedRangeMinutes(for: entry)
            let minutes = entry.rangeMinutes
            if minutes > range.upperBound {
                Label("최대 \(range.upperBound)분을 넘었어요. 넘는 시간은 인정되지 않아요.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            } else if minutes >= range.upperBound - 10 {
                Label("최대 인정 시간까지 \(range.upperBound - minutes)분 남았어요.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if minutes < range.lowerBound {
                Text("인정 범위 \(KACValidator.allowedLengthText(for: entry)) · \(range.lowerBound - minutes)분 더 하면 인정돼요")
                    .foregroundStyle(.secondary)
            } else {
                Label("인정 범위 \(KACValidator.allowedLengthText(for: entry))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: Actions

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await recorder.start(recordAudio: recordAudio)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndSave(force: Bool = true) {
        if !force, certification.limitsSessionLength, let start = recorder.startDate {
            let entry = draft.entry(start: start, end: Date())
            if entry.rangeMinutes < KACValidator.allowedRangeMinutes(for: entry).lowerBound {
                confirmShortStop = true
                return
            }
        }
        guard let result = recorder.stop() else {
            dismiss()
            return
        }
        let entry = draft.entry(start: result.startDate, end: result.endDate)
        if certification.limitsSessionLength && entry.rangeMinutes > KACValidator.allowedRangeMinutes(for: entry).upperBound {
            overLimitResult = result
            return
        }
        save(result)
    }

    private func save(_ result: RecordingResult) {
        let session = CoachingSession(
            startDate: result.startDate,
            endDate: result.endDate,
            clientNames: draft.clientNames,
            groupSize: draft.kind == .coachTheCoach && draft.ctcComposition != .group ? 1 : draft.groupSize,
            kind: draft.kind,
            format: draft.format
        )
        session.ctcComposition = draft.ctcComposition
        session.ctcLicenseNumber = draft.ctcLicenseNumber.trimmingCharacters(in: .whitespaces).uppercased()
        session.topic = draft.topic
        if let url = result.fileURL {
            session.audioFileName = url.lastPathComponent
        }
        modelContext.insert(session)
        try? modelContext.save()

        if autoTranscribe && session.audioFileName != nil {
            transcriptionCenter.start(session, requireOnDevice: requireOnDevice)
        }
        onSaved(session)
        dismiss()
    }
}

struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level > 0.85 ? Color.orange : Color.red)
                    .frame(width: max(4, proxy.size.width * level))
                    .animation(.linear(duration: 0.2), value: level)
            }
        }
    }
}
