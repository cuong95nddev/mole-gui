import AppKit
import SwiftUI

/// The panel that drops down from MoleDesk's menu bar icon: a compact read of `mo status`.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    private var model: StatusModel { app.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !app.hasMole {
                notice("Chưa cài Mole. Mở MoleDesk để cài đặt.", icon: "shippingbox")
            } else if let s = model.snapshot {
                header(s)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    cpuTile(s)
                    gpuTile(s)
                    memoryTile(s)
                    diskTile(s)
                    networkTile(s)
                    powerTile(s)
                }
                if let b = s.batteries?.first { batteryTile(b, s) }
                processesTile(s)
            } else if let error = model.error {
                notice(error, icon: "exclamationmark.triangle")
            } else {
                ProgressView("Đang đọc thông số hệ thống…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            footer
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { if app.hasMole { model.acquire() } }
        .onDisappear { if app.hasMole { model.release() } }
    }

    // MARK: - Header

    private func header(_ s: StatusSnapshot) -> some View {
        let score = s.health_score ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: score >= 80 ? "sun.max.fill" : score >= 60 ? "cloud.sun.fill" : "cloud.bolt.fill")
                    .font(.title2)
                    .foregroundStyle(scoreColor(score))
                Text("\(score)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(healthText(s.health_score_msg))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .animation(.easeOut, value: score)
            FlowChips(items: chips(s))
        }
    }

    private func chips(_ s: StatusSnapshot) -> [String] {
        var out: [String] = []
        if let cpu = s.hardware?.cpu_model { out.append(cpu.replacingOccurrences(of: "Apple ", with: "")) }
        if let ram = s.hardware?.total_ram { out.append(ram.replacingOccurrences(of: ".0 GB", with: " GB")) }
        if let os = s.hardware?.os_version { out.append(os) }
        if let up = s.uptime { out.append("bật \(up)") }
        if let p = s.proxy, p.enabled == true { out.append(p.type ?? "Proxy") }
        return out
    }

    // MARK: - Tiles

    private func cpuTile(_ s: StatusSnapshot) -> some View {
        let usage = s.cpu?.usage ?? 0
        return Tile(title: "CPU", icon: "cpu", badge: temperature(s.thermal?.cpu_temp)) {
            BigValue(value: String(format: "%.0f", usage), unit: "%")
            CoreBars(values: s.cpu?.per_core ?? [])
            Caption(text: "\(activity(usage)) · tải \(String(format: "%.1f", s.cpu?.load1 ?? 0))/\(s.cpu?.logical_cpu ?? s.cpu?.core_count ?? 0)")
        }
    }

    private func gpuTile(_ s: StatusSnapshot) -> some View {
        let g = s.gpu?.first
        let usage = g?.usage ?? -1
        return Tile(title: "GPU", icon: "display", badge: temperature(s.thermal?.gpu_temp)) {
            BigValue(value: usage >= 0 ? String(format: "%.0f", usage) : "—", unit: usage >= 0 ? "%" : "")
            if usage >= 0 {
                Sparkline(values: model.gpuHistory, maxValue: 100, tint: .purple)
            } else {
                Caption(text: "Mole chưa đo được").frame(height: 22, alignment: .bottomLeading)
            }
            Caption(text: [usage >= 0 ? activity(usage) : nil, g?.core_count.map { "\($0) nhân" }]
                .compactMap { $0 }.joined(separator: " · "))
        }
    }

    private func memoryTile(_ s: StatusSnapshot) -> some View {
        let m = s.memory
        return Tile(title: "RAM", icon: "memorychip", badge: pressureText(m?.pressure)) {
            BigValue(value: String(format: "%.0f", m?.used_percent ?? 0), unit: "%")
            Sparkline(values: model.memHistory, maxValue: 100, tint: .orange)
            Caption(text: "\(Fmt.bytes(m?.used ?? 0)) / \(Fmt.bytes(m?.total ?? 0))")
        }
    }

    private func diskTile(_ s: StatusSnapshot) -> some View {
        let d = s.disks?.first { $0.mount == "/" } ?? s.disks?.first
        let free = max(0, (d?.total ?? 0) - (d?.used ?? 0))
        let pct = d?.used_percent ?? 0
        let parts = Fmt.bytes(free).split(separator: " ")
        return Tile(title: "Ổ đĩa", icon: "internaldrive", badge: d?.total.map { Fmt.bytes($0) }) {
            BigValue(value: String(parts.first ?? ""), unit: parts.count > 1 ? "\(parts[1]) trống" : "")
            Meter(value: pct / 100, height: 7)
                .frame(height: 22)
            Caption(text: "Đã dùng \(Fmt.bytes(d?.used ?? 0)) · \(Fmt.percent(pct))")
        }
    }

    private func networkTile(_ s: StatusSnapshot) -> some View {
        let rate = s.networkRate
        let active = (s.network ?? []).first { $0.ip?.isEmpty == false }
        let total = Rate.split(rate.rx + rate.tx)
        return Tile(title: "Mạng", icon: "network", badge: active.map { interfaceName($0.name) }) {
            BigValue(value: total.value, unit: total.unit)
            Sparkline(values: model.netHistory, maxValue: nil, tint: .teal)
            Caption(text: "↑ \(Rate.text(rate.tx)) · ↓ \(Rate.text(rate.rx))")
        }
    }

    /// Fans when the Mac has any, otherwise the system's power draw.
    @ViewBuilder private func powerTile(_ s: StatusSnapshot) -> some View {
        let t = s.thermal
        if let fans = t?.fan_count, fans > 0 {
            Tile(title: "Quạt", icon: "fanblades", badge: "\(fans) quạt") {
                BigValue(value: String(format: "%.0f", t?.fan_speed ?? 0), unit: "RPM")
                Spacer(minLength: 0).frame(height: 22)
                Caption(text: (t?.fan_speed ?? 0) > 0 ? "Đang quay" : "Đang nghỉ · macOS tự điều khiển")
            }
        } else {
            Tile(title: "Điện năng", icon: "bolt", badge: t?.adapter_power.flatMap { $0 > 0 ? String(format: "Sạc %.0fW", $0) : nil }) {
                BigValue(value: String(format: "%.1f", t?.system_power ?? 0), unit: "W")
                Spacer(minLength: 0).frame(height: 22)
                Caption(text: "Máy không có quạt")
            }
        }
    }

    private func batteryTile(_ b: StatusSnapshot.Battery, _ s: StatusSnapshot) -> some View {
        let devices = (s.bluetooth ?? []).filter { $0.connected == true }
        return Tile(title: "Pin", icon: batteryIcon(b), badge: b.capacity.map { "Độ chai \(Fmt.percent(100 - $0))" }) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.percent(b.percent ?? 0))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(batteryStatus(b))
                            .font(.callout).foregroundStyle(.secondary)
                        if let w = s.thermal?.adapter_power, w > 0 {
                            Text(String(format: "⚡︎%.0fW", w)).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Caption(text: [b.health.map { "Tình trạng \(healthWord($0))" },
                                   b.cycle_count.map { "\($0) lần sạc" }]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                Spacer(minLength: 4)
                ForEach(devices.prefix(3)) { d in
                    DeviceRing(name: d.name, percent: Self.percent(d.battery))
                }
            }
        }
    }

    private func processesTile(_ s: StatusSnapshot) -> some View {
        Tile(title: "Tiến trình nặng nhất", icon: "chart.bar.xaxis", badge: nil) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("")
                    Text("Bộ nhớ").gridColumnAlignment(.trailing)
                    Text("% CPU").gridColumnAlignment(.trailing)
                    Text("")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                ForEach((s.top_processes ?? []).prefix(5)) { p in
                    GridRow {
                        Text(p.name ?? p.command ?? "?")
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(p.memory_bytes.map { Fmt.bytes($0) } ?? "—")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", p.cpu ?? 0))
                            .foregroundStyle((p.cpu ?? 0) >= 50 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        ProcessMenu(pid: p.pid)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button { show(.status) } label: { Label("Mở MoleDesk", systemImage: "macwindow") }
            Button { show(.clean) } label: { Label("Dọn dẹp", systemImage: "sparkles") }
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Thoát MoleDesk")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.top, 2)
    }

    private func show(_ pane: Pane) {
        app.pane = pane
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
        // Close the panel: it is the key window right now.
        NSApp.keyWindow?.close()
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: - Text helpers

    private func scoreColor(_ score: Int) -> Color { score >= 80 ? .green : score >= 60 ? .orange : .red }

    private func healthText(_ msg: String?) -> String {
        switch msg?.lowercased() {
        case "excellent": "Rất tốt"
        case "good": "Tốt"
        case "fair": "Tạm ổn"
        case "poor": "Kém"
        case "critical": "Nguy cấp"
        default: msg ?? ""
        }
    }

    private func temperature(_ t: Double?) -> String? {
        guard let t, t > 0 else { return nil }
        return String(format: "%.0f°C", t)
    }

    private func activity(_ usage: Double) -> String {
        usage < 20 ? "rảnh" : usage < 60 ? "vừa" : "bận"
    }

    private func pressureText(_ p: String?) -> String? {
        switch p?.lowercased() {
        case "normal": "Ổn định"
        case "warn", "warning": "Căng"
        case "critical": "Quá tải"
        default: p
        }
    }

    private func interfaceName(_ name: String) -> String {
        name == "en0" ? "Wi‑Fi" : name.hasPrefix("utun") ? "VPN" : name
    }

    private func batteryIcon(_ b: StatusSnapshot.Battery) -> String {
        if b.status?.lowercased() == "charging" { return "battery.100percent.bolt" }
        switch b.percent ?? 0 {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func batteryStatus(_ b: StatusSnapshot.Battery) -> String {
        switch b.status?.lowercased() {
        case "charged": "Đã sạc đầy"
        case "charging": "Đang sạc"
        case "discharging": b.time_left.flatMap { $0 == "0:00" ? nil : "Còn \($0)" } ?? "Đang dùng pin"
        default: b.status ?? ""
        }
    }

    private func healthWord(_ h: String) -> String {
        switch h.lowercased() {
        case "good", "normal": "tốt"
        case "fair": "khá"
        case "poor", "service recommended": "cần bảo hành"
        default: h
        }
    }

    /// "85%" / "85" → 85; "" → nil.
    static func percent(_ text: String?) -> Double? {
        guard let text else { return nil }
        let digits = text.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

// MARK: - Building blocks

private struct Tile<Content: View>: View {
    let title: String
    let icon: String
    let badge: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.5)))
    }
}

private struct BigValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

private struct Caption: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}

/// Per-core CPU load, one bar per core.
private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                let f = min(1, max(0, v / 100))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green.opacity(0.35 + 0.65 * f))
                    .frame(height: max(2, 22 * f))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .animation(.easeOut(duration: 0.4), value: values)
    }
}

/// A small area chart of recent samples. `maxValue == nil` scales to the largest sample.
private struct Sparkline: View {
    let values: [Double]
    let maxValue: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let top = max(maxValue ?? (values.max() ?? 0), 0.0001)
            let n = StatusModel.historyLength
            let step = geo.size.width / CGFloat(max(1, n - 1))
            let points: [CGPoint] = values.enumerated().map { i, v in
                let x = geo.size.width - CGFloat(values.count - 1 - i) * step
                let y = geo.size.height * (1 - CGFloat(min(1, max(0, v / top))))
                return CGPoint(x: x, y: max(1, y))
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 0.5))
                }
                .stroke(.quaternary, lineWidth: 1)
                if let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(points) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 22)
    }
}

/// Battery ring for a connected Bluetooth device.
private struct DeviceRing: View {
    let name: String
    let percent: Double?

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            if let percent {
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(percent < 20 ? Color.red : .green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbol).font(.system(size: 12))
        }
        .frame(width: 34, height: 34)
        .help(percent.map { "\(name): \(Fmt.percent($0))" } ?? name)
    }

    private var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpods" }
        if n.contains("keyboard") || n.contains("bàn phím") { return "keyboard" }
        if n.contains("mouse") || n.contains("chuột") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("watch") { return "applewatch" }
        return "headphones"
    }
}

/// "…" menu for a process row. Only regular apps can be asked to quit, the same as ⌘Q.
private struct ProcessMenu: View {
    let pid: Int

    var body: some View {
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        Menu {
            if let app {
                Button("Thoát \(app.localizedName ?? "ứng dụng")") { app.terminate() }
                Button("Hiện ứng dụng") { app.activate() }
            }
            Button("Mở Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

/// Small rounded chips that wrap onto new lines.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        WrapLayout(spacing: 5) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in rows.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, maxX, y + rowHeight)
    }
}

/// Network rates: Mole reports MB/s.
enum Rate {
    static func split(_ mbs: Double) -> (value: String, unit: String) {
        let kbs = mbs * 1000
        if kbs < 1000 { return (String(format: "%.0f", kbs), "KB/s") }
        return (String(format: mbs < 10 ? "%.1f" : "%.0f", mbs), "MB/s")
    }

    static func text(_ mbs: Double) -> String {
        let s = split(mbs)
        return "\(s.value) \(s.unit)"
    }
}
