import Foundation

// MARK: - mo status --json / --watch

struct StatusSnapshot: Decodable {
    var collected_at: String?
    var host: String?
    var uptime: String?
    var procs: Int?
    var hardware: Hardware?
    var health_score: Int?
    var health_score_msg: String?
    var cpu: CPU?
    var gpu: [GPU]?
    var memory: Memory?
    var disks: [Disk]?
    var trash_size: Int64?
    var disk_io: DiskIO?
    var network: [Network]?
    var batteries: [Battery]?
    var thermal: Thermal?
    var top_processes: [Proc]?

    struct Hardware: Decodable {
        var model: String?
        var cpu_model: String?
        var total_ram: String?
        var disk_size: String?
        var os_version: String?
    }

    struct CPU: Decodable {
        var usage: Double?
        var per_core: [Double]?
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var core_count: Int?
        var p_core_count: Int?
        var e_core_count: Int?
    }

    struct GPU: Decodable {
        var name: String?
        var usage: Double?
        var core_count: Int?
    }

    struct Memory: Decodable {
        var used: Int64?
        var total: Int64?
        var available: Int64?
        var used_percent: Double?
        var swap_used: Int64?
        var swap_total: Int64?
        var cached: Int64?
        var pressure: String?
    }

    struct Disk: Decodable, Identifiable {
        var mount: String
        var device: String?
        var used: Int64?
        var total: Int64?
        var used_percent: Double?
        var fstype: String?
        var external: Bool?
        var purgeable: Int64?
        var id: String { mount }
    }

    struct DiskIO: Decodable {
        var read_rate: Double?
        var write_rate: Double?
    }

    struct Network: Decodable, Identifiable {
        var name: String
        var rx_rate_mbs: Double?
        var tx_rate_mbs: Double?
        var ip: String?
        var id: String { name }
    }

    struct Battery: Decodable {
        var percent: Double?
        var status: String?
        var time_left: String?
        var health: String?
        var cycle_count: Int?
        var capacity: Double?
    }

    struct Thermal: Decodable {
        var cpu_temp: Double?
        var battery_temp: Double?
        var system_power: Double?
        var adapter_power: Double?
    }

    struct Proc: Decodable, Identifiable {
        var pid: Int
        var name: String?
        var command: String?
        var cpu: Double?
        var memory: Double?
        var memory_bytes: Int64?
        var id: Int { pid }
    }
}

// MARK: - mo analyze --json

struct AnalyzeResult: Decodable {
    var scan_status: String?
    var path: String?
    var overview: Bool?
    var entries: [Entry]?
    var large_files: [Entry]?
    var total_size: Int64?
    var total_files: Int64?

    struct Entry: Decodable, Identifiable, Hashable {
        var name: String
        var path: String
        var size: Int64?
        var is_dir: Bool?
        var last_access: String?
        var scan_status: String?
        var id: String { path }
    }
}

// MARK: - mo uninstall --list

struct InstalledApp: Decodable, Identifiable, Hashable {
    var name: String
    var bundle_id: String?
    var source: String?
    var uninstall_name: String
    var path: String?
    var size: String?

    var id: String { (bundle_id ?? "") + "|" + (path ?? uninstall_name) }
    var sizeBytes: Int64 { size.flatMap(Fmt.parseSize) ?? -1 }
}

// MARK: - mo history --json

struct HistoryResult: Decodable {
    var sessions: [Session]?

    struct Session: Decodable, Identifiable {
        var command: String
        var run_id: String?
        var started_at: String?
        var ended_at: String?
        var items: Int?
        var size: String?
        var operation_count: Int?
        var failed_tasks: Int?
        var actions: Actions?
        var id: String { (run_id ?? "") + command + (started_at ?? "") }
    }

    struct Actions: Decodable {
        var removed: Int?
        var trashed: Int?
        var skipped: Int?
        var failed: Int?
    }
}

// MARK: - ~/.config/mole/clean-list.txt (written by mo clean --dry-run)

struct CleanItem: Identifiable, Hashable {
    var path: String
    var sizeText: String
    var bytes: Int64?
    var itemCount: Int
    var coveredBy: String?
    var id: String { path }
}

struct CleanSection: Identifiable {
    var name: String
    var items: [CleanItem]
    var id: String { name }
    var totalBytes: Int64 {
        items.filter { $0.coveredBy == nil }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
}

enum CleanListParser {
    static let fileURL = URL(fileURLWithPath: Mole.home)
        .appendingPathComponent(".config/mole/clean-list.txt")

    static func load() -> (date: Date?, sections: [CleanSection]) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return (nil, []) }
        let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (date, parse(text))
    }

    static func parse(_ text: String) -> [CleanSection] {
        var sections: [CleanSection] = []
        var current: CleanSection?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                if let c = current, !c.items.isEmpty { sections.append(c) }
                let name = String(line.dropFirst(4).dropLast(4))
                current = CleanSection(name: name, items: [])
                continue
            }

            // "<path>  # <size>[, N items][, counted under <path>]"
            guard let sep = line.range(of: "  # ", options: .backwards) else { continue }
            let path = String(line[..<sep.lowerBound])
            let meta = line[sep.upperBound...].components(separatedBy: ", ")
            let sizeText = meta.first ?? ""
            var count = 1
            var coveredBy: String?
            for part in meta.dropFirst() {
                if part.hasSuffix(" items"), let n = Int(part.dropLast(6)) { count = n }
                if part.hasPrefix("counted under ") { coveredBy = String(part.dropFirst(14)) }
            }
            let item = CleanItem(path: path, sizeText: sizeText,
                                 bytes: Fmt.parseSize(sizeText), itemCount: count, coveredBy: coveredBy)
            if current == nil { current = CleanSection(name: "Khác", items: []) }
            current?.items.append(item)
        }
        if let c = current, !c.items.isEmpty { sections.append(c) }
        return sections
    }
}
