import Foundation
import os

private let log = Logger(subsystem: "io.sprkplg.SparkPlug", category: "shortcuts")

/// Runs the person's own Shortcuts with `/usr/bin/shortcuts`. macOS has no public API for
/// turning Do Not Disturb on and off, so Focus runs a Shortcut that does it (see the README).
enum ShortcutRunner {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// One at a time, in order, so a quick "off" then "on" can never finish the wrong way round.
    private static let queue = DispatchQueue(label: "io.sprkplg.SparkPlug.shortcuts")

    /// Runs `name` in the background; failures are logged, never shown mid-focus.
    static func run(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        queue.async {
            do {
                let (status, output) = try execute(["run", name])
                if status != 0 { log.error("shortcut \(name, privacy: .public) exited \(status): \(output, privacy: .public)") }
            } catch {
                log.error("shortcut \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The names of the person's shortcuts, for the pickers in Settings.
    static func list() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let (status, output) = try? execute(["list"]), status == 0 else {
                    continuation.resume(returning: [])
                    return
                }
                let names = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                continuation.resume(returning: names)
            }
        }
    }

    /// Runs the tool and waits for it, reading its output to the end first (so a long listing
    /// cannot fill the pipe and stall it). Call it off the main thread.
    private static func execute(_ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
