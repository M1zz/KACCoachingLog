import SwiftData
import SwiftUI
import LeeoKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TranscriptionCenter.self) private var transcriptionCenter
    @Query(sort: \CoachingSession.startDate, order: .reverse) private var sessions: [CoachingSession]

    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.trainingStartKey) private var trainingStart = 0.0
    @AppStorage(AppSettings.certificationKey) private var certification: Certification = .kac
    @AppStorage(AppSettings.autoTranscribeKey) private var autoTranscribe = true
    @AppStorage(AppSettings.requireOnDeviceKey) private var requireOnDevice = true

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selectedID: UUID?
    /// iPad portrait shows the list next to the detail instead of hiding it.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showRecording = false
    @State private var showExport = false
    @State private var showManualEntry = false
    @State private var showSettings = false
    @State private var showAudioImporter = false
    @State private var alertMessage: String?
    @State private var pendingDelete: CoachingSession?
    @State private var didRecover = false

    private var entries: [LogEntry] { sessions.map(\.logEntry) }

    private var selectedSession: CoachingSession? {
        guard let selectedID else { return nil }
        return sessions.first { $0.uuid == selectedID }
    }

    private var knownClients: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for session in sessions where session.kind != .coachTheCoach {
            for name in session.logEntry.cleanedClientNames where !seen.contains(KACValidator.normalize(name)) {
                seen.insert(KACValidator.normalize(name))
                names.append(name)
            }
        }
        return names
    }

    var body: some View {
        let issues = KACValidator.validate(
            entries: entries,
            candidateName: candidateName,
            certification: certification,
            trainingStartDate: AppSettings.trainingStartDate(trainingStart)
        )
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(issues: issues)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showRecording) {
            RecordingView(knownClients: knownClients) { session in
                selectedID = session.uuid
            }
            .largeSheetOnPad()
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView(knownClients: knownClients) { session in
                selectedID = session.uuid
            }
            .largeSheetOnPad()
        }
        .sheet(isPresented: $showExport) {
            ExportView(sessions: sessions)
                .largeSheetOnPad()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showSettings = false }
                        }
                    }
            }
            .largeSheetOnPad()
        }
        #endif
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
            importAudio(result)
        }
        .confirmationDialog(
            "이 코칭 기록을 삭제할까요?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let session = pendingDelete { delete(session) }
                pendingDelete = nil
            }
        } message: {
            Text("녹음 파일과 변환된 텍스트도 함께 삭제돼요.")
        }
        .alert(
            "알림",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            guard !didRecover else { return }
            didRecover = true
            #if DEBUG
            if ScreenshotSupport.isSeeding {
                let newest = ScreenshotSupport.seed(modelContext)
                switch ScreenshotSupport.screen {
                case "detail": selectedID = newest?.uuid
                case "recording": showRecording = true
                case "export": showExport = true
                case "settings": showSettings = true
                case "manual": showManualEntry = true
                default: break
                }
                if selectedID == nil && isRegularWidth { selectedID = newest?.uuid }
                return
            }
            #endif
            transcriptionCenter.recoverInterrupted(sessions)
            // On a wide screen the detail column would otherwise start empty.
            if selectedID == nil && isRegularWidth { selectedID = sessions.first?.uuid }
        }
    }

    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    @ViewBuilder
    private var detailContent: some View {
        if let session = selectedSession {
            SessionDetailView(session: session, knownClients: knownClients) {
                pendingDelete = session
            }
            .id(session.uuid)
        } else {
            ContentUnavailableView(
                "코칭을 선택하세요",
                systemImage: "waveform",
                description: Text("코칭을 녹음하면 날짜·시간·분이 자동으로 기록되고, 대화는 텍스트로 변환돼요.")
            )
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private func sidebar(issues: [ValidationIssue]) -> some View {
        let summary = KACSummary(entries: entries, certification: certification)
        let issuesByEntry = Dictionary(grouping: issues.filter { $0.entryID != nil }, by: { $0.entryID! })
        let globalIssues = issues.filter { $0.entryID == nil }

        List(selection: $selectedID) {
            Section {
                SummaryCard(
                    summary: summary,
                    certification: certification,
                    errorCount: issues.filter { $0.severity == .error }.count,
                    warningCount: issues.filter { $0.severity == .warning }.count
                )
                ForEach(globalIssues) { issue in
                    IssueRow(issue: issue)
                }
                // 기록한 코칭 시간이 쌓였을 때만, 드물게 응원을 부탁한다. 코칭을 마치고 돌아온 목록이다 (모달 아님)
                LeeoTipAskSlot<KACCoachingLogSpec>(tipJar: KACCoachingLogSpec.tipJar,
                                                   reached: KACCoachingLogTipMoments.reached(totalMinutes: summary.totalMinutes))
            }

            if sessions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("첫 코칭을 기록해 보세요")
                            .font(.headline)
                        Text("‘코칭 시작’을 누르면 녹음과 함께 시작 시각이 기록되고, 종료하면 코칭일지 한 줄이 완성돼요. 지난 코칭은 ‘직접 입력’이나 ‘오디오 파일 가져오기’로 추가할 수 있어요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(monthGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sessions) { session in
                        NavigationLink(value: session.uuid) {
                            SessionRow(
                                session: session,
                                issues: issuesByEntry[session.uuid] ?? [],
                                progress: transcriptionCenter.progressValue(for: session)
                            )
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = session
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = session
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("코칭일지")
        .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 480)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showRecording = true
                } label: {
                    Label("코칭 시작", systemImage: "record.circle")
                }
                .help("녹음하며 코칭 시작")
                .keyboardShortcut("n", modifiers: .command)

                Menu {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("직접 입력", systemImage: "square.and.pencil")
                    }
                    Button {
                        showAudioImporter = true
                    } label: {
                        Label("오디오 파일 가져오기", systemImage: "waveform.badge.plus")
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }

                Button {
                    showExport = true
                } label: {
                    Label("엑셀로 내보내기", systemImage: "square.and.arrow.up")
                }
                .help("코칭일지 엑셀로 내보내기")
                .keyboardShortcut("e", modifiers: .command)

                #if os(iOS)
                Button {
                    showSettings = true
                } label: {
                    Label("설정", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                #else
                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
                #endif
            }
        }
    }

    private struct MonthGroup {
        var title: String
        var sessions: [CoachingSession]
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        var groups: [MonthGroup] = []
        for session in sessions {
            let month = calendar.dateInterval(of: .month, for: session.startDate)?.start ?? session.startDate
            let title = month.formatted(.dateTime.year().month(.wide))
            if groups.last?.title == title {
                groups[groups.count - 1].sessions.append(session)
            } else {
                groups.append(MonthGroup(title: title, sessions: [session]))
            }
        }
        return groups
    }

    // MARK: Actions

    private func importAudio(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            alertMessage = error.localizedDescription
        case .success(let url):
            do {
                let imported = try AudioImporter.importAudio(from: url)
                let minutes = max(1, Int((imported.duration / 60).rounded()))
                let calendar = Calendar.current
                let reference = imported.recordedAt ?? Date().addingTimeInterval(-imported.duration)
                let start = calendar.combine(day: reference, time: reference)
                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                let session = CoachingSession(startDate: start, endDate: end)
                session.audioFileName = imported.fileName
                modelContext.insert(session)
                try? modelContext.save()
                selectedID = session.uuid
                if autoTranscribe {
                    transcriptionCenter.start(session, requireOnDevice: requireOnDevice)
                }
                alertMessage = String(localized: "오디오를 가져왔어요. 파일의 생성 시각으로 시간을 채웠으니 실제 코칭 시간과 고객명을 확인해 주세요.")
            } catch {
                alertMessage = String(localized: "오디오 파일을 가져오지 못했어요: \(error.localizedDescription)")
            }
        }
    }

    private func delete(_ session: CoachingSession) {
        transcriptionCenter.discard(session)
        if selectedID == session.uuid { selectedID = nil }
        session.deleteAudioFile()
        modelContext.delete(session)
        try? modelContext.save()
    }
}

// MARK: - Rows

struct SessionRow: View {
    let session: CoachingSession
    let issues: [ValidationIssue]
    let progress: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let formatter = KACFormatter()

    var body: some View {
        let entry = session.logEntry
        // 아주 큰 글씨에서는 분 표시를 옆이 아니라 아래로
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(formatter.dateText(entry))  \(formatter.timeText(entry))")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    KindBadge(kind: session.kind)
                    Text(formatter.formatSummary(entry))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if session.audioFileName != nil {
                        Image(systemName: "waveform")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("녹음"))
                    }
                    transcriptionBadge
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(entry.recordedMinutes)분")
                    .font(.headline)
                    .monospacedDigit()
                if !issues.isEmpty {
                    let hasError = issues.contains { $0.severity == .error }
                    Image(systemName: hasError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasError ? Color.red : Color.orange)
                        .help(issues.map(\.message).joined(separator: "\n"))
                        .accessibilityLabel(Text(issues.map(\.message).joined(separator: ", ")))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var transcriptionBadge: some View {
        if let progress {
            ProgressView(value: progress)
                .frame(width: 44)
        } else {
            switch session.transcriptionState {
            case .completed:
                Image(systemName: "text.bubble")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("변환 완료"))
            case .failed:
                Image(systemName: "text.bubble.badge.exclamationmark")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("변환에 실패했어요."))
            case .idle, .inProgress:
                EmptyView()
            }
        }
    }
}

struct SummaryCard: View {
    let summary: KACSummary
    let certification: Certification
    let errorCount: Int
    let warningCount: Int

    private var goalMinutes: Int { certification.requiredTotalMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("누적 코칭시간")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(certification.title) 목표 \(certification.practiceHours)시간")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text(KACDuration.hoursMinutes(summary.totalMinutes))
                .font(.title2.weight(.bold))
                .monospacedDigit()
            ProgressView(value: goalMinutes > 0 ? min(1, Double(summary.totalMinutes) / Double(goalMinutes)) : 0)
            // Two columns so "27시간 45분" never runs into the next value at body size.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                stat("유료", KACDuration.hoursMinutes(summary.paidMinutes))
                stat("무료", KACDuration.hoursMinutes(summary.freeCoachingMinutes))
                if certification.countsCoachTheCoach {
                    stat("CTC", KACDuration.hoursMinutes(summary.ctcMinutes))
                }
                stat("고객", String(localized: "\(summary.uniqueClientCount)명"))
            }
            if errorCount > 0 || warningCount > 0 {
                Label(
                    "작성 점검: 오류 \(errorCount)건 · 주의 \(warningCount)건",
                    systemImage: errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                )
                .font(.body)
                .foregroundStyle(errorCount > 0 ? Color.red : Color.orange)
            } else if summary.entryCount > 0 {
                Label("작성 점검 통과", systemImage: "checkmark.seal.fill")
                    .font(.body)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
