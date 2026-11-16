import Foundation

enum MoleError: LocalizedError {
    case notInstalled
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Không tìm thấy lệnh `mo`. Cài Mole bằng: brew install mole"
        case .badOutput(let detail):
            return "Không đọc được kết quả từ Mole: \(detail)"
        }
    }
}

/// Thin wrapper around the `mo` command-line tool.
enum Mole {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Looked up on every call so installing Mole while the app runs is picked up.
    static var path: String? {
        firstExecutable(["/opt/homebrew/bin/mo", "/usr/local/bin/mo",
                         "\(home)/.local/bin/mo", "\(home)/.config/mole/bin/mo"])
    }

    static var brewPath: String? {
        firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Environment for child processes. GUI apps get a minimal PATH, so add the usual locations.
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let basePath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = basePath + (env["PATH"].map { ":" + $0 } ?? "")
        env["HOME"] = home
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        for (k, v) in extra { env[k] = v }
        return env
    }

    /// Runs `mo args...` with stdin closed and returns stdout. Cancelling the task terminates the process.
    static func run(_ args: [String]) async throws -> Data {
        guard let path else { throw MoleError.notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.environment = environment(extra: ["NO_COLOR": "1"])
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        cont.resume(throwing: error)
                        return
                    }
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    cont.resume(returning: data)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    static func runJSON<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        let data = try await run(args)
        try Task.checkCancellation()
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(decoding: data.prefix(300), as: UTF8.self)
            throw MoleError.badOutput("\(error.localizedDescription)\n\(preview)")
        }
    }
}

/// Runs a long-lived `mo` process and delivers its output line by line on the main thread.
final class LineStream {
    private var process: Process?
    private var buffer = Data()

    var isRunning: Bool { process?.isRunning ?? false }

    func start(_ args: [String],
               mergeStderr: Bool = false,
               onLine: @escaping (String) -> Void,
               onExit: @escaping (Int32) -> Void) throws {
        guard let path = Mole.path else { throw MoleError.notInstalled }
        stop()
        buffer = Data()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.environment = Mole.environment(extra: ["NO_COLOR": "1"])
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeStderr ? pipe : FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                self.buffer.append(chunk)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let lineData = self.buffer[self.buffer.startIndex..<nl]
                    self.buffer.removeSubrange(self.buffer.startIndex...nl)
                    onLine(String(decoding: lineData, as: UTF8.self))
                }
            }
        }
        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async { [weak self] in
                if let self {
                    self.buffer.append(rest)
                    if !self.buffer.isEmpty {
                        for line in String(decoding: self.buffer, as: UTF8.self).split(separator: "\n") {
                            onLine(String(line))
                        }
                        self.buffer = Data()
                    }
                }
                onExit(p.terminationStatus)
            }
        }
        try process.run()
        self.process = process
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    deinit { stop() }
}

extension String {
    /// Removes ANSI escape sequences and carriage-return spinner frames.
    var strippingANSI: String {
        var s = self.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
        if let lastCR = s.lastIndex(of: "\r") { s = String(s[s.index(after: lastCR)...]) }
        return s
    }
}

enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ value: Int64) -> String { byteFormatter.string(fromByteCount: value) }

    static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "vi_VN")))
    }

    static func bytes(_ value: Double) -> String { bytes(Int64(value)) }

    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }

    /// Parses Mole's human sizes ("1.20GB", "512KB", "0B"). Mole uses base-1000 units.
    static func parseSize(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
        for (unit, factor) in units where t.hasSuffix(unit) {
            let number = t.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
            guard let v = Double(number) else { return nil }
            return Int64(v * factor)
        }
        return nil
    }
}
