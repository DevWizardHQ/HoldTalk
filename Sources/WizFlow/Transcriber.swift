import Foundation

/// Runs whisper-cli as a one-shot subprocess per dictation.
/// No model is kept resident in memory — the process exits when transcription finishes,
/// keeping WizFlow's idle footprint near zero.
final class Transcriber {
    private var currentProcess: Process?
    private let queue = DispatchQueue(label: "wizflow.transcriber")

    /// Locates the whisper.cpp CLI binary (Homebrew installs it as whisper-cli).
    static func findWhisperCLI() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func transcribe(audioURL: URL, mode: DictationMode, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let cli = Self.findWhisperCLI() else {
                completion(nil)
                return
            }
            let modelPath = ModelManager.modelPath(for: mode).path

            var arguments = [
                "-m", modelPath,
                "-f", audioURL.path,
                "-l", "auto",
                "-nt",          // no timestamps
                "-np",          // no progress/debug prints
                "-t", "4",      // 4 threads — fast on M1 without starving other work
            ]
            if mode == .translate {
                arguments.append("--translate")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = arguments
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe() // discard

            self.currentProcess = process
            do {
                try process.run()
            } catch {
                self.currentProcess = nil
                completion(nil)
                return
            }

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let wasCancelled = self.currentProcess !== process
            self.currentProcess = nil

            guard !wasCancelled, process.terminationStatus == 0 else {
                completion(wasCancelled ? nil : nil)
                return
            }

            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            completion(text)
        }
    }

    /// Cancels any in-flight transcription (e.g. when a new dictation starts).
    func cancel() {
        if let process = currentProcess, process.isRunning {
            currentProcess = nil
            process.terminate()
        }
    }
}
