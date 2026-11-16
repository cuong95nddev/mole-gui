import AppKit
import SwiftUI

/// First-run setup, shown while Mole is missing or Full Disk Access has not been granted (or skipped).
/// It re-checks every two seconds, so it moves on by itself once things are in place.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var copied = false

    private var installCommand: String { "brew install mole" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Thiết lập MoleDesk")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 10)
                Text("MoleDesk là giao diện cho Mole, công cụ dọn dẹp và tối ưu máy Mac miễn phí. Chỉ cần thiết lập một lần.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                checklist.padding(.top, 20)

                if !state.hasMole { installSection.padding(.top, 18) }
                else if !state.hasFullDiskAccess { permissionSection.padding(.top, 18) }

                Text("Màn hình này tự chuyển tiếp khi mọi thứ đã sẵn sàng.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
            }
            .frame(width: 480)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                state.refreshSetup()
            }
        }
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            SetupRow(ok: state.hasBrew, name: "Homebrew",
                     detail: "Trình quản lý gói, dùng để cài Mole",
                     okLabel: "Đã cài", missingLabel: "Chưa cài")
            Divider()
            SetupRow(ok: state.hasMole, name: "Mole",
                     detail: "Công cụ dòng lệnh mo, làm mọi việc dọn dẹp",
                     okLabel: "Đã cài", missingLabel: "Chưa cài")
            Divider()
            SetupRow(ok: state.hasFullDiskAccess, name: "Full Disk Access",
                     detail: "Để quét đủ cache, log và macOS không hỏi quyền từng app",
                     okLabel: "Đã cấp", missingLabel: "Chưa cấp")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    // MARK: Step 1: install Mole

    private var installSection: some View {
        VStack(spacing: 14) {
            if !state.hasBrew {
                Text("Cài Homebrew trước, sau đó chạy:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("$").foregroundStyle(.tertiary)
                Text(installCommand).textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCommand, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Sao chép lệnh")
            }
            .font(.body.monospaced())
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            HStack(spacing: 10) {
                if let brew = state.brewPath {
                    Button {
                        state.terminalJob = TerminalJob(
                            title: "Cài Mole", args: ["install", "mole"], executable: brew,
                            note: "Homebrew đang tải và cài Mole. Xong thì đóng cửa sổ này.",
                            onFinish: { state.refreshSetup() })
                    } label: {
                        Label("Cài Mole", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                    } label: {
                        Label("Tải Homebrew", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    state.refreshSetup()
                } label: {
                    Label("Kiểm tra lại", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.large)

            Link("Cách cài Mole khác", destination: URL(string: "https://github.com/tw93/Mole#installation")!)
                .font(.callout)
        }
    }

    // MARK: Step 2: Full Disk Access

    private var permissionSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Bấm **Mở Cài đặt** để tới mục Full Disk Access.")
                step(2, "Bật **MoleDesk**. Không thấy trong danh sách thì bấm **+** rồi chọn app (hoặc kéo app từ Finder vào).")
                step(3, "Quay lại đây. Nếu vẫn chưa nhận, bấm **Khởi động lại**.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button {
                    AppState.openFullDiskAccessSettings()
                } label: {
                    Label("Mở Cài đặt", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Finder.reveal(Bundle.main.bundlePath)
                } label: {
                    Label("Hiện app trong Finder", systemImage: "folder")
                }
                Button {
                    AppState.relaunch()
                } label: {
                    Label("Khởi động lại", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.large)

            Button("Bỏ qua, làm sau") { state.skipFullDiskAccess() }
                .buttonStyle(.link)
                .font(.callout)
                .help("Vẫn dùng được, nhưng quét không đủ và macOS sẽ hỏi quyền nhiều lần.")
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                .foregroundStyle(Color.accentColor)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One checklist line: status mark, name, description, state label.
struct SetupRow: View {
    let ok: Bool
    let name: String
    let detail: String
    let okLabel: String
    let missingLabel: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if ok {
                    Circle().fill(.green.opacity(0.18))
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.green)
                } else {
                    Circle().strokeBorder(.tertiary, lineWidth: 1.4)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ok ? okLabel : missingLabel)
                .font(.callout)
                .foregroundStyle(ok ? .green : .orange)
        }
        .padding(.vertical, 10)
        .animation(.easeOut, value: ok)
    }
}
