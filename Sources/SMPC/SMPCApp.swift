import AppKit
import SwiftUI

final class SMPCDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { cleanMenus() }
    func applicationDidBecomeActive(_ notification: Notification) { cleanMenus() }

    private func cleanMenus() {
        DispatchQueue.main.async {
            guard let menu = NSApp.mainMenu else { return }
            for title in ["Edit", "Format"] {
                if let item = menu.items.first(where: { $0.title == title }) { menu.removeItem(item) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !PlayerStore.shared.menuBarMode
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if PlayerStore.shared.menuBarMode { MenuBarController.shared.restoreWindow() }
        return true
    }

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
        Window("MMM-UI", id: "main") {
            MainView()
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Martins MacOS Music UI") { PlayerStore.shared.showAboutDialog() }
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Local Files…") { PlayerStore.shared.selectLocalFiles() }
                Button("MPD Client") { PlayerStore.shared.selectMPDClient() }
                Button("Choose Music Folder…") { PlayerStore.shared.chooseMusicFolder() }
                Divider()
                Button("Move to Menu Bar") { PlayerStore.shared.moveToMenuBar() }
                Button("Show Main Window") { MenuBarController.shared.restoreWindow() }
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

@MainActor final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var item: NSStatusItem?
    private var mainWindow: NSWindow?

    func show(window: NSWindow?) {
        guard item == nil else { return }
        mainWindow = window
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "♫"
        item.button?.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        item.button?.toolTip = "MMM-UI · Show main window"
        item.button?.target = self
        item.button?.action = #selector(showWindow)
        item.isVisible = true
        self.item = item
    }

    @objc private func showWindow() { restoreWindow() }

    func restoreWindow() {
        guard PlayerStore.shared.menuBarMode else { return }
        let window = mainWindow ?? NSApp.windows.first(where: { $0.title == "MMM-UI" })
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        DispatchQueue.main.async {
            PlayerStore.shared.menuBarMode = false
            if let item = self.item { NSStatusBar.system.removeStatusItem(item) }
            self.item = nil
            self.mainWindow = nil
        }
    }

}
