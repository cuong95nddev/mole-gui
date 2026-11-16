import SwiftUI

@Observable
final class UninstallModel {
    var apps: [InstalledApp] = []
    var loading = false
    var error: String?

    @MainActor
    func load() async {
        loading = true
        defer { loading = false }
        do {
            apps = try await Mole.runJSON([InstalledApp].self, ["uninstall", "--list"])
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct UninstallView: View {
    @Environment(AppState.self) private var app
    private var model: UninstallModel { app.uninstall }
    @State private var selection = Set<InstalledApp.ID>()
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\InstalledApp.sizeBytes, order: .reverse)]
    @State private var withData = false
    @State private var permanent = false

    private var filtered: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? model.apps : model.apps.filter {
            $0.name.lowercased().contains(q) || ($0.bundle_id ?? "").lowercased().contains(q)
        }
        return list.sorted(using: sortOrder)
    }

    private var selectedApps: [InstalledApp] { model.apps.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {

            if let error = model.error { ErrorBanner(message: error) }

            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Ứng dụng", value: \.name) { a in
                    HStack(spacing: 8) {
                        if let path = a.path {
                            Image(nsImage: Finder.icon(path)).resizable().frame(width: 22, height: 22)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(a.name)
                            if let id = a.bundle_id {
                                Text(id).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        if let path = a.path { Button("Hiện trong Finder") { Finder.reveal(path) } }
                    }
                }
                .width(min: 260, ideal: 340)
                TableColumn("Nguồn", value: \.sourceLabel) { a in
                    Text(a.sourceLabel).foregroundStyle(.secondary)
                }
                .width(90)
                TableColumn("Dung lượng", value: \.sizeBytes) { a in
                    Text(a.sizeBytes >= 0 ? Fmt.bytes(a.sizeBytes) : "—")
                        .monospacedDigit()
                        .foregroundStyle(a.sizeBytes >= 0 ? .primary : .secondary)
                }
                .width(100)
                TableColumn("Thư mục", value: \.pathLabel) { a in
                    Text(a.pathLabel).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .overlay {
                if model.loading && model.apps.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Đang liệt kê ứng dụng và tính dung lượng…")
                        Text("Lần đầu có thể mất 10–20 giây.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            actionBar
        }
        .paneHeader("Gỡ ứng dụng", subtitle: "\(model.apps.count) ứng dụng · ⌘-click để chọn nhiều")
        .searchable(text: $search, placement: .toolbar, prompt: "Tìm ứng dụng")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.load() } } label: { Label("Tải lại", systemImage: "arrow.clockwise") }
                    .disabled(model.loading)
            }
        }
        .task { if model.apps.isEmpty { await model.load() } }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Text(selectionText)
                .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Toggle("Kèm dữ liệu cá nhân", isOn: $withData)
                .help("Chọn sẵn dữ liệu cá nhân của app để xoá (--with-data). Bạn vẫn xem lại trước khi xác nhận.")
            Toggle("Xoá vĩnh viễn", isOn: $permanent)
                .help("Bỏ qua Thùng rác (--permanent). Mặc định Mole chuyển file vào Thùng rác.")
            Button("Xem trước") { run(dryRun: true) }
                .disabled(selection.isEmpty)
            Button(role: .destructive) {
                run(dryRun: false)
            } label: {
                Label(selection.count > 1 ? "Gỡ \(selection.count) app" : "Gỡ", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty)
        }
        .toggleStyle(.checkbox)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var selectionText: String {
        guard !selection.isEmpty else { return "Chưa chọn ứng dụng nào" }
        let apps = selectedApps
        let total = apps.map(\.sizeBytes).filter { $0 > 0 }.reduce(0, +)
        let names = apps.map(\.name).joined(separator: ", ")
        return total > 0 ? "\(names) · \(Fmt.bytes(total))" : names
    }

    private func run(dryRun: Bool) {
        let names = selectedApps.map(\.uninstall_name)
        guard !names.isEmpty else { return }
        var args = ["uninstall"]
        if dryRun { args.append("--dry-run") }
        if withData { args.append("--with-data") }
        if permanent && !dryRun { args.append("--permanent") }
        args += names
        app.runInTerminal(
            dryRun ? "Xem trước khi gỡ" : "Gỡ ứng dụng",
            args,
            note: dryRun ? "Chỉ xem trước, không xoá gì." : "Mole liệt kê các file sẽ xoá và chờ bạn xác nhận trong terminal.",
            onFinish: dryRun ? nil : {
                selection.removeAll()
                Task { await model.load() }
            })
    }
}

extension InstalledApp {
    var sourceLabel: String { source ?? "" }
    /// The folder holding the app, e.g. "/Applications" or "~/Applications/Chrome Apps".
    var pathLabel: String {
        guard let path else { return "" }
        return (path as NSString).deletingLastPathComponent.replacingOccurrences(of: Mole.home, with: "~")
    }
}
