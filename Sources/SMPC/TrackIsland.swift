import AppKit
import SwiftUI

private struct TrackIslandView: View {
    let song: Song

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.69, green: 0.96, blue: 0.39))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(song.artist.isEmpty ? song.album : song.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 21)
        .padding(.top, 35)
        .padding(.bottom, 12)
        .frame(width: 380, height: 82)
        .background(.black, in: UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 22,
            bottomTrailingRadius: 22, topTrailingRadius: 0
        ))
    }
}

@MainActor final class TrackIsland {
    static let shared = TrackIsland()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(song: Song) {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let width: CGFloat = 380
        let height: CGFloat = 82
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)
        let panel = self.panel ?? NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(frame, display: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TrackIslandView(song: song))
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }
}
