import Foundation

/// Manages the whisper.cpp GGML model files on disk.
/// Models live in ~/Library/Application Support/WizFlow/models/.
enum ModelManager {
    struct Model {
        let fileName: String
        let downloadURL: URL
        let approximateSize: String
    }

    static let transcribeModel = Model(
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
        approximateSize: "574 MB"
    )

    static let translateModel = Model(
        fileName: "ggml-medium-q5_0.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin")!,
        approximateSize: "539 MB"
    )

    static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WizFlow/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func model(for mode: DictationMode) -> Model {
        mode == .transcribe ? transcribeModel : translateModel
    }

    static func modelPath(for mode: DictationMode) -> URL {
        modelsDirectory.appendingPathComponent(model(for: mode).fileName)
    }

    static func modelInstalled(for mode: DictationMode) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: mode).path)
    }
}

/// Downloads a model file with progress reporting, for the Settings UI.
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0
    @Published var isDownloading = false
    @Published var errorMessage: String?

    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func download(_ model: ModelManager.Model) {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        errorMessage = nil
        destination = ModelManager.modelsDirectory.appendingPathComponent(model.fileName)
        task = session.downloadTask(with: model.downloadURL)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        DispatchQueue.main.async { self.isDownloading = false }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progress = value }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
        DispatchQueue.main.async {
            self.isDownloading = false
            self.progress = 1
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isDownloading = false
            self.errorMessage = error.localizedDescription
        }
    }
}
