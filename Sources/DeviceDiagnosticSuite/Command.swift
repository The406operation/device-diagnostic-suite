import Foundation

enum Command {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) async -> (Int32, String) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            guard let output = try? FileHandle(forWritingTo: outputURL) else { return (-1, "Cannot create output file") }
            process.standardOutput = output
            process.standardError = output
            do { try process.run() } catch {
                try? output.close()
                try? FileManager.default.removeItem(at: outputURL)
                return (-1, error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            let timedOut = process.isRunning
            if timedOut { process.terminate() }
            try? output.close()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            try? FileManager.default.removeItem(at: outputURL)
            return (timedOut ? -2 : process.terminationStatus,
                    String(decoding: data.prefix(4_000_000), as: UTF8.self))
        }.value
    }

    static func tool(_ name: String) -> String? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}
