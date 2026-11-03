import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Participants editor (clients or coach-the-coach coach)

/// 전에 기록한 고객과 그분의 마지막 코칭 날.
struct KnownClient: Hashable {
    var name: String
    var lastDate: Date

    /// 최근에 만난 분부터. 이름은 띄어쓰기·대소문자를 무시하고 한 분으로 센다. 코치더코치는 고객이 아니라 뺀다.
    static func list(from sessions: [CoachingSession]) -> [KnownClient] {
        var latest: [String: KnownClient] = [:]
        for session in sessions where session.kind != .coachTheCoach {
            for name in session.logEntry.cleanedClientNames {
                let key = KACValidator.normalize(name)
                if let known = latest[key], known.lastDate >= session.startDate { continue }
                latest[key] = KnownClient(name: name, lastDate: session.startDate)
            }
        }
        return latest.values.sorted { $0.lastDate > $1.lastDate }
    }

    /// "10월 28일 · 6일 전". 올해가 아니면 연도도 붙인다.
    var lastDateText: String {
        let calendar = Calendar.current
        let now = Date()
        let sameYear = calendar.isDate(lastDate, equalTo: now, toGranularity: .year)
        let day = lastDate.formatted(sameYear ? .dateTime.month().day() : .dateTime.year().month().day())
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate), to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return "\(day) · \(formatter.localizedString(from: DateComponents(day: -days)))"
    }
}

struct ParticipantsEditor: View {
    @Binding var kind: SessionKind
    @Binding var groupSize: Int
    @Binding var clientNames: [String]
    @Binding var ctcComposition: CTCComposition
    @Binding var ctcLicenseNumber: String
    var knownClients: [KnownClient]

    @AppStorage(AppSettings.certificationKey) private var certification: Certification = .kac
    /// 동명이인으로 구분할 이름 칸과, 붙일 구분 말.
    @State private var distinguishingIndex: Int?
    @State private var distinguisher = ""

    var body: some View {
        if kind == .coachTheCoach {
            coachTheCoachSection
        } else {
            clientSection
        }
    }

    private var clientSection: some View {
        Section {
            Stepper(value: $groupSize, in: 1...certification.maxGroupSize) {
                LabeledContent("인원", value: groupSize == 1 ? String(localized: "1:1 코칭") : String(localized: "1:\(groupSize) 그룹코칭"))
            }
            ForEach(0..<min(groupSize, 3), id: \.self) { index in
                TextField(placeholder(for: index), text: nameBinding(index))
                if let known = knownClient(at: index) {
                    sameNameNote(known, index: index)
                }
            }
            let suggestions = suggestedClients
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { fillNextEmpty(with: name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("고객")
        } footer: {
            if groupSize > 3 && certification.body == .kca {
                Text("그룹코칭은 코칭일지에 3명까지만 기재하고, 코칭형태에 총 인원이 표시돼요.")
            }
        }
    }

    private var coachTheCoachSection: some View {
        Section {
            TextField("코치더코치 코치 이름", text: nameBinding(0))
            TextField("인증자격번호 (예: KPC00000)", text: $ctcLicenseNumber)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            Picker("구성", selection: $ctcComposition) {
                ForEach(CTCComposition.allCases) { composition in
                    Text(composition.title).tag(composition)
                }
            }
            if ctcComposition == .group {
                Stepper(value: $groupSize, in: 3...5) {
                    LabeledContent("응시자 수", value: String(localized: "\(groupSize)명"))
                }
            }
        } header: {
            Text("받은 코치더코치")
        } footer: {
            Text("한국코치협회 인증 코치에게 받은 코치더코치만 인정돼요. 1:1·1:2는 2배로 계산되어 60~120분만 작성할 수 있고, \(certification.title)는 최대 \(certification.maxCTCHours ?? 0)시간까지 인정돼요.")
        }
    }

    private var suggestedClients: [String] {
        let current = Set(clientNames.map { KACValidator.normalize($0) })
        return knownClients.map(\.name).filter { !current.contains(KACValidator.normalize($0)) }.prefix(12).map { $0 }
    }

    /// 고객은 이름으로 센다. 전에 기록한 이름이면 같은 분으로 보고, 동명이인일 때만 구분 말을 붙인다.
    private func knownClient(at index: Int) -> KnownClient? {
        guard index < clientNames.count else { return nil }
        let key = KACValidator.normalize(clientNames[index].trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return nil }
        return knownClients.first { KACValidator.normalize($0.name) == key }
    }

    /// 전에 만난 분이면 마지막 코칭 날을 보여 준다. 같은 분으로 세어지니, 아니면 구분하게 한다.
    private func sameNameNote(_ known: KnownClient, index: Int) -> some View {
        let name = known.name
        return HStack {
            Label("마지막 코칭 \(known.lastDateText)", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Spacer()
            Button("다른 분이에요") {
                distinguisher = ""
                distinguishingIndex = index
            }
            .buttonStyle(.borderless)
        }
        .alert(
            "\(name) 님과 구분해 주세요",
            isPresented: Binding(
                get: { distinguishingIndex == index },
                set: { if !$0 { distinguishingIndex = nil } }
            )
        ) {
            TextField("예: 회사, 지역", text: $distinguisher)
            Button("취소", role: .cancel) {}
            Button("구분하기") {
                let mark = distinguisher.trimmingCharacters(in: .whitespaces)
                if !mark.isEmpty { nameBinding(index).wrappedValue = "\(name)(\(mark))" }
            }
        } message: {
            Text("코칭일지에 ‘\(name)(회사)’처럼 적혀 다른 고객으로 세어져요.")
        }
    }

    private func placeholder(for index: Int) -> String {
        groupSize == 1 ? String(localized: "고객 이름") : String(localized: "고객 \(index + 1) 이름")
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < clientNames.count ? clientNames[index] : "" },
            set: { newValue in
                var names = clientNames
                while names.count <= index { names.append("") }
                names[index] = newValue
                clientNames = names
            }
        )
    }

    private func fillNextEmpty(with name: String) {
        var names = clientNames
        let limit = min(groupSize, 3)
        while names.count < limit { names.append("") }
        if let emptyIndex = names.prefix(limit).firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            names[emptyIndex] = name
        } else if groupSize < certification.maxGroupSize {
            groupSize += 1
            if names.count < 3 { names.append(name) }
        }
        clientNames = names
    }
}

// MARK: - Small views

/// 고치면 바로 저장된다는 표시. 저장할 때마다 체크가 한 번 튄다.
struct SavedIndicator: View {
    let saveCount: Int

    var body: some View {
        Label("저장됨", systemImage: "checkmark.circle.fill")
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: saveCount)
    }
}

struct KindBadge: View {
    let kind: SessionKind

    var body: some View {
        Text(kind.shortTitle)
            .font(.body.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // Solid fill stays readable on a selected (tinted) list row.
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }

    private var color: Color {
        switch kind {
        case .paid: return .blue
        case .free: return .green
        case .coachTheCoach: return .purple
        }
    }
}

struct IssueRow: View {
    let issue: ValidationIssue

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                    .font(.body)
                if issue.rule > 0 {
                    Text("유의사항 \(issue.rule)번")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
        }
    }
}

/// Shows how the session will appear in the official sheet.
struct SheetRowPreview: View {
    let entry: LogEntry
    private let formatter = KACFormatter()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("날짜", formatter.dateText(entry))
            row("시간", formatter.timeText(entry))
            row("고객명", formatter.clientText(entry).isEmpty ? "—" : formatter.clientText(entry))
            row("유료(분)", entry.kind == .paid ? "\(entry.recordedMinutes)" : "")
            row("무료(분)", entry.kind == .free ? "\(entry.recordedMinutes)" : "")
            row("받은 코치더코치(분)", entry.kind == .coachTheCoach ? "\(entry.recordedMinutes)" : "")
            row("코칭형태", formatter.formatSummary(entry))
        }
        .font(.body)
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value.isEmpty ? " " : value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}

// MARK: - Helpers

extension Calendar {
    /// Date of `day` with hour and minute of `time` (seconds cleared).
    func combine(day: Date, time: Date) -> Date {
        var components = dateComponents([.year, .month, .day], from: day)
        let clock = dateComponents([.hour, .minute], from: time)
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = 0
        return date(from: components) ?? day
    }
}

extension UTType {
    static var xlsxSpreadsheet: UTType {
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
    }
}

/// Exported coaching log: the KCA .xlsx form or the ICF .csv log.
struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xlsxSpreadsheet, .commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum AudioImporter {
    struct Imported {
        var fileName: String
        var duration: TimeInterval
        var recordedAt: Date?
    }

    /// Copies a user-selected audio file into the app's recordings folder.
    static func importAudio(from url: URL) throws -> Imported {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let destination = AudioStorage.newRecordingURL(fileExtension: fileExtension)
        try FileManager.default.copyItem(at: url, to: destination)

        var duration: TimeInterval = 0
        if let file = try? AVAudioFile(forReading: destination), file.processingFormat.sampleRate > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return Imported(
            fileName: destination.lastPathComponent,
            duration: duration,
            recordedAt: values?.creationDate ?? values?.contentModificationDate
        )
    }
}

extension View {
    /// iPad: a page-sized sheet instead of the small form sheet. iPhone sheets are unchanged.
    @ViewBuilder
    func largeSheetOnPad() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
