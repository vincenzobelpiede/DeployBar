import Foundation

/// Redirects stdout/stderr to a rotating log file at
/// ~/Library/Logs/DeployBar/deploybar.log.
/// Max file size: 5 MB — rotated to deploybar.log.1 when exceeded.
final class FileLogger {
    static let shared = FileLogger()

    let logDirectory: URL
    let logFileURL: URL
    private let maxSize: UInt64 = 5 * 1024 * 1024  // 5 MB
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.salesforza.deploybar.logger")

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDirectory = home.appendingPathComponent("Library/Logs/DeployBar")
        logFileURL = logDirectory.appendingPathComponent("deploybar.log")

        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Create file if needed
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Write startup marker
        let startLine = "[\(Self.timestamp())] ── DeployBar launched ──\n"
        if let data = startLine.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    /// Call once from applicationDidFinishLaunching to capture stdout/stderr.
    func redirectOutput() {
        let outPipe = Pipe()
        let errPipe = Pipe()

        // Duplicate originals so Xcode console still works during development
        let origOut = dup(STDOUT_FILENO)
        let origErr = dup(STDERR_FILENO)

        dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        let handler: (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Write to original fd so console still works
            write(origOut, (data as NSData).bytes, data.count)
            self?.writeToLog(data)
        }

        let errHandler: (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            write(origErr, (data as NSData).bytes, data.count)
            self?.writeToLog(data)
        }

        outPipe.fileHandleForReading.readabilityHandler = handler
        errPipe.fileHandleForReading.readabilityHandler = errHandler
    }

    /// Write a line directly to the log (for structured app-level logging).
    func log(_ message: String, level: String = "INFO") {
        let line = "[\(Self.timestamp())] [\(level)] \(message)\n"
        if let data = line.data(using: .utf8) {
            writeToLog(data)
        }
    }

    private func writeToLog(_ data: Data) {
        queue.async { [weak self] in
            guard let self, let fh = self.fileHandle else { return }
            self.rotateIfNeeded()
            fh.write(data)
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= maxSize else { return }

        let rotated = logDirectory.appendingPathComponent("deploybar.log.1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: logFileURL, to: rotated)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)

        // The old file handle's fd still points at the moved inode. Truncate
        // in place so continued writes go into a fresh region — the OS reclaims
        // the moved file's space once its fd closes (at next launch).
        fileHandle?.truncateFile(atOffset: 0)
        fileHandle?.seekToEndOfFile()
        let marker = "[\(Self.timestamp())] ── Log rotated ──\n"
        if let data = marker.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
