import AVFoundation
import CoreMedia
import Foundation
import Speech

struct TranscriptionOutput {
    var segments: [TranscriptSegment]
    var engine: String

    /// "[00:12] 안녕하세요 ..." one line per recognized phrase.
    var formattedText: String {
        segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\(KACDuration.clock($0.start))] \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case onDeviceUnsupported
    case unreadableAudio

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(localized: "음성 인식 권한이 없어요. 설정 앱에서 코칭일지의 음성 인식을 허용해 주세요.")
        case .recognizerUnavailable:
            return String(localized: "지금은 음성 인식을 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
        case .onDeviceUnsupported:
            return String(localized: "이 기기는 기기 내 인식을 지원하지 않아요. 설정에서 ‘기기 내 인식만 사용’을 끄면 서버 인식으로 변환할 수 있어요.")
        case .unreadableAudio:
            return String(localized: "오디오 파일을 읽을 수 없어요.")
        }
    }
}

/// Picks the best available speech-to-text engine:
/// - iOS 26 / macOS 26+: SpeechAnalyzer + SpeechTranscriber (on-device, long-form)
/// - Older systems: SFSpeechRecognizer, processed in chunks
enum TranscriptionService {
    /// Sessions are transcribed in the app's language: Korean or English.
    static let locale = Locale(identifier: Bundle.main.preferredLocalizations.first == "ko" ? "ko-KR" : "en-US")

    static func transcribe(
        fileURL: URL,
        requireOnDevice: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionOutput {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            if await AnalyzerSpeechEngine.supports(locale: locale) {
                return try await AnalyzerSpeechEngine().transcribe(fileURL: fileURL, locale: locale, progress: progress)
            }
        }
        #endif
        return try await LegacySpeechEngine().transcribe(
            fileURL: fileURL,
            locale: locale,
            requireOnDevice: requireOnDevice,
            progress: progress
        )
    }

    static func engineDescription() async -> String {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            if await AnalyzerSpeechEngine.supports(locale: locale) {
                return String(localized: "SpeechAnalyzer (기기 내 처리, 긴 녹음 최적화)")
            }
        }
        #endif
        return String(localized: "SFSpeechRecognizer (구간 분할 처리)")
    }
}

// MARK: - iOS 26+ engine

#if compiler(>=6.2)
@available(iOS 26.0, macOS 26.0, *)
struct AnalyzerSpeechEngine {
    static func supports(locale: Locale) async -> Bool {
        await matchingLocale(for: locale) != nil
    }

    static func matchingLocale(for locale: Locale) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let target = locale.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == target }) {
            return exact
        }
        let language = locale.language.languageCode?.identifier
        return supported.first { $0.language.languageCode?.identifier == language }
    }

    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionOutput {
        guard let matched = await Self.matchingLocale(for: locale) else {
            throw TranscriptionError.recognizerUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: matched,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // Downloads the Korean model once if it is not installed yet.
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.unreadableAudio
        }
        let totalSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let collector = Task { () async throws -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                let start = result.range.start.seconds
                let end = result.range.end.seconds
                segments.append(TranscriptSegment(
                    start: start.isFinite ? start : 0,
                    end: end.isFinite ? end : 0,
                    text: text
                ))
                if totalSeconds > 0, end.isFinite {
                    progress(min(1, end / totalSeconds))
                }
            }
            return segments
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }

        let segments = try await collector.value
        progress(1)
        return TranscriptionOutput(segments: segments, engine: "SpeechAnalyzer")
    }
}
#endif

// MARK: - Fallback engine

struct LegacySpeechEngine {
    /// Server-based recognition is limited to about a minute per request, so long recordings are split.
    private static let serverChunkSeconds: Double = 50
    private static let onDeviceChunkSeconds: Double = 120

    func transcribe(
        fileURL: URL,
        locale: Locale,
        requireOnDevice: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionOutput {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        let onDevice = recognizer.supportsOnDeviceRecognition
        if requireOnDevice && !onDevice {
            throw TranscriptionError.onDeviceUnsupported
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.unreadableAudio
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = file.length
        guard totalFrames > 0, sampleRate > 0 else { return TranscriptionOutput(segments: [], engine: "SFSpeechRecognizer") }

        let chunkSeconds = onDevice ? Self.onDeviceChunkSeconds : Self.serverChunkSeconds
        let chunkFrames = AVAudioFrameCount(sampleRate * chunkSeconds)
        var segments: [TranscriptSegment] = []

        while file.framePosition < totalFrames {
            try Task.checkCancellation()
            let chunkStartFrame = file.framePosition
            let remaining = AVAudioFrameCount(clamping: totalFrames - chunkStartFrame)
            let frames = min(chunkFrames, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                throw TranscriptionError.unreadableAudio
            }
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }

            let text = try await recognize(buffer: buffer, recognizer: recognizer, onDevice: onDevice)
            let start = Double(chunkStartFrame) / sampleRate
            let end = Double(file.framePosition) / sampleRate
            if !text.isEmpty {
                segments.append(TranscriptSegment(start: start, end: end, text: text))
            }
            progress(min(1, Double(file.framePosition) / Double(totalFrames)))
        }

        return TranscriptionOutput(
            segments: segments,
            engine: onDevice ? String(localized: "SFSpeechRecognizer (기기 내)") : String(localized: "SFSpeechRecognizer (서버)")
        )
    }

    private func recognize(buffer: AVAudioPCMBuffer, recognizer: SFSpeechRecognizer, onDevice: Bool) async throws -> String {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.append(buffer)
        request.endAudio()

        let gate = ResumeGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        if gate.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
                        return
                    }
                    if let error {
                        guard gate.claim() else { return }
                        let nsError = error as NSError
                        // 1110: no speech detected, 301: request canceled — treat silent chunks as empty text.
                        if nsError.domain == "kAFAssistantErrorDomain" && [1110, 301, 203].contains(nsError.code) {
                            continuation.resume(returning: "")
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                gate.setTask(task)
            }
        } onCancel: {
            gate.cancelTask()
        }
    }
}

/// Ensures a continuation is resumed exactly once.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    private var task: SFSpeechRecognitionTask?

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    func setTask(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancelTask() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
