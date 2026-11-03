import SwiftData
import SwiftUI

/// Adds a past session by hand, asking for every cell of one coaching-log row (columns A–G).
/// 여는 순간 '작성 중' 기록이 생기고, 고칠 때마다 저장된다. 닫았다가 목록에서 이어 쓴다.
struct ManualEntryView: View {
    @Bindable var session: CoachingSession
    let knownClients: [String]
    let onFinish: (CoachingSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CoachingSession> { !$0.isDraft }) private var finishedSessions: [CoachingSession]

    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.trainingStartKey) private var trainingStart = 0.0
    @AppStorage(AppSettings.certificationKey) private var certification: Certification = .kac

    @State private var askCandidateName = false
    @State private var saveCount = 0

    private var draft: LogEntry { session.logEntry }

    /// Cells of the row that are still empty. Saving is allowed only when this is empty.
    private var missingCells: [String] {
        let entry = draft
        var missing: [String] = []
        if entry.end <= entry.start {
            missing.append(String(localized: "B 시간: 종료 시각이 시작 시각보다 늦어야 해요"))
        }
        switch entry.kind {
        case .paid, .free:
            let needed = min(entry.participantCount, 3)
            if entry.cleanedClientNames.count < needed {
                missing.append(String(localized: "C 고객명: \(needed)명의 이름이 필요해요"))
            }
        case .coachTheCoach:
            if entry.cleanedClientNames.isEmpty {
                missing.append(String(localized: "C 고객명: 코치더코치 코치 이름이 필요해요"))
            }
            if entry.ctcLicenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(String(localized: "C 고객명: 코치의 인증자격번호가 필요해요"))
            }
        }
        return missing
    }

    private var draftIssues: [ValidationIssue] {
        KACValidator
            .validate(
                entries: finishedSessions.map(\.logEntry) + [draft],
                candidateName: candidateName,
                certification: certification,
                trainingStartDate: AppSettings.trainingStartDate(trainingStart)
            )
            .filter { $0.entryID == session.uuid }
    }

    var body: some View {
        NavigationStack {
            Form {
                if askCandidateName {
                    Section {
                        TextField("응시자 명", text: $candidateName)
                    } header: {
                        Text("응시자 명 (엑셀 상단)")
                    } footer: {
                        Text("모든 기록에 공통으로 들어가요. 설정에서도 바꿀 수 있어요.")
                    }
                }

                timeSection

                Section {
                    Picker("구분", selection: $session.kind) {
                        ForEach(certification.sessionKinds) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } header: {
                    Text("D·E·F 시간 칸")
                } footer: {
                    Text("유료는 D칸, 무료는 E칸, 받은 코치더코치는 F칸에 분이 기록돼요.")
                }

                ParticipantsEditor(
                    kind: $session.kind,
                    groupSize: $session.groupSize,
                    clientNames: $session.clientNames,
                    ctcComposition: $session.ctcComposition,
                    ctcLicenseNumber: $session.ctcLicenseNumber,
                    knownClients: knownClients
                )

                Section {
                    Picker("형태", selection: $session.format) {
                        ForEach(CoachingFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("G 코칭형태")
                } footer: {
                    Text("줌·보이스톡·전화로 진행했다면 비대면을 선택해 주세요.")
                }

                Section {
                    SheetRowPreview(entry: draft)
                } header: {
                    Text("코칭일지에 들어갈 내용")
                }

                checkSection
            }
            .formStyle(.grouped)
            .navigationTitle("직접 입력")
            .toolbar {
                // 닫아도 작성 중인 내용은 남는다.
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    SavedIndicator(saveCount: saveCount)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료", systemImage: "checkmark") { finish() }
                        .disabled(!missingCells.isEmpty)
                }
            }
            .onAppear {
                askCandidateName = candidateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .onChange(of: draft) {
                if (try? modelContext.save()) != nil { saveCount += 1 }
            }
            .onDisappear(perform: discardIfEmpty)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    // MARK: Sections

    private var timeSection: some View {
        let entry = draft
        return Section {
            DatePicker("날짜", selection: dayBinding, displayedComponents: .date)
            DatePicker("시작", selection: startBinding, displayedComponents: .hourAndMinute)
            DatePicker("종료", selection: endBinding, in: endRange, displayedComponents: .hourAndMinute)
            LabeledContent("기록될 시간", value: String(localized: "\(entry.recordedMinutes)분"))
            if certification.limitsSessionLength {
                LabeledContent("인정 범위", value: KACValidator.allowedLengthText(for: entry))
            }
        } header: {
            Text("A 날짜 · B 시간")
        } footer: {
            Text("실제로 진행한 시각을 분 단위까지 정확히 적어 주세요.")
        }
    }

    @ViewBuilder
    private var checkSection: some View {
        let missing = missingCells
        let issues = draftIssues
        Section {
            if missing.isEmpty && issues.isEmpty {
                Label("모든 칸이 채워졌고 문제가 없어요.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(missing, id: \.self) { text in
                Label(text, systemImage: "square.dashed")
                    .foregroundStyle(.red)
            }
            ForEach(issues) { issue in
                Label(issue.message,
                      systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            }
        } header: {
            Text("작성 점검")
        } footer: {
            if !missing.isEmpty {
                Text("빈 칸을 모두 채우면 완료할 수 있어요. 닫아도 작성 중인 내용은 남아 목록 맨 위에서 이어 쓸 수 있어요.")
            }
        }
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

    /// Moving the start keeps the session length.
    private var startBinding: Binding<Date> {
        Binding(
            get: { session.startDate },
            set: {
                let length = session.endDate.timeIntervalSince(session.startDate)
                session.startDate = Calendar.current.combine(day: session.startDate, time: $0)
                session.endDate = session.startDate.addingTimeInterval(max(length, 0))
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { session.endDate },
            set: { session.endDate = Calendar.current.combine(day: session.startDate, time: $0) }
        )
    }

    /// The end time can only be picked up to the maximum allowed length (120분, CTC 1:1·1:2는 60분).
    private var endRange: ClosedRange<Date> {
        let maxMinutes = KACValidator.maxRangeMinutes(for: draft, certification: certification)
        let start = session.startDate
        return start...max(start.addingTimeInterval(TimeInterval(maxMinutes * 60)), session.endDate)
    }

    // MARK: Actions

    /// 빈 칸을 다 채웠을 때만 — '작성 중'을 떼고 정식 기록으로 넣는다.
    private func finish() {
        session.clientNames = draft.cleanedClientNames
        session.ctcLicenseNumber = session.ctcLicenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        session.isDraft = false
        try? modelContext.save()
        onFinish(session)
        dismiss()
    }

    /// 열자마자 닫아 이름 하나 적지 않은 초안은 남기지 않는다.
    private func discardIfEmpty() {
        guard session.isDraft,
              draft.cleanedClientNames.isEmpty,
              session.ctcLicenseNumber.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

extension CoachingSession {
    /// 직접 입력을 열 때 만드는 '작성 중' 기록. 이번 정시에 시작해 기본 코칭 시간만큼.
    static func manualDraft() -> CoachingSession {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.minute = 0
        let start = calendar.date(from: components) ?? now
        let certification = UserDefaults.standard.string(forKey: AppSettings.certificationKey)
            .flatMap(Certification.init(rawValue:)) ?? .kac
        let minutes = AppSettings.defaultSessionMinutes(for: certification)
        let session = CoachingSession(startDate: start, endDate: start.addingTimeInterval(TimeInterval(minutes * 60)))
        session.isDraft = true
        return session
    }
}
