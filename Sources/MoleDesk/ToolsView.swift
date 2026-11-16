import SwiftUI

struct ToolSpec: Identifiable {
    var id: String { command.joined(separator: " ") }
    var title: String
    var icon: String
    var detail: String
    var command: [String]
    var previewArgs: [String]?
    var extra: (label: String, args: [String])?
    var note: String?
}

struct ToolsView: View {
    @Environment(AppState.self) private var app

    private let tools: [ToolSpec] = [
        ToolSpec(title: "Tối ưu hệ thống", icon: "bolt.horizontal.circle",
                 detail: "Làm mới cache và các dịch vụ hệ thống, sửa các lỗi bảo trì an toàn.",
                 command: ["optimize"], previewArgs: ["optimize", "--dry-run"],
                 extra: ("Mục bảo vệ…", ["optimize", "--whitelist"]),
                 note: "Một số tác vụ cần mật khẩu quản trị."),
        ToolSpec(title: "Dọn project cũ", icon: "folder.badge.minus",
                 detail: "Xoá thư mục build của các project lâu không đụng tới: node_modules, target, .build, DerivedData…",
                 command: ["purge"], previewArgs: ["purge", "--dry-run"],
                 extra: ("Thư mục quét…", ["purge", "--paths"]),
                 note: "Dùng phím mũi tên và Space để chọn, Enter để xác nhận."),
        ToolSpec(title: "File cài đặt", icon: "shippingbox",
                 detail: "Tìm và xoá các file .dmg, .pkg, .iso, .xip, .zip còn sót trong máy.",
                 command: ["installer"], previewArgs: ["installer", "--dry-run"],
                 note: "Dùng phím mũi tên và Space để chọn, Enter để xác nhận."),
        ToolSpec(title: "Bỏ mã Intel", icon: "scissors",
                 detail: "Bỏ phần mã Intel khỏi các app universal để tiết kiệm dung lượng trên máy Apple Silicon.",
                 command: ["slim"], previewArgs: ["slim", "--dry-run"]),
        ToolSpec(title: "Touch ID cho sudo", icon: "touchid",
                 detail: "Dùng Touch ID thay cho mật khẩu khi chạy lệnh sudo trong terminal.",
                 command: ["touchid"]),
        ToolSpec(title: "Cập nhật Mole", icon: "arrow.down.circle",
                 detail: "Cập nhật Mole CLI lên phiên bản mới nhất.",
                 command: ["update"]),
    ]

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(tools) { tool in
                        Card(title: tool.title, icon: tool.icon) {
                            Text(tool.detail)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                            HStack {
                                if let extra = tool.extra {
                                    Button(extra.label) { app.runInTerminal(tool.title, extra.args) }
                                }
                                Spacer()
                                if let preview = tool.previewArgs {
                                    Button("Xem trước") {
                                        app.runInTerminal("\(tool.title) (xem trước)", preview, note: "Chỉ xem trước, không thay đổi gì.")
                                    }
                                }
                                Button("Chạy") { app.runInTerminal(tool.title, tool.command, note: tool.note) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .paneHeader("Công cụ khác", subtitle: "Mỗi công cụ chạy trong terminal để bạn xem và xác nhận từng bước.")
    }
}

@Observable
final class HistoryModel {
    var sessions: [HistoryResult.Session] = []
    var loading = false
    var error: String?

    @MainActor
    func load() async {
        loading = true
        defer { loading = false }
        do {
            sessions = try await Mole.runJSON(HistoryResult.self, ["history", "--json"]).sessions ?? []
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var app
    private var model: HistoryModel { app.history }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error { ErrorBanner(message: error) }

            Table(model.sessions) {
                TableColumn("Lệnh") { s in
                    Label(commandLabel(s.command), systemImage: s.command.contains("dry-run") ? "eye" : "play.circle")
                }
                .width(min: 160, ideal: 200)
                TableColumn("Bắt đầu") { s in Text(s.started_at ?? "—").monospacedDigit() }
                    .width(150)
                TableColumn("Số mục") { s in Text("\(s.items ?? 0)").monospacedDigit() }
                    .width(60)
                TableColumn("Giải phóng") { s in Text(s.size ?? "—").monospacedDigit() }
                    .width(90)
                TableColumn("Kết quả") { s in Text(actionsSummary(s)).foregroundStyle(.secondary) }
            }
            .overlay {
                if model.loading && model.sessions.isEmpty { ProgressView() }
                else if !model.loading && model.sessions.isEmpty && model.error == nil {
                    ContentUnavailableView("Chưa có lịch sử", systemImage: "clock")
                }
            }
        }
        .paneHeader("Lịch sử", subtitle: "Các lần chạy Mole gần đây.") {
            Button {
                Finder.reveal("\(Mole.home)/Library/Logs/mole/operations.log")
            } label: {
                Label("Mở thư mục log", systemImage: "doc.text.magnifyingglass")
            }
            Button { Task { await model.load() } } label: { Label("Tải lại", systemImage: "arrow.clockwise") }
        }
        .task { if model.sessions.isEmpty { await model.load() } }
    }

    private func commandLabel(_ c: String) -> String {
        let dry = c.hasSuffix("-dry-run")
        let base = dry ? String(c.dropLast(8)) : c
        let names = ["clean": "Dọn dẹp", "uninstall": "Gỡ ứng dụng", "optimize": "Tối ưu",
                     "purge": "Dọn project", "installer": "File cài đặt", "slim": "Bỏ mã Intel"]
        return (names[base] ?? base) + (dry ? " (xem trước)" : "")
    }

    private func actionsSummary(_ s: HistoryResult.Session) -> String {
        guard let a = s.actions else { return "" }
        var parts: [String] = []
        if let n = a.removed, n > 0 { parts.append("đã xoá \(n)") }
        if let n = a.trashed, n > 0 { parts.append("vào Thùng rác \(n)") }
        if let n = a.skipped, n > 0 { parts.append("bỏ qua \(n)") }
        if let n = a.failed, n > 0 { parts.append("lỗi \(n)") }
        return parts.isEmpty ? "không có thay đổi" : parts.joined(separator: " · ")
    }
}
