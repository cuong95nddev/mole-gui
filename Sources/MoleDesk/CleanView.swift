import AppKit
import SwiftUI

@Observable
final class CleanModel {
    var sections: [CleanSection] = []
    var previewDate: Date?
    var scanning = false
    var log: [String] = []
    var error: String?
    var staleAfterClean = false
    private let stream = LineStream()

    var totalBytes: Int64 { sections.reduce(0) { $0 + $1.totalBytes } }
    var totalItems: Int { sections.reduce(0) { $0 + $1.items.filter { $0.coveredBy == nil }.count } }

    func loadExisting() {
        guard !scanning else { return }
        let result = CleanListParser.load()
        sections = sortSections(result.sections)
        previewDate = result.date
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        staleAfterClean = false
        error = nil
        log = []
        do {
            try stream.start(["clean", "--dry-run"], mergeStderr: true, onLine: { [weak self] line in
                let clean = line.strippingANSI.trimmingCharacters(in: .whitespaces)
                guard let self, !clean.isEmpty else { return }
                self.log.append(clean)
                if self.log.count > 400 { self.log.removeFirst(self.log.count - 400) }
            }, onExit: { [weak self] code in
                guard let self else { return }
                self.scanning = false
                if code != 0 && code != 15 { self.error = "Quét kết thúc với mã \(code). Xem nhật ký bên dưới." }
                let result = CleanListParser.load()
                self.sections = self.sortSections(result.sections)
                self.previewDate = result.date
            })
        } catch {
            scanning = false
            self.error = error.localizedDescription
        }
    }

    func cancel() {
        stream.stop()
        scanning = false
    }

    private func sortSections(_ s: [CleanSection]) -> [CleanSection] {
        s.map { sec in
            var sec = sec
            sec.items.sort { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
            return sec
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }
}

struct CleanView: View {
    @Environment(AppState.self) private var app
    private var model: CleanModel { app.clean }
    @State private var expanded: Set<String> = []
    @State private var askFDA = false
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {

            if let error = model.error { ErrorBanner(message: error) }

            if model.scanning {
                scanningView
            } else if model.sections.isEmpty {
                emptyView
            } else {
                resultList
            }
        }
        .paneHeader("Dọn dẹp", subtitle: subtitle) {
            Button {
                app.runInTerminal("Danh sách bảo vệ", ["clean", "--whitelist"])
            } label: {
                Label("Bảo vệ…", systemImage: "lock")
            }
            .help("Chọn các đường dẫn Mole không bao giờ dọn (mo clean --whitelist)")

            if model.scanning {
                Button("Dừng quét") { model.cancel() }
            } else {
                Button {
                    if app.hasFullDiskAccess { model.scan() } else { askFDA = true }
                } label: {
                    Label("Quét", systemImage: "magnifyingglass")
                }
            }
            Button {
                app.runInTerminal(
                    "Dọn dẹp",
                    ["clean"],
                    note: "Mole sẽ hỏi mật khẩu nếu cần dọn cache hệ thống. Bấm Space trong terminal để bỏ qua phần đó.",
                    onFinish: {
                        model.sections = []
                        model.staleAfterClean = true
                    })
            } label: {
                Label("Dọn ngay", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.scanning)
        }
        .onAppear {
            model.loadExisting()
            if expanded.isEmpty, let first = model.sections.first { expanded.insert(first.id) }
        }
        .onChange(of: model.sections.first?.id) { _, id in
            if let id, expanded.isEmpty { expanded.insert(id) }
        }
        .confirmationDialog("Chưa cấp Full Disk Access", isPresented: $askFDA) {
            Button("Mở Cài đặt") { AppState.openFullDiskAccessSettings() }
            Button("Vẫn quét") { model.scan() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không có quyền này, macOS sẽ hỏi \"truy cập dữ liệu của app khác\" nhiều lần trong lúc quét. Nên cấp quyền cho MoleDesk trước.")
        }
    }

    private var subtitle: String {
        if model.scanning { return "Đang quét, chưa xoá gì cả…" }
        guard !model.sections.isEmpty else {
            return "Xem trước rồi mới dọn: cache, log, file tạm và phần sót lại của app đã gỡ."
        }
        var s = "Có thể giải phóng khoảng \(Fmt.bytes(model.totalBytes)) · \(model.totalItems) mục"
        if let d = model.previewDate {
            s += " · quét lúc \(Fmt.date(d))"
        }
        return s
    }

    private var scanningView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(model.log.last ?? "Đang bắt đầu…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
            logView.frame(maxHeight: 260).padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(model.staleAfterClean ? "Đã dọn xong" : "Chưa có kết quả quét",
                  systemImage: model.staleAfterClean ? "checkmark.seal" : "sparkle.magnifyingglass")
        } description: {
            Text(model.staleAfterClean
                 ? "Bấm Quét để xem còn gì có thể dọn."
                 : "Bấm Quét để xem trước những gì Mole sẽ dọn. Bước này không xoá gì.")
        } actions: {
            Button("Quét") { if app.hasFullDiskAccess { model.scan() } else { askFDA = true } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        let maxBytes = max(1, model.sections.first?.totalBytes ?? 1)
        return List {
            ForEach(model.sections) { section in
                DisclosureGroup(isExpanded: binding(for: section.id)) {
                    ForEach(section.items) { item in
                        CleanItemRow(item: item)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(section.name).font(.body.weight(.medium))
                        Text("\(section.items.count) mục").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        SizeBar(fraction: Double(section.totalBytes) / Double(maxBytes)).frame(width: 120)
                        Text(section.totalBytes == 0 && section.items.contains { $0.bytes == nil } ? "Chưa rõ" : Fmt.bytes(section.totalBytes))
                            .font(.callout.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }

            if !model.log.isEmpty {
                Section {
                    DisclosureGroup("Nhật ký lần quét gần nhất", isExpanded: $showLog) { logView.frame(height: 240) }
                }
            }
        }
        .listStyle(.inset)
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { i, line in
                        Text(line).id(i)
                    }
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: model.log.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }
}

struct CleanItemRow: View {
    let item: CleanItem

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: Finder.icon(item.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.path.replacingOccurrences(of: Mole.home, with: "~"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let parent = item.coveredBy {
                    Text("Đã tính trong \(parent.replacingOccurrences(of: Mole.home, with: "~"))")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if item.itemCount > 1 {
                Text("\(item.itemCount) mục").font(.caption).foregroundStyle(.secondary)
            }
            Text(item.bytes.map { Fmt.bytes($0) } ?? "?")
                .font(.callout.monospacedDigit())
                .foregroundStyle(item.coveredBy == nil ? .primary : .secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .contextMenu {
            Button("Hiện trong Finder") { Finder.reveal(item.path) }
            Button("Sao chép đường dẫn") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
        }
    }
}
