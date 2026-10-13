import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    let sessions: [CoachingSession]

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.candidateNameKey) private var candidateName = ""
    @AppStorage(AppSettings.trainingStartKey) private var trainingStart = 0.0

    @State private var useRange = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @State private var rangeEnd = Date()
    @State private var includeExampleRows = false
    @State private var document: XLSXDocument?
    @State private var shareURL: URL?
    @State private var showExporter = false
    @State private var resultMessage: String?

    private var filteredEntries: [LogEntry] {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: rangeStart)
        let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEnd)) ?? rangeEnd
        return sessions
            .filter { !useRange || ($0.startDate >= lower && $0.startDate < upper) }
            .map(\.logEntry)
    }

    private var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let name = candidateName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
        let suffix = name.isEmpty ? "" : "_\(name)"
        return "코칭일지\(suffix)_\(formatter.string(from: Date()))"
    }

    var body: some View {
        let entries = filteredEntries
        let summary = KACSummary(entries: entries)
        let issues = KACValidator.validate(
            entries: entries,
            candidateName: candidateName,
            trainingStartDate: AppSettings.trainingStartDate(trainingStart),
            checkTotalHours: true
        )
        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.count - errorCount

        NavigationStack {
            Form {
                Section {
                    TextField("응시자 명 (필수)", text: $candidateName)
                } header: {
                    Text("응시자")
                }

                Section("범위") {
                    Toggle("기간 지정", isOn: $useRange)
                    if useRange {
                        DatePicker("시작일", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("종료일", selection: $rangeEnd, displayedComponents: .date)
                    }
                    LabeledContent("포함되는 코칭", value: "\(entries.count)건")
                }

                Section("합계 미리보기") {
                    LabeledContent("총 유료 코칭 시간", value: KACDuration.hoursMinutes(summary.paidMinutes))
                    LabeledContent("총 무료 코칭 시간", value: KACDuration.hoursMinutes(summary.totalFreeMinutes))
                    LabeledContent("└ 받은 코치더코치 포함", value: KACDuration.hoursMinutes(summary.ctcMinutes))
                    LabeledContent("총 코칭시간 합계", value: KACDuration.hoursMinutes(summary.totalMinutes))
                    LabeledContent("고객 수", value: "\(summary.uniqueClientCount)명")
                }

                Section {
                    if issues.isEmpty {
                        Label("점검한 항목에서 문제가 발견되지 않았어요.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(issues) { issue in
                            IssueRow(issue: issue)
                        }
                    }
                } header: {
                    Text("작성 점검 · 오류 \(errorCount)건 · 주의 \(warningCount)건")
                } footer: {
                    Text("협회 기준: 건별 작성 오류가 5개를 초과하면 탈락 사유이고, 오류 건의 시간은 합계에서 제외돼요. 코칭교육 중 실시한 실습(유의사항 5번)은 앱이 구분할 수 없으니 직접 빼 주세요.")
                }

                Section {
                    Toggle("원본 양식의 예시 행(7–10행) 포함", isOn: $includeExampleRows)
                } footer: {
                    Text("양식 \(KACTemplateParts.templateVersion) 기준으로 날짜순 정렬해 작성돼요. 합계 칸은 시간과 분으로 채워져요.")
                }

                Section {
                    if errorCount > 0 {
                        Label("오류가 \(errorCount)건 있어요. 목록에서 빨간 표시가 있는 기록을 열어 고친 뒤 내보내 주세요.",
                              systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    Button {
                        prepareFile(entries: entries)
                        if document != nil { showExporter = true }
                    } label: {
                        Label("엑셀 파일로 저장", systemImage: "tablecells")
                    }
                    .disabled(entries.isEmpty)

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("공유 (메일 · 메시지 · AirDrop)", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            prepareFile(entries: entries)
                        } label: {
                            Label("공유용 파일 만들기", systemImage: "square.and.arrow.up")
                        }
                        .disabled(entries.isEmpty)
                    }

                    if let resultMessage {
                        Text(resultMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("코칭일지 내보내기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onChange(of: useRange) { _, _ in shareURL = nil }
            .onChange(of: rangeStart) { _, _ in shareURL = nil }
            .onChange(of: rangeEnd) { _, _ in shareURL = nil }
            .onChange(of: includeExampleRows) { _, _ in shareURL = nil }
            .onChange(of: candidateName) { _, _ in shareURL = nil }
            .fileExporter(
                isPresented: $showExporter,
                document: document,
                contentType: .xlsxSpreadsheet,
                defaultFilename: fileName
            ) { result in
                switch result {
                case .success(let url):
                    resultMessage = "저장했어요: \(url.lastPathComponent)"
                case .failure(let error):
                    resultMessage = "저장하지 못했어요: \(error.localizedDescription)"
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private func prepareFile(entries: [LogEntry]) {
        let builder = KACWorkbookBuilder(
            candidateName: candidateName,
            entries: entries,
            includeExampleRows: includeExampleRows
        )
        let data = builder.build()
        document = XLSXDocument(data: data)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(fileName).xlsx")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            shareURL = nil
            resultMessage = "공유용 파일을 만들지 못했어요: \(error.localizedDescription)"
        }
    }
}
