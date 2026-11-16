import AppKit
import SwiftUI

@main
struct MoleDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        // A single main window, so the menu bar panel can bring it back instead of opening another.
        Window("MoleDesk", id: MainWindow.id) {
            ContentView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(state)
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the main window keeps MoleDesk in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum MainWindow {
    static let id = "main"
}

enum Pane: String, CaseIterable, Identifiable {
    case status, clean, uninstall, analyze, tools, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Tổng quan"
        case .clean: "Dọn dẹp"
        case .uninstall: "Gỡ ứng dụng"
        case .analyze: "Dung lượng ổ đĩa"
        case .tools: "Công cụ khác"
        case .history: "Lịch sử"
        }
    }

    var icon: String {
        switch self {
        case .status: "gauge.with.dots.needle.67percent"
        case .clean: "sparkles"
        case .uninstall: "trash.square"
        case .analyze: "chart.pie"
        case .tools: "wrench.and.screwdriver"
        case .history: "clock.arrow.circlepath"
        }
    }
}

@Observable
final class AppState {
    /// `open MoleDesk.app --args -pane clean` opens a given pane (handy for testing).
    var pane: Pane? = Pane(rawValue: UserDefaults.standard.string(forKey: "pane") ?? "") ?? .status
    var terminalJob: TerminalJob?
    // Pane models live here so switching panes keeps their data.
    let clean = CleanModel()
    let uninstall = UninstallModel()
    let analyze = AnalyzeModel()
    let history = HistoryModel()
    let status = StatusModel()
    var hasFullDiskAccess = AppState.checkFullDiskAccess()
    var hasMole = AppState.moleInstalled()
    var brewPath = Mole.brewPath
    var hasBrew: Bool { brewPath != nil }
    var fdaSkipped = UserDefaults.standard.bool(forKey: "fdaSkipped")

    /// Onboarding stays up until Mole is installed and Full Disk Access is granted or skipped.
    var needsOnboarding: Bool { !hasMole || (!hasFullDiskAccess && !fdaSkipped) }

    func refreshSetup() {
        let mole = Self.moleInstalled(), brew = Mole.brewPath, fda = Self.checkFullDiskAccess()
        if mole != hasMole { hasMole = mole }
        if brew != brewPath { brewPath = brew }
        if fda != hasFullDiskAccess { hasFullDiskAccess = fda }
    }

    func skipFullDiskAccess() {
        fdaSkipped = true
        UserDefaults.standard.set(true, forKey: "fdaSkipped")
    }

    /// `--args -simulateMissingMole YES` shows the install step (for testing).
    private static func moleInstalled() -> Bool {
        Mole.path != nil && !UserDefaults.standard.bool(forKey: "simulateMissingMole")
    }

    /// Full Disk Access usually only applies to a freshly started process.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func runInTerminal(_ title: String, _ args: [String], note: String? = nil, onFinish: (() -> Void)? = nil) {
        terminalJob = TerminalJob(title: title, args: args, note: note, onFinish: onFinish)
    }

    /// Reading the system TCC database only succeeds with Full Disk Access, and never triggers a prompt.
    static func checkFullDiskAccess() -> Bool {
        // `--args -simulateNoFDA YES` shows the permission step (for testing).
        if UserDefaults.standard.bool(forKey: "simulateNoFDA") { return false }
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: probe) else { return false }
        try? handle.close()
        return true
    }


    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Group {
            if UserDefaults.standard.bool(forKey: "previewMenuBar") {
                // `--args -previewMenuBar YES` shows the menu bar panel in the window (for screenshots).
                MenuBarPanel().fixedSize()
            } else if state.needsOnboarding {
                OnboardingView()
            } else {
                mainView
            }
        }
        .sheet(item: $state.terminalJob) { job in
            TerminalSheet(job: job)
        }
        .onAppear {
            // `--args -terminal "history"` opens a terminal job at launch (for testing).
            if let cmd = UserDefaults.standard.string(forKey: "terminal"), !cmd.isEmpty {
                state.runInTerminal("Thử terminal", cmd.split(separator: " ").map(String.init))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshSetup()
        }
    }

    private var mainView: some View {
        @Bindable var state = state
        return NavigationSplitView {
            List(Pane.allCases, selection: $state.pane) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                fdaBanner
                switch state.pane ?? .status {
                case .status: StatusView()
                case .clean: CleanView()
                case .uninstall: UninstallView()
                case .analyze: AnalyzeView()
                case .tools: ToolsView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private var fdaBanner: some View {
        if !state.hasFullDiskAccess {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                Text("Chưa cấp Full Disk Access: Mole quét không đủ và macOS sẽ hỏi quyền từng app.")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Mở Cài đặt") { AppState.openFullDiskAccessSettings() }
                    .controlSize(.small)
                Button("Khởi động lại") { AppState.relaunch() }
                    .controlSize(.small)
                    .help("Full Disk Access thường chỉ có hiệu lực sau khi mở lại app")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.1))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
