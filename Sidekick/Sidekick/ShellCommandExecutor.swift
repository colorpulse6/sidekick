
import Foundation

enum ShellCommandError: Error {
    case commandNotFound
    case executionFailed(String)
    case invalidOutput
}

class ShellCommandExecutor {
    func execute(_ command: String) async throws -> String {
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // Capture stderr as well

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        continuation.resume(throwing: ShellCommandError.invalidOutput)
                    }
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ShellCommandError.executionFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellCommandError.commandNotFound)
            }
        }
    }
}
