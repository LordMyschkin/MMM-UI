import SwiftUI

private enum Palette {
    static let background = Color(hex: 0x10151D)
    static let panel = Color(hex: 0x1A222E)
    static let now = Color(hex: 0x233347)
    static let row = Color(hex: 0x212C3A)
    static let border = Color(hex: 0x303B49)
    static let text = Color(hex: 0xEEF2F5)
    static let muted = Color(hex: 0x99A8B6)
    static let accent = Color(hex: 0xB8F36B)
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

private struct Panel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}

private struct ActionButton: View {
    let title: String
    var accent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 11, weight: .medium)) }
            .buttonStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(accent ? Color(hex: 0x172316) : Palette.text)
            .background(accent ? Palette.accent : Color(hex: 0x263443), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent ? Palette.accent : Color(hex: 0x3A4A59)))
    }
}

struct MainView: View {
    @StateObject private var store = PlayerStore.shared

    var body: some View {
        VStack(spacing: 8) {
            header
            nowPlaying
            HStack(spacing: 8) {
                Panel { mainPanel.padding(.horizontal, 9).padding(.vertical, 6) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Panel { sidebar.padding(12) }
                    .frame(width: 230)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Text(store.message)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
        .onAppear { store.start(); store.seekDraft = store.status.elapsed; store.volumeDraft = Double(max(0, store.status.volume)) }
        .onChange(of: store.status.elapsed) { _, value in if !store.seeking { store.seekDraft = value } }
        .onChange(of: store.status.volume) { _, value in if !store.adjustingVolume { store.volumeDraft = Double(max(0, value)) } }
        .sheet(isPresented: $store.showAbout) { AboutView(store: store) }
        .sheet(isPresented: $store.showSettings) { settingsPopup }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Palette.accent).frame(width: 31, height: 31)
                Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(Color(hex: 0x172316))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("MMM-UI").font(.system(size: 19, weight: .bold))
                Text(store.isLocal ? "Local music player + library shuffle" : "MPD desktop player + library shuffle")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer()
            ActionButton(title: "ⓘ") { store.showAboutDialog() }
            Text(store.connectionText)
                .font(.system(size: 11)).foregroundStyle(Palette.accent)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Color(hex: 0x202D39), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("●  NOW PLAYING").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                Spacer()
                if store.status.bitrate > 0 && store.status.state != "stop" {
                    Text("\(store.status.bitrate) kbit/s")
                        .font(.system(size: 10)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: 0x334A3E), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.currentSong?.displayTitle ?? "No track selected")
                        .font(.system(size: 21, weight: .bold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color(hex: 0xC1CED6)).lineLimit(1)
                    if let composer = store.currentSong?.composer, !composer.isEmpty {
                        Text("Composed by \(composer)").font(.system(size: 11)).foregroundStyle(Palette.accent).lineLimit(1)
                    }
                    if store.settings.showFilePath, let file = store.currentSong?.file {
                        Text(file).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    playerButton("backward.end.fill", help: "Previous track") { store.previous() }
                    playerButton("stop.fill", help: "Stop") { store.stopPlayback() }
                    playerButton(store.status.state == "play" ? "pause.fill" : "play.fill", accent: true,
                                 help: "Play or pause") { store.playPause() }
                    playerButton("forward.end.fill", help: "Next track") { store.next() }
                }
            }
            HStack(spacing: 8) {
                Text(clock(store.seeking ? store.seekDraft : store.status.elapsed)).frame(width: 34, alignment: .leading)
                Slider(value: $store.seekDraft, in: 0...max(1, store.status.duration)) { editing in
                    store.seeking = editing
                    if !editing { store.seek(store.seekDraft) }
                }
                .tint(Palette.accent)
                .frame(height: 24)
                Text(clock(store.status.duration)).frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 2)
        .background(Palette.now, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3D5146), lineWidth: 1))
    }

    private var subtitle: String {
        guard let song = store.currentSong else { return "Choose music from Queue, Library or Search" }
        return [song.artist, song.album].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    private func playerButton(_ symbol: String, accent: Bool = false, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                .frame(width: accent ? 41 : 37, height: accent ? 37 : 35)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent ? Color(hex: 0x172316) : Palette.text)
        .background(accent ? Palette.accent : Color(hex: 0x263443), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent ? Palette.accent : Color(hex: 0x3A4A59)))
        .help(help)
    }

    @ViewBuilder private var mainPanel: some View {
        switch store.page {
        case .queue: queuePage
        case .library: libraryPage
        case .search: searchPage
        }
    }

    private var settingsPopup: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Settings · \(store.settings.source.rawValue)")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                ActionButton(title: "Close") { store.showSettings = false }
            }
            settingsPage
        }
        .padding(20)
        .frame(width: 680, height: 540)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
    }

    private var queuePage: some View {
        VStack(spacing: 5) {
            HStack {
                Text("Queue · \(store.queue.count) tracks").font(.system(size: 17, weight: .bold))
                Spacer()
                ActionButton(title: "Clear queue") { store.clearQueue() }
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.queue, id: \.id) { song in QueueRow(song: song, store: store) }
                }
            }
        }
    }

    private var libraryPage: some View {
        VStack(spacing: 5) {
            HStack {
                if !store.browserPath.isEmpty { ActionButton(title: "← Back") { store.browseBack() } }
                Text(store.browserPath.isEmpty
                     ? (store.isLocal ? (store.settings.musicFolder as NSString).lastPathComponent : "Library")
                     : store.browserPath)
                    .font(.system(size: 16, weight: .bold)).lineLimit(1)
                Spacer()
                if store.isLocal {
                    ActionButton(title: "Add folder") {
                        store.addFolder(store.browserPath.isEmpty ? store.settings.musicFolder : store.browserPath)
                    }
                }
                ActionButton(title: "Refresh") { Task { await store.browse(store.browserPath) } }
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.entries.filter { $0.kind == "directory" }, id: \.path) { entry in
                        HStack {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(Palette.accent)
                                Text(entry.name).lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { Task { await store.browse(entry.path) } }
                            if store.isLocal {
                                ActionButton(title: "Next") { store.addFolder(entry.path, afterCurrent: true) }
                                ActionButton(title: "Add") { store.addFolder(entry.path) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(7)
                        .background(Palette.row, in: RoundedRectangle(cornerRadius: 7))
                    }
                    ForEach(store.entries.filter { $0.kind == "playlist" }, id: \.path) { entry in
                        HStack {
                            Image(systemName: "music.note.list").foregroundStyle(Palette.accent)
                            Text(entry.name).lineLimit(1)
                            Spacer()
                            ActionButton(title: "Load") { store.loadPlaylist(entry.path) }
                        }
                        .padding(5).background(Palette.row, in: RoundedRectangle(cornerRadius: 7))
                    }
                    ForEach(store.entries.compactMap(\.song), id: \.file) { song in
                        SongResultRow(song: song, store: store, showPlay: false)
                    }
                }
            }
        }
    }

    private var searchPage: some View {
        VStack(spacing: 7) {
            HStack {
                TextField("Search title, artist, album…", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.search() }
                ActionButton(title: "Search", accent: true) { store.search() }
            }
            Text("\(store.searchResults.count) results · Next queues behind the current track")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.searchResults, id: \.file) { song in
                        SongResultRow(song: song, store: store, showPlay: true)
                    }
                }
            }
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.isLocal {
                    Text("Local music folder").font(.system(size: 18, weight: .bold))
                    Text(store.settings.musicFolder).foregroundStyle(Palette.muted).textSelection(.enabled)
                    HStack {
                        ActionButton(title: "Choose folder…") { store.chooseMusicFolder() }
                        ActionButton(title: "Rescan library") { store.rescanLocalLibrary() }
                    }
                } else {
                    Text("Connection").font(.system(size: 18, weight: .bold))
                    HStack {
                        VStack(alignment: .leading) {
                            Text("MPD host").foregroundStyle(Palette.muted)
                            TextField("127.0.0.1", text: $store.settings.host)
                        }
                        VStack(alignment: .leading) {
                            Text("Port").foregroundStyle(Palette.muted)
                            TextField("6600", value: $store.settings.port, format: .number)
                                .frame(width: 75)
                        }
                    }
                    Text("MPD password (kept only for this session)").foregroundStyle(Palette.muted)
                    SecureField("Password", text: $store.password)
                }
                Text("Library shuffle").font(.system(size: 18, weight: .bold)).padding(.top, 5)
                Toggle("Fill queue with random library tracks", isOn: $store.settings.autoFill)
                HStack {
                    Text("Keep at least")
                    TextField("20", value: $store.settings.fillTarget, format: .number).frame(width: 60)
                    Text("tracks in the queue (1–500)")
                }
                Text("The app keeps filling while it runs. If the queue is empty, playback starts automatically.")
                    .foregroundStyle(Palette.muted)
                Text("Display").font(.system(size: 18, weight: .bold)).padding(.top, 5)
                Toggle("Show file path below composer", isOn: $store.settings.showFilePath)
                Toggle("Show track changes by the camera for 2 seconds", isOn: $store.settings.showTrackIsland)
                if !store.isLocal {
                    Text("On exit").font(.system(size: 18, weight: .bold)).padding(.top, 5)
                    Toggle("Ask whether to pause MPD before quitting", isOn: $store.settings.askPauseOnExit)
                    Text("Closing MMM-UI stops automatic queue filling. MPD keeps playing unless you choose to pause it.")
                        .foregroundStyle(Palette.muted)
                }
                HStack {
                    ActionButton(title: store.isLocal ? "Save settings" : "Save and connect", accent: true) {
                        store.saveSettings()
                    }
                    if !store.isLocal {
                        ActionButton(title: "Update MPD database") { store.perform("update", success: "Database update started") }
                        ActionButton(title: "Check MPD library") {
                            Task {
                                do { store.message = "MPD library: \(try await MPDClient(host: store.settings.host, port: store.settings.port, password: store.password).libraryCount()) tracks" }
                                catch { store.message = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: 610, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PLAYBACK").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
            HStack {
                Text("Volume")
                Spacer()
                Text(store.status.volume < 0 ? "Unavailable" : "\(store.status.volume)%")
                    .foregroundStyle(Palette.muted)
            }
            Slider(value: $store.volumeDraft, in: 0...100) { editing in
                store.adjustingVolume = editing
                if !editing { store.volume(store.volumeDraft) }
            }.tint(Palette.accent)
            Toggle(store.isLocal ? "Random playback" : "MPD random", isOn: Binding(get: { store.status.random }, set: { store.setRandom($0) }))
            Toggle("Repeat queue", isOn: Binding(get: { store.status.repeatQueue }, set: { store.setRepeat($0) }))
            Toggle("Consume played tracks", isOn: Binding(get: { store.status.consume }, set: { store.setConsume($0) }))
            Divider().overlay(Palette.border).padding(.vertical, 4)
            Text("LIBRARY SHUFFLE").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
            Text(store.settings.autoFill ? "On · keep \(store.settings.fillTarget) tracks in the queue" : "Off · enable in Settings")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            ActionButton(title: store.isFilling ? "Filling…" : "Fill to 200 random tracks") {
                Task { await store.fill(to: 200) }
            }
            .disabled(store.isFilling)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct QueueRow: View {
    let song: Song
    @ObservedObject var store: PlayerStore

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(Palette.accent)
                    Text("\(song.position + 1)").foregroundStyle(Palette.muted)
                }.frame(width: 50, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(song.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(song.displayArtist).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(song.durationText).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.playID(song.id) }
            ActionButton(title: "Play") { store.playID(song.id) }
            ActionButton(title: "×") { store.remove(song) }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(height: 35)
        .background(store.status.songID == song.id ? Color(hex: 0x2D3A3A) : Palette.row,
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(store.dropTargetID == song.id ? Palette.accent : Color.clear, lineWidth: 2))
        .draggable(String(song.id))
        .dropDestination(for: String.self) { dragged, location in
            guard let text = dragged.first, let source = Int(text) else { return false }
            store.move(source, to: song.id, after: location.y > 17)
            return true
        } isTargeted: { store.dropTargetID = $0 ? song.id : nil }
    }
}

private struct SongResultRow: View {
    let song: Song
    @ObservedObject var store: PlayerStore
    var showPlay: Bool
    var body: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(song.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            ActionButton(title: "Next", accent: showPlay) { store.addNext(song) }
            ActionButton(title: "Add") { store.add(song) }
            if showPlay { ActionButton(title: "Play") { store.addAndPlay(song) } }
        }
        .padding(6)
        .background(Palette.row, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct AboutView: View {
    @ObservedObject var store: PlayerStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "play.square.fill").font(.system(size: 38)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading) {
                    Text("MMM-UI · Martins MacOS Music UI").font(.system(size: 23, weight: .bold))
                    Text("Version 0.2.0").foregroundStyle(Palette.accent)
                }
            }
            Text("A native Swift sibling of A-mpd, descended from the ympd web player and ashuffle. Built with OpenAI Codex.")
            Text(store.isLocal
                 ? "MMM-UI plays local audio files from your chosen folder tree, fills the queue randomly, and supports macOS media keys."
                 : "MMM-UI controls MPD directly, fills the queue from MPD's library, and supports macOS media keys.")
                .padding(12).background(Palette.row, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isLocal ? "LOCAL LIBRARY" : "MPD STATISTICS")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                if let stats = store.statistics {
                    Text("Artists: \(stats.artists.formatted())   Albums: \(stats.albums.formatted())   Songs: \(stats.songs.formatted())")
                    if store.isLocal {
                        Text("Total duration: \(clock(Double(stats.databasePlaytime)))")
                    } else {
                        Text("Play time: \(clock(Double(stats.playtime)))   Uptime: \(clock(Double(stats.uptime)))")
                        Text("Database play time: \(clock(Double(stats.databasePlaytime)))")
                        if let updated = stats.updated { Text("Database updated: \(updated.formatted())") }
                    }
                } else { Text("Loading…") }
            }
            .font(.system(size: 11)).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            Spacer()
            HStack { Spacer(); ActionButton(title: "Close", accent: true) { dismiss() } }
        }
        .padding(24)
        .frame(width: 540, height: 445)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
    }
}
