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
            let text = self.run(audioURL: audioURL, mode: mode, language: "auto")

            // Whisper often misdetects Bangla as Hindi on short clips. If auto-detect
            // produced Devanagari, re-run once forced to Bangla.
            if mode == .transcribe, let text, Self.looksLikeHindiMisdetection(text) {
                completion(self.run(audioURL: audioURL, mode: mode, language: "bn") ?? text)
                return
            }
            completion(text)
        }
    }

    /// True when the text is dominated by Devanagari script — the bn→hi misdetection signature.
    static func looksLikeHindiMisdetection(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let devanagari = letters.filter { (0x0900...0x097F).contains($0.value) }
        return Double(devanagari.count) / Double(letters.count) > 0.5
    }

    private func run(audioURL: URL, mode: DictationMode, language: String) -> String? {
        guard let cli = Self.findWhisperCLI() else { return nil }
        let modelPath = ModelManager.modelPath(for: mode).path

        var arguments = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language,
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

        currentProcess = process
        do {
            try process.run()
        } catch {
            currentProcess = nil
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let wasCancelled = currentProcess !== process
        currentProcess = nil

        guard !wasCancelled, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cancels any in-flight transcription (e.g. when a new dictation starts).
    func cancel() {
        if let process = currentProcess, process.isRunning {
            currentProcess = nil
            process.terminate()
        }
    }
}
