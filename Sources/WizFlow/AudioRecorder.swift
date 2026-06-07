import AVFoundation

/// Records microphone audio to a 16kHz mono 16-bit PCM WAV file — the format whisper.cpp expects.
final class AudioRecorder {
    struct Result {
        let fileURL: URL
        let duration: TimeInterval
    }

    /// Recordings shorter than this are treated as accidental taps and discarded.
    private static let minimumDuration: TimeInterval = 0.3

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizflow-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw NSError(domain: "WizFlow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Recording failed to start. Check microphone access in System Settings → Privacy & Security → Microphone."
            ])
        }
        self.recorder = recorder
        startedAt = Date()
    }

    /// Stops recording. Returns nil (and deletes the file) if the recording was too short.
    func stop() -> Result? {
        guard let recorder, let startedAt else { return nil }
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil

        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return Result(fileURL: recorder.url, duration: duration)
    }
}
