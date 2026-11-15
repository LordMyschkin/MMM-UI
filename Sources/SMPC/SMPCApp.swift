import AppKit
import SwiftUI

final class SMPCDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = PlayerStore.shared
        guard store.settings.source == .mpd && store.settings.askPauseOnExit else {
            store.stop()
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Pause MPD before quitting?"
        alert.informativeText = "MMM-UI will stop filling the queue. MPD can keep playing the current playlist."
        alert.addButton(withTitle: "Quit without pausing")
        alert.addButton(withTitle: "Pause MPD and quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.stop()
            return .terminateNow
        case .alertSecondButtonReturn:
            Task { @MainActor in
                await store.pauseBeforeExit()
                store.stop()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }
}

@main struct SMPCApp: App {
    @NSApplicationDelegateAdaptor(SMPCDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("MMM-UI") {
            MainView()
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Martins MacOS Music UI") { PlayerStore.shared.showAboutDialog() }
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Local Files…") { PlayerStore.shared.selectLocalFiles() }
                Button("MPD Client") { PlayerStore.shared.selectMPDClient() }
                Button("Choose Music Folder…") { PlayerStore.shared.chooseMusicFolder() }
                Divider()
                Button("Settings…") { PlayerStore.shared.showSettings = true }
                    .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Navigate") {
                ForEach(Page.allCases, id: \.self) { page in
                    Button(page.rawValue) { PlayerStore.shared.page = page }
                }
            }
            CommandMenu("Playback") {
                Button("Previous Track") { PlayerStore.shared.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("Play/Pause") { PlayerStore.shared.playPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { PlayerStore.shared.stopPlayback() }
                Button("Next Track") { PlayerStore.shared.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
            }
        }
    }
}
