import Foundation
import Observation
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Runs transcriptions in the background of the app and writes results back to the session.
@MainActor
@Observable
final class TranscriptionCenter {
    private(set) var progress: [UUID: Double] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Sessions being deleted: their running transcription must not touch the model again.
    @ObservationIgnored private var discarded: Set<UUID> = []

    nonisolated init() {}

    func isRunning(_ session: CoachingSession) -> Bool {
        tasks[session.uuid] != nil
    }

    func progressValue(for session: CoachingSession) -> Double? {
        progress[session.uuid]
    }

    func start(_ session: CoachingSession, requireOnDevice: Bool) {
        guard let url = session.audioFileURL else {
            session.transcriptionState = .failed
            session.transcriptionError = "녹음 파일이 없어요."
            return
        }
        let id = session.uuid
        guard tasks[id] == nil else { return }

        session.transcriptionState = .inProgress
        session.transcriptionError = ""
        progress[id] = 0
        updateIdleTimer()

        tasks[id] = Task {
            do {
                let output = try await TranscriptionService.transcribe(
                    fileURL: url,
                    requireOnDevice: requireOnDevice
                ) { value in
                    Task { @MainActor in
                        if self.tasks[id] != nil { self.progress[id] = value }
                    }
                }
                guard !self.discarded.contains(id) else {
                    self.finish(id)
                    return
                }
                session.transcriptSegments = output.segments
                session.transcript = output.formattedText
                session.transcriptionEngine = output.engine
                session.transcriptionState = .completed
                if output.segments.isEmpty {
                    session.transcriptionError = "인식된 말소리가 없어요."
                }
            } catch {
                if !self.discarded.contains(id) {
                    if error is CancellationError {
                        session.transcriptionState = session.transcript.isEmpty ? .idle : .completed
                    } else {
                        session.transcriptionState = .failed
                        session.transcriptionError = error.localizedDescription
                    }
                }
            }
            if !self.discarded.contains(id) {
                try? session.modelContext?.save()
            }
            self.finish(id)
        }
    }

    func cancel(_ session: CoachingSession) {
        tasks[session.uuid]?.cancel()
    }

    /// Call before deleting a session.
    func discard(_ session: CoachingSession) {
        let id = session.uuid
        guard let task = tasks[id] else { return }
        discarded.insert(id)
        task.cancel()
    }

    /// Sessions left "in progress" by a previous launch can never finish; mark them as failed.
    func recoverInterrupted(_ sessions: [CoachingSession]) {
        for session in sessions where session.transcriptionState == .inProgress && tasks[session.uuid] == nil {
            session.transcriptionState = .failed
            session.transcriptionError = "앱이 종료되어 변환이 중단됐어요. 다시 변환해 주세요."
        }
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
        discarded.remove(id)
        progress[id] = nil
        updateIdleTimer()
    }

    /// Keeps an iPhone awake while long recordings are transcribed.
    private func updateIdleTimer() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = !tasks.isEmpty || !progress.isEmpty
        #endif
    }
}
