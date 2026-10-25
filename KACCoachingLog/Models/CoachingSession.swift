import Foundation
import SwiftData

enum TranscriptionState: String, Codable {
    case idle
    case inProgress
    case completed
    case failed
}

struct TranscriptSegment: Codable, Hashable {
    /// Seconds from the beginning of the recording.
    var start: Double
    var end: Double
    var text: String
}

@Model
final class CoachingSession {
    var uuid: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Newline-separated client names. For coach-the-coach, the first line is the coach's name.
    var clientNamesText: String = ""
    var groupSize: Int = 1
    var kindRaw: String = SessionKind.paid.rawValue
    var formatRaw: String = CoachingFormat.faceToFace.rawValue
    var ctcCompositionRaw: String = CTCComposition.oneOnOne.rawValue
    var ctcLicenseNumber: String = ""
    var minutesOverride: Int? = nil
    var topic: String = ""
    var notes: String = ""
    var transcript: String = ""
    var transcriptSegmentsData: Data? = nil
    var transcriptionStateRaw: String = TranscriptionState.idle.rawValue
    var transcriptionEngine: String = ""
    var transcriptionError: String = ""
    var audioFileName: String? = nil
    var createdAt: Date = Date()

    init(
        startDate: Date,
        endDate: Date,
        clientNames: [String] = [],
        groupSize: Int = 1,
        kind: SessionKind = .paid,
        format: CoachingFormat = .faceToFace
    ) {
        self.uuid = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.clientNamesText = clientNames.joined(separator: "\n")
        self.groupSize = groupSize
        self.kindRaw = kind.rawValue
        self.formatRaw = format.rawValue
        self.createdAt = Date()
    }
}

extension CoachingSession {
    var kind: SessionKind {
        get { SessionKind(rawValue: kindRaw) ?? .paid }
        set { kindRaw = newValue.rawValue }
    }

    var format: CoachingFormat {
        get { CoachingFormat(rawValue: formatRaw) ?? .faceToFace }
        set { formatRaw = newValue.rawValue }
    }

    var ctcComposition: CTCComposition {
        get { CTCComposition(rawValue: ctcCompositionRaw) ?? .oneOnOne }
        set { ctcCompositionRaw = newValue.rawValue }
    }

    var transcriptionState: TranscriptionState {
        get { TranscriptionState(rawValue: transcriptionStateRaw) ?? .idle }
        set { transcriptionStateRaw = newValue.rawValue }
    }

    var clientNames: [String] {
        get { clientNamesText.components(separatedBy: "\n") }
        set { clientNamesText = newValue.joined(separator: "\n") }
    }

    var transcriptSegments: [TranscriptSegment] {
        get {
            guard let data = transcriptSegmentsData else { return [] }
            return (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
        }
        set { transcriptSegmentsData = try? JSONEncoder().encode(newValue) }
    }

    var audioFileURL: URL? {
        guard let audioFileName else { return nil }
        let url = AudioStorage.recordingsDirectory.appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var logEntry: LogEntry {
        LogEntry(
            id: uuid,
            start: startDate,
            end: endDate,
            clientNames: clientNames,
            groupSize: groupSize,
            kind: kind,
            format: format,
            ctcComposition: ctcComposition,
            ctcLicenseNumber: ctcLicenseNumber,
            minutesOverride: minutesOverride
        )
    }

    /// Short label for lists: "홍길동", "홍길동 외 2명", "김코치 (CTC)"
    var displayTitle: String {
        let names = logEntry.cleanedClientNames
        guard let first = names.first else { return String(localized: "이름 없음") }
        if kind == .coachTheCoach { return String(localized: "\(first) 코치") }
        let others = max(logEntry.participantCount - 1, 0)
        return others > 0 ? String(localized: "\(first) 외 \(others)명") : first
    }

    func deleteAudioFile() {
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileName = nil
    }
}

enum AudioStorage {
    static var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func newRecordingURL(fileExtension: String = "m4a") -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "coaching-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).\(fileExtension)"
        return recordingsDirectory.appendingPathComponent(name)
    }

    static func totalSizeText() -> String {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let bytes = urls.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
