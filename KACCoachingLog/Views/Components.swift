import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Participants editor (clients or coach-the-coach coach)

struct ParticipantsEditor: View {
    @Binding var kind: SessionKind
    @Binding var groupSize: Int
    @Binding var clientNames: [String]
    @Binding var ctcComposition: CTCComposition
    @Binding var ctcLicenseNumber: String
    var knownClients: [String]

    var body: some View {
        if kind == .coachTheCoach {
            coachTheCoachSection
        } else {
            clientSection
        }
    }

    private var clientSection: some View {
        Section {
            Stepper(value: $groupSize, in: 1...KACValidator.maxGroupSize) {
                LabeledContent("인원", value: groupSize == 1 ? "1:1 코칭" : "1:\(groupSize) 그룹코칭")
            }
            ForEach(0..<min(groupSize, 3), id: \.self) { index in
                TextField(placeholder(for: index), text: nameBinding(index))
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
            if groupSize > 3 {
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
                    LabeledContent("응시자 수", value: "\(groupSize)명")
                }
            }
        } header: {
            Text("받은 코치더코치")
        } footer: {
            Text("KAC 이상 인증 코치에게 받은 코치더코치만 인정돼요. 1:1·1:2는 2배로 계산되어 60~120분만 작성할 수 있고, 최대 25시간까지 인정돼요.")
        }
    }

    private var suggestedClients: [String] {
        let current = Set(clientNames.map { KACValidator.normalize($0) })
        return knownClients.filter { !current.contains(KACValidator.normalize($0)) }.prefix(12).map { $0 }
    }

    private func placeholder(for index: Int) -> String {
        groupSize == 1 ? "고객 이름" : "고객 \(index + 1) 이름"
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
        } else if groupSize < KACValidator.maxGroupSize {
            groupSize += 1
            if names.count < 3 { names.append(name) }
        }
        clientNames = names
    }
}

// MARK: - Small views

struct KindBadge: View {
    let kind: SessionKind

    var body: some View {
        Text(kind.shortTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
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
                    .font(.callout)
                if issue.rule > 0 {
                    Text("유의사항 \(issue.rule)번")
                        .font(.caption2)
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
            row("코칭형태", formatter.formatText(entry))
        }
        .font(.callout)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
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

struct XLSXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xlsxSpreadsheet] }

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
