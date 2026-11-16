import AppKit
import SwiftUI

@Observable
final class AnalyzeModel {
    /// nil path = machine-wide overview.
    var stack: [String?] = []
    var result: AnalyzeResult?
    var loading = false
    var error: String?
    private var cache: [String: AnalyzeResult] = [:]
    private var task: Task<Void, Never>?

    var current: String? { stack.last ?? nil }
    var started: Bool { !stack.isEmpty }

    func open(_ path: String?, push: Bool = true) {
        if push { stack.append(path) }
        load()
    }

    func reset(to path: String?) {
        stack = [path]
        load()
    }

    func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        load()
    }

    func jump(to index: Int) {
        guard index < stack.count else { return }
        stack = Array(stack.prefix(index + 1))
        load()
    }

    func reload() {
        cache[key(current)] = nil
        load()
    }

    func invalidate(_ path: String) {
        cache = cache.filter { !path.hasPrefix($0.key) && !$0.key.hasPrefix(path) }
    }

    func load() {
        guard started else { return }
        task?.cancel()
        let target = current
        if let cached = cache[key(target)] {
            result = cached
            loading = false
            error = nil
            return
        }
        loading = true
        error = nil
        task = Task { @MainActor in
            do {
                var args = ["analyze", "--json"]
                if let target { args.append(target) }
                let r = try await Mole.runJSON(AnalyzeResult.self, args)
                guard !Task.isCancelled else { return }
                cache[key(target)] = r
                result = r
                loading = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    func removeLocally(_ path: String) {
        guard var r = result else { return }
        let size = r.entries?.first { $0.path == path }?.size ?? 0
        r.entries?.removeAll { $0.path == path }
        r.large_files?.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        r.total_size = (r.total_size ?? 0) - size
        result = r
        invalidate(path)
        cache[key(current)] = r
    }

    private func key(_ p: String?) -> String { p ?? "<overview>" }
}

struct AnalyzeView: View {
    @Environment(AppState.self) private var app
    private var model: AnalyzeModel { app.analyze }
    @State private var selection: AnalyzeResult.Entry.ID?
    @State private var pendingTrash: AnalyzeResult.Entry?
    @State private var trashError: String?

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            if let error = model.error { ErrorBanner(message: error) }
            if let trashError { ErrorBanner(message: trashError) }

            if model.result == nil && !model.loading && model.error == nil {
                startView
            } else {
                HStack(spacing: 0) {
                    entriesList.frame(minWidth: 0, maxWidth: .infinity)
                    Divider()
                    largeFiles.frame(width: 290)
                }
                .overlay { loadingOverlay }
            }
        }
        .paneHeader("Dung lượng ổ đĩa", subtitle: subtitle) {
            Button { model.reset(to: Mole.home) } label: { Label("Thư mục nhà", systemImage: "house") }
            Button { model.reset(to: nil) } label: { Label("Toàn máy", systemImage: "desktopcomputer") }
                .help("Tổng quan toàn máy (mo analyze). Lần đầu có thể mất vài phút.")
            Button { choose() } label: { Label("Chọn thư mục…", systemImage: "folder") }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.back() } label: { Label("Quay lại", systemImage: "chevron.left") }
                    .disabled(model.stack.count < 2)
                    .keyboardShortcut("[", modifiers: .command)
            }
            ToolbarItem {
                Button { model.reload() } label: { Label("Quét lại", systemImage: "arrow.clockwise") }
            }
        }
        .onAppear {
            // `--args -analyze PATH` starts on a folder (for testing).
            if !model.started, let p = UserDefaults.standard.string(forKey: "analyze") { model.reset(to: p) }
        }
        .confirmationDialog(
            "Chuyển \"\(pendingTrash?.name ?? "")\" vào Thùng rác?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { entry in
            Button("Chuyển vào Thùng rác (\(Fmt.bytes(entry.size ?? 0)))", role: .destructive) { trash(entry) }
            Button("Huỷ", role: .cancel) {}
        } message: { entry in
            Text(entry.path)
        }
    }

    @ViewBuilder private var loadingOverlay: some View {
        if model.loading {
            ProgressView(model.current == nil ? "Đang quét toàn máy, có thể mất vài phút…" : "Đang quét…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var startView: some View {
        ContentUnavailableView {
            Label("Chọn nơi cần phân tích", systemImage: "chart.pie")
        } description: {
            Text("Mole sẽ đo dung lượng từng thư mục con và tìm các tệp lớn nhất. Việc quét chỉ đọc, không xoá gì.")
        } actions: {
            HStack {
                Button("Thư mục nhà") { model.reset(to: Mole.home) }
                Button("Toàn máy") { model.reset(to: nil) }
                Button("Chọn…") { choose() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitle: String {
        guard let r = model.result else { return "Xem thư mục nào đang chiếm nhiều chỗ nhất." }
        var parts: [String] = []
        if let s = r.total_size { parts.append("Tổng \(Fmt.bytes(s))") }
        if let f = r.total_files, f > 0 { parts.append("\(f.formatted()) tệp") }
        if let st = r.scan_status, st != "complete" { parts.append("trạng thái: \(st)") }
        return parts.joined(separator: " · ")
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.stack.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(label(for: p)) { model.jump(to: i) }
                        .buttonStyle(.plain)
                        .foregroundStyle(i == model.stack.count - 1 ? .primary : .secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func label(for p: String?) -> String {
        guard let p else { return "Toàn máy" }
        if p == Mole.home { return "~" }
        return (p as NSString).lastPathComponent.isEmpty ? p : (p as NSString).lastPathComponent
    }

    private var entries: [AnalyzeResult.Entry] {
        (model.result?.entries ?? []).sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    private var entriesList: some View {
        let maxSize = Double(max(1, entries.first?.size ?? 1))
        let total = Double(max(1, model.result?.total_size ?? 1))
        return List(selection: $selection) {
            ForEach(entries) { e in
                HStack(spacing: 10) {
                    Image(nsImage: Finder.icon(e.path)).resizable().frame(width: 18, height: 18)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SizeBar(fraction: Double(e.size ?? 0) / maxSize).frame(width: 90)
                    Text(Fmt.percent(Double(e.size ?? 0) / total * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                    Text(Fmt.bytes(e.size ?? 0))
                        .font(.callout.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .opacity(e.is_dir == true ? 1 : 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .tag(e.id)
                .onTapGesture(count: 2) { if e.is_dir == true { model.open(e.path) } }
                .contextMenu { menu(for: e) }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            if let id = selection, let e = entries.first(where: { $0.id == id }), e.is_dir == true {
                model.open(e.path)
                return .handled
            }
            return .ignored
        }
    }

    private var largeFiles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tệp lớn nhất").font(.headline).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            List(model.result?.large_files ?? []) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(f.name).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.bytes(f.size ?? 0)).font(.callout.monospacedDigit())
                            .fixedSize()
                    }
                    Text((f.path as NSString).deletingLastPathComponent.replacingOccurrences(of: Mole.home, with: "~"))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help(f.path)
                .contextMenu { menu(for: f) }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder private func menu(for e: AnalyzeResult.Entry) -> some View {
        if e.is_dir == true { Button("Mở") { model.open(e.path) } }
        Button("Hiện trong Finder") { Finder.reveal(e.path) }
        Button("Sao chép đường dẫn") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(e.path, forType: .string)
        }
        Divider()
        Button("Chuyển vào Thùng rác…", role: .destructive) { pendingTrash = e }
    }

    private func trash(_ e: AnalyzeResult.Entry) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil)
            model.removeLocally(e.path)
            trashError = nil
        } catch {
            trashError = "Không chuyển được vào Thùng rác: \(error.localizedDescription)"
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Phân tích"
        if panel.runModal() == .OK, let url = panel.url {
            model.reset(to: url.path)
        }
    }
}
