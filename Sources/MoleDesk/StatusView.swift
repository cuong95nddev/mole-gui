import SwiftUI

/// One `mo status --watch` stream shared by the overview pane and the menu bar panel.
/// It runs while at least one of them is on screen.
@Observable
final class StatusModel {
    var snapshot: StatusSnapshot?
    var error: String?
    /// Recent samples (oldest first) for the menu bar sparklines.
    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var netHistory: [Double] = []
    private let stream = LineStream()
    private var users = 0
    static let historyLength = 40

    func acquire() {
        users += 1
        start()
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { stream.stop() }
    }

    private func start() {
        guard !stream.isRunning else { return }
        do {
            try stream.start(["status", "--watch", "--interval", "2s"], onLine: { [weak self] line in
                guard let self, line.hasPrefix("{"), let data = line.data(using: .utf8) else { return }
                do {
                    let s = try JSONDecoder().decode(StatusSnapshot.self, from: data)
                    self.snapshot = s
                    self.record(s)
                    self.error = nil
                } catch {
                    self.error = "Không đọc được dữ liệu trạng thái: \(error.localizedDescription)"
                }
            }, onExit: { [weak self] code in
                if code != 0 && code != 15 { self?.error = "mo status đã dừng (mã \(code))." }
            })
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func record(_ s: StatusSnapshot) {
        func push(_ arr: inout [Double], _ v: Double) {
            arr.append(v)
            if arr.count > Self.historyLength { arr.removeFirst(arr.count - Self.historyLength) }
        }
        push(&cpuHistory, s.cpu?.usage ?? 0)
        push(&memHistory, s.memory?.used_percent ?? 0)
        push(&gpuHistory, max(0, s.gpu?.first?.usage ?? 0))
        push(&netHistory, s.networkRate.rx + s.networkRate.tx)
    }
}

extension StatusSnapshot {
    /// Total receive/transmit over all interfaces, in MB/s.
    var networkRate: (rx: Double, tx: Double) {
        (network ?? []).reduce((0, 0)) { ($0.0 + ($1.rx_rate_mbs ?? 0), $0.1 + ($1.tx_rate_mbs ?? 0)) }
    }
}

struct StatusView: View {
    @Environment(AppState.self) private var app
    private var model: StatusModel { app.status }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error { ErrorBanner(message: error) }

            if let s = model.snapshot {
                ScrollView {
                    VStack(spacing: 14) {
                        HealthHeader(snapshot: s)
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 14) {
                                cpuCard(s)
                                disksCard(s)
                                networkCard(s)
                            }
                            VStack(spacing: 14) {
                                memoryCard(s)
                                if let b = s.batteries?.first { batteryCard(b, thermal: s.thermal) }
                            }
                        }
                        processesCard(s)
                    }
                    .padding(20)
                }
            } else if model.error == nil {
                ProgressView("Đang đọc thông số hệ thống…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .paneHeader("Tổng quan", subtitle: subtitle) {
            Button {
                app.runInTerminal("Bảng theo dõi của Mole", ["status"])
            } label: {
                Label("Mở bảng gốc", systemImage: "terminal")
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }

    private var subtitle: String? {
        guard let h = model.snapshot?.hardware else { return nil }
        return [h.model, h.cpu_model, h.total_ram, h.os_version].compactMap { $0 }.joined(separator: " · ")
    }

    private func cpuCard(_ s: StatusSnapshot) -> some View {
        Card(title: "CPU", icon: "cpu") {
            let usage = s.cpu?.usage ?? 0
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.percent(usage)).font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                if let c = s.cpu {
                    Text("Tải \(String(format: "%.2f · %.2f · %.2f", c.load1 ?? 0, c.load5 ?? 0, c.load15 ?? 0))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Meter(value: usage / 100)
            if let cores = s.cpu?.per_core, !cores.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.35 + 0.65 * min(1, v / 100)))
                            .frame(height: max(3, 34 * min(1, v / 100)))
                    }
                }
                .frame(height: 34, alignment: .bottom)
                .animation(.easeOut(duration: 0.4), value: cores)
            }
            if let c = s.cpu, let p = c.p_core_count, let e = c.e_core_count {
                Text("\(p) nhân hiệu năng · \(e) nhân tiết kiệm · \(s.procs ?? 0) tiến trình")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func memoryCard(_ s: StatusSnapshot) -> some View {
        Card(title: "Bộ nhớ", icon: "memorychip") {
            let m = s.memory
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.percent(m?.used_percent ?? 0)).font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(Fmt.bytes(m?.used ?? 0)) / \(Fmt.bytes(m?.total ?? 0))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Meter(value: (m?.used_percent ?? 0) / 100)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Còn trống").foregroundStyle(.secondary)
                    Text(Fmt.bytes(m?.available ?? 0))
                }
                GridRow {
                    Text("Swap").foregroundStyle(.secondary)
                    Text("\(Fmt.bytes(m?.swap_used ?? 0)) / \(Fmt.bytes(m?.swap_total ?? 0))")
                }
                GridRow {
                    Text("Áp lực").foregroundStyle(.secondary)
                    Text(m?.pressure?.capitalized ?? "—")
                }
            }
            .font(.callout)
        }
    }

    private func disksCard(_ s: StatusSnapshot) -> some View {
        Card(title: "Ổ đĩa", icon: "internaldrive") {
            ForEach((s.disks ?? []).filter { !$0.mount.contains("/CoreSimulator/") }) { d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(d.mount == "/" ? "Macintosh HD" : (d.mount as NSString).lastPathComponent)
                            .font(.callout.weight(.medium)).lineLimit(1)
                        if d.external == true { Text("ngoài").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(Fmt.bytes(d.used ?? 0)) / \(Fmt.bytes(d.total ?? 0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Meter(value: (d.used_percent ?? 0) / 100, height: 6)
                }
            }
            if let trash = s.trash_size, trash > 0 {
                Text("Thùng rác: \(Fmt.bytes(trash))").font(.caption).foregroundStyle(.secondary)
            }
            if let io = s.disk_io {
                Text("Đọc \(String(format: "%.1f", io.read_rate ?? 0)) MB/s · Ghi \(String(format: "%.1f", io.write_rate ?? 0)) MB/s")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func batteryCard(_ b: StatusSnapshot.Battery, thermal: StatusSnapshot.Thermal?) -> some View {
        Card(title: "Pin", icon: "battery.100percent") {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.percent(b.percent ?? 0)).font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Text(statusText(b.status)).font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Text("Tình trạng").foregroundStyle(.secondary); Text(b.health ?? "—") }
                GridRow { Text("Dung lượng tối đa").foregroundStyle(.secondary); Text(b.capacity.map { Fmt.percent($0) } ?? "—") }
                GridRow { Text("Số lần sạc").foregroundStyle(.secondary); Text(b.cycle_count.map(String.init) ?? "—") }
                if let t = thermal?.battery_temp, t > 0 {
                    GridRow { Text("Nhiệt độ pin").foregroundStyle(.secondary); Text(String(format: "%.1f °C", t)) }
                }
                if let w = thermal?.system_power, w > 0 {
                    GridRow { Text("Công suất hệ thống").foregroundStyle(.secondary); Text(String(format: "%.1f W", w)) }
                }
            }
            .font(.callout)
        }
    }

    private func statusText(_ s: String?) -> String {
        switch s?.lowercased() {
        case "charged": "Đã sạc đầy"
        case "charging": "Đang sạc"
        case "discharging": "Đang dùng pin"
        default: s ?? ""
        }
    }

    private func networkCard(_ s: StatusSnapshot) -> some View {
        Card(title: "Mạng", icon: "network") {
            let nets = (s.network ?? []).filter { $0.ip?.isEmpty == false }
            if nets.isEmpty {
                Text("Không có kết nối").foregroundStyle(.secondary)
            }
            ForEach(nets) { n in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.name).font(.callout.weight(.medium))
                        Text(n.ip ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(String(format: "%.2f MB/s", n.rx_rate_mbs ?? 0), systemImage: "arrow.down")
                        Label(String(format: "%.2f MB/s", n.tx_rate_mbs ?? 0), systemImage: "arrow.up")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func processesCard(_ s: StatusSnapshot) -> some View {
        Card(title: "Tiến trình tốn tài nguyên nhất", icon: "list.number") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Tên"); Text("PID"); Text("CPU"); Text("Bộ nhớ")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(s.top_processes ?? []) { p in
                    GridRow {
                        Text(p.name ?? p.command ?? "?").lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(p.pid)).foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", p.cpu ?? 0))
                        Text(p.memory_bytes.map { Fmt.bytes($0) } ?? "—")
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
    }
}

struct HealthHeader: View {
    let snapshot: StatusSnapshot

    var body: some View {
        let score = snapshot.health_score ?? 0
        let color: Color = score >= 80 ? .green : score >= 60 ? .orange : .red
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(score) / 100)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)").font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .frame(width: 66, height: 66)
            .animation(.easeOut, value: score)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sức khoẻ hệ thống: \(snapshot.health_score_msg ?? "—")").font(.headline)
                Text([snapshot.host, snapshot.uptime.map { "Bật được \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
