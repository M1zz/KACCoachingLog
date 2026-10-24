import AVFoundation
import Foundation
import Observation

struct RecordingResult {
    var fileURL: URL?
    var startDate: Date
    var endDate: Date
    var recordedDuration: TimeInterval
}

enum RecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "마이크 권한이 없어요. 설정 앱에서 코칭일지의 마이크 접근을 허용해 주세요."
        case .couldNotStart:
            return "녹음을 시작하지 못했어요. 다른 앱이 마이크를 사용 중인지 확인해 주세요."
        }
    }
}

/// Records a coaching session to an AAC (.m4a) file.
/// Also works as a plain session timer when audio recording is turned off (e.g. no client consent).
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording
        case paused
    }

    private(set) var state: State = .idle
    private(set) var startDate: Date?
    private(set) var isRecordingAudio = false
    private(set) var wasInterrupted = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // MARK: Permission

    static func requestPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
        #endif
    }

    // MARK: Control

    func start(recordAudio: Bool) async throws {
        guard state == .idle else { return }
        pausedTotal = 0
        pausedAt = nil
        wasInterrupted = false

        if recordAudio {
            guard await Self.requestPermission() else { throw RecorderError.permissionDenied }
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            observeInterruptions()
            #endif

            let url = AudioStorage.newRecordingURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecorderError.couldNotStart
            }
            self.recorder = recorder
            self.fileURL = url
            isRecordingAudio = true
        } else {
            recorder = nil
            fileURL = nil
            isRecordingAudio = false
        }

        startDate = Date()
        state = .recording
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        pausedAt = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        recorder?.record()
        if let pausedAt {
            pausedTotal += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        wasInterrupted = false
        state = .recording
    }

    /// Stops and returns the result. The session's end time is the moment of stopping.
    func stop() -> RecordingResult? {
        guard state != .idle, let startDate else { return nil }
        let endDate = Date()
        let duration = elapsed(at: endDate)
        recorder?.stop()
        recorder = nil
        removeInterruptionObserver()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        let result = RecordingResult(fileURL: fileURL, startDate: startDate, endDate: endDate, recordedDuration: duration)
        reset()
        return result
    }

    /// Stops and deletes the recording.
    func discard() {
        let url = fileURL
        recorder?.stop()
        recorder = nil
        removeInterruptionObserver()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if let url { try? FileManager.default.removeItem(at: url) }
        reset()
    }

    private func reset() {
        fileURL = nil
        startDate = nil
        pausedAt = nil
        pausedTotal = 0
        isRecordingAudio = false
        wasInterrupted = false
        state = .idle
    }

    // MARK: Metering (polled by the UI through TimelineView)

    /// Wall-clock time since start, excluding pauses.
    #if DEBUG
    /// Screenshot mode: shows a session that has been running for `elapsed` seconds, without the microphone.
    func startPreview(elapsed: TimeInterval) {
        startDate = Date().addingTimeInterval(-elapsed)
        isRecordingAudio = true
        state = .recording
    }
    #endif

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let startDate else { return 0 }
        var paused = pausedTotal
        if let pausedAt { paused += date.timeIntervalSince(pausedAt) }
        return max(0, date.timeIntervalSince(startDate) - paused)
    }

    /// Normalized input level 0...1.
    func currentLevel() -> Double {
        guard let recorder, state == .recording else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        let floor = -50.0
        guard decibels > floor else { return 0 }
        return min(1, (decibels - floor) / -floor)
    }

    // MARK: Interruptions (phone calls etc.)

    #if os(iOS)
    private func observeInterruptions() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            switch type {
            case .began:
                if self.state == .recording {
                    self.pause()
                    self.wasInterrupted = true
                }
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if options.contains(.shouldResume) && self.state == .paused && self.wasInterrupted {
                    self.resume()
                }
            @unknown default:
                break
            }
        }
    }
    #endif

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }
}
