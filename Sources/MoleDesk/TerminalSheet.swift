import AppKit
import SwiftTerm
import SwiftUI

/// A `mo` command that must run in a real terminal (confirmations, sudo, interactive pickers).
struct TerminalJob: Identifiable {
    let id = UUID()
    var title: String
    var args: [String]
    /// nil runs `mo`; otherwise the full path of another executable (e.g. brew).
    var executable: String? = nil
    var note: String?
    var onFinish: (() -> Void)?

    var commandLine: String {
        ([executable.map { ($0 as NSString).lastPathComponent } ?? "mo"] + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }).joined(separator: " ")
    }
}

struct TerminalSheet: View {
    let job: TerminalJob
    @Environment(\.dismiss) private var dismiss
    @State private var exitCode: Int32?
    @State private var finished = false
    @State private var controller = TerminalController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.headline)
                    Text(job.commandLine).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge
                Button(finished ? "Đóng" : "Dừng & đóng") {
                    controller.terminate()
                    dismiss()
                }
                .keyboardShortcut(finished ? .defaultAction : .cancelAction)
            }
            .padding(12)

            if let note = job.note {
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()
            MoleTerminalView(executable: job.executable, args: job.args, controller: controller) { code in
                exitCode = code
                finished = true
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 520, idealHeight: 620)
        .onDisappear {
            controller.terminate()
            job.onFinish?()
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if !finished {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Đang chạy").foregroundStyle(.secondary)
            }
        } else if exitCode == 0 || exitCode == nil {
            Label("Xong", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label("Thoát với mã \(exitCode ?? -1)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

final class TerminalController {
    weak var view: LocalProcessTerminalView?

    func terminate() {
        guard let view, view.process?.running == true else { return }
        view.terminate()
    }
}

struct MoleTerminalView: NSViewRepresentable {
    let executable: String?
    let args: [String]
    let controller: TerminalController
    let onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .textColor
        controller.view = view

        let env = Mole.environment(extra: ["TERM": "xterm-256color", "COLORTERM": "truecolor"])
            .map { "\($0.key)=\($0.value)" }

        DispatchQueue.main.async {
            guard let path = executable ?? Mole.path else {
                view.feed(text: "Không tìm thấy lệnh mo. Cài bằng: brew install mole\r\n")
                onExit(127)
                return
            }
            view.startProcess(executable: path, args: args, environment: env,
                              execName: (path as NSString).lastPathComponent)
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: (Int32?) -> Void
        init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { self.onExit(exitCode) }
        }
    }
}
