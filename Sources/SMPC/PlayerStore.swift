import Foundation
import Combine
import MediaPlayer
import AppKit

enum Page: String, CaseIterable {
    case queue = "Queue", library = "Library", search = "Search"
}

@MainActor final class PlayerStore: ObservableObject {
    static let shared = PlayerStore()

    @Published var page: Page = .queue
    @Published var settings = Settings.load()
    @Published var password = ""
    @Published var status = MPDStatus([:])
    @Published var currentSong: Song?
    @Published var queue: [Song] = []
    @Published var entries: [LibraryEntry] = []
    @Published var browserPath = ""
    @Published var searchText = ""
    @Published var searchResults: [Song] = []
    @Published var connectionText = "Connecting…"
    @Published var message = "Ready"
    @Published var showAbout = false
    @Published var showSettings = false
    @Published var statistics: MPDStatistics?
    @Published var isFilling = false
    @Published var seekDraft = 0.0
    @Published var volumeDraft = 0.0
    @Published var seeking = false
    @Published var adjustingVolume = false
    @Published var dropTargetID: Int?

    private var worker: Task<Void, Never>?
    private var lastSongID = Int.min
    private var lastQueueVersion = Int.min
    private var recent: [String] = []
    private lazy var local: LocalBackend = {
        let backend = LocalBackend()
        backend.store = self
        return backend
    }()
    var isLocal: Bool { settings.source == .local }
    var localLibraryCount: Int { local.library.count }
    func rescanLocalLibrary() { local.scanLibrary() }

    private init() {
        settings.port = min(65535, max(1, settings.port))
        settings.localFillTarget = min(500, max(1, settings.localFillTarget))
        settings.mpdFillTarget = min(500, max(1, settings.mpdFillTarget))
    }

    private func client() -> MPDClient {
        MPDClient(host: settings.host, port: settings.port, password: password)
    }

    func start() {
        guard worker == nil else { return }
        MediaControls.shared.install()
        if isLocal { local.activate() }
        worker = Task {
            var cycle = 0
            while !Task.isCancelled {
                await refresh()
                if settings.autoFill && cycle % 3 == 0 { await fill(to: settings.fillTarget, autoStart: true) }
                cycle += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
        if !isLocal { Task { await browse("") } }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        if isLocal { persistLocalQueue() }
        local.deactivate()
        TrackIsland.shared.hide()
        MediaControls.shared.clear()
    }

    func refresh() async {
        if isLocal {
            connectionText = "Local Files · \(settings.musicFolder.isEmpty ? "choose folder" : (settings.musicFolder as NSString).lastPathComponent)"
            MediaControls.shared.update(song: currentSong, status: status)
            return
        }
        do {
            let mpd = client()
            let fresh = try await mpd.status()
            guard !isLocal else { return }
            status = fresh
            connectionText = "Connected · \(settings.host):\(settings.port)"
            if fresh.songID != lastSongID {
                let wasConnected = lastSongID != Int.min
                let song = try await mpd.currentSong()
                guard !isLocal else { return }
                currentSong = song
                lastSongID = fresh.songID
                if wasConnected, settings.showTrackIsland, let currentSong {
                    TrackIsland.shared.show(song: currentSong)
                }
            }
            if fresh.queueVersion != lastQueueVersion {
                let latestQueue = try await mpd.queue()
                guard !isLocal else { return }
                queue = latestQueue
                lastQueueVersion = fresh.queueVersion
            }
            MediaControls.shared.update(song: currentSong, status: fresh)
        } catch {
            guard !isLocal else { return }
            connectionText = "Disconnected"
            message = error.localizedDescription
            MediaControls.shared.clearInfo()
        }
    }

    func perform(_ command: String, success: String) {
        if isLocal {
            if executeLocal(command) { message = success }
            return
        }
        Task {
            do {
                _ = try await client().request(command)
                message = success
                await refresh()
            } catch { message = error.localizedDescription }
        }
    }

    private func executeLocal(_ command: String) -> Bool {
        let parts = command.split(separator: " ")
        guard let verb = parts.first else { return false }
        let number = parts.count > 1 ? Int(parts[1]) : nil
        switch verb {
        case "play": if status.state != "play" { local.playPause() }
        case "playid": if let number { local.play(number) }
        case "pause": local.pause(number == 1)
        case "stop": local.stop()
        case "next": local.next()
        case "previous": local.previous()
        case "seekid": if parts.count > 2, let seconds = Double(parts[2]) { local.seek(seconds) }
        case "setvol": if let number { local.setVolume(number) }
        case "random": settings.localRandom = number == 1; status.random = settings.localRandom; saveSettings()
        case "repeat": settings.localRepeat = number == 1; status.repeatQueue = settings.localRepeat; saveSettings()
        case "consume": settings.localConsume = number == 1; status.consume = settings.localConsume; saveSettings()
        case "deleteid": if let number { local.remove(number) }
        case "moveid": if parts.count > 2, let number, let position = Int(parts[2]) { local.move(number, to: position) }
        case "clear": local.clear()
        case "update": local.scanLibrary()
        default: return false
        }
        return true
    }

    func selectLocalFiles() {
        if settings.musicFolder.isEmpty { chooseMusicFolder(); return }
        switchToLocal()
    }

    func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.message = "Choose the root of your local music library"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !settings.musicFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: settings.musicFolder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.musicFolder = url.path
        switchToLocal()
    }

    private func switchToLocal() {
        settings.source = .local
        do { try settings.save() } catch { message = error.localizedDescription }
        local.activate()
        page = .queue
    }

    func selectMPDClient() {
        guard isLocal else { return }
        persistLocalQueue()
        local.deactivate()
        message = "Switching to MPD client…"
        settings.source = .mpd
        do { try settings.save() } catch { message = error.localizedDescription }
        status = MPDStatus([:])
        queue = []
        currentSong = nil
        entries = []
        browserPath = ""
        lastSongID = Int.min
        lastQueueVersion = Int.min
        page = .queue
        Task { await refresh(); await browse("") }
    }

    func playPause() {
        let command = status.state == "play" ? "pause 1" : status.state == "pause" ? "pause 0" : "play"
        perform(command, success: "Playback updated")
    }
    func playID(_ id: Int) { perform("playid \(id)", success: "Playing selected track") }
    func previous() { perform("previous", success: "Previous track") }
    func next() { perform("next", success: "Next track") }
    func stopPlayback() { perform("stop", success: "Stopped") }
    func seek(_ seconds: Double) {
        guard status.songID >= 0 else { return }
        perform("seekid \(status.songID) \(max(0, Int(seconds)))", success: "Position updated")
    }
    func volume(_ value: Double) { perform("setvol \(min(100, max(0, Int(value))))", success: "Volume updated") }
    func setRandom(_ value: Bool) { perform("random \(value ? 1 : 0)", success: "Random updated") }
    func setRepeat(_ value: Bool) { perform("repeat \(value ? 1 : 0)", success: "Repeat updated") }
    func setConsume(_ value: Bool) { perform("consume \(value ? 1 : 0)", success: "Consume updated") }
    func remove(_ song: Song) { perform("deleteid \(song.id)", success: "Removed \(song.displayTitle)") }

    func clearQueue() {
        settings.autoFill = false
        saveSettings()
        perform("clear", success: "Queue cleared; shuffle switched off")
    }

    func move(_ sourceID: Int, to targetID: Int, after: Bool) {
        guard let source = queue.firstIndex(where: { $0.id == sourceID }),
              let target = queue.firstIndex(where: { $0.id == targetID }), source != target else { return }
        let insertion = target + (after ? 1 : 0)
        let destination = insertion > source ? insertion - 1 : insertion
        guard destination != source else { return }
        perform("moveid \(sourceID) \(destination)", success: "Queue reordered")
    }

    func saveSettings() {
        settings.port = min(65535, max(1, settings.port))
        settings.fillTarget = min(500, max(1, settings.fillTarget))
        if settings.host.trimmingCharacters(in: .whitespaces).isEmpty { settings.host = "127.0.0.1" }
        do { try settings.save(); message = "Settings saved" }
        catch { message = error.localizedDescription }
        if isLocal {
            local.browse(browserPath)
        } else {
            lastQueueVersion = Int.min
            lastSongID = Int.min
            Task { await refresh(); await browse(browserPath) }
        }
    }

    func persistLocalQueue() {
        settings.localQueue = queue
        do { try settings.save() }
        catch { message = error.localizedDescription }
    }

    func browse(_ path: String) async {
        if isLocal { local.browse(path); return }
        do {
            entries = try await client().browse(path)
            browserPath = path
        } catch { message = error.localizedDescription }
    }
    func browseBack() {
        let parent = (browserPath as NSString).deletingLastPathComponent
        let destination = isLocal && parent == settings.musicFolder ? "" : parent
        Task { await browse(destination == "." ? "" : destination) }
    }

    func loadPlaylist(_ name: String) { perform("load \(MPDClient.quote(name))", success: "Playlist added") }
    func add(_ song: Song) {
        if isLocal { _ = local.add(song); message = "Added \(song.displayTitle)" }
        else { perform("addid \(MPDClient.quote(song.file))", success: "Added \(song.displayTitle)") }
    }
    func addFolder(_ path: String, afterCurrent: Bool = false) {
        guard isLocal else { return }
        local.addFolder(path, afterCurrent: afterCurrent)
    }
    func addNext(_ song: Song) {
        if isLocal { _ = local.add(song, afterCurrent: true); message = "Queued next: \(song.displayTitle)"; return }
        Task {
            do {
                let mpd = client()
                let latest = try await mpd.status()
                let position = latest.songPosition >= 0 ? " \(latest.songPosition + 1)" : ""
                _ = try await mpd.request("addid \(MPDClient.quote(song.file))\(position)")
                message = "Queued next: \(song.displayTitle)"
                await refresh()
            } catch { message = error.localizedDescription }
        }
    }
    func addAndPlay(_ song: Song) {
        if isLocal { local.play(local.add(song)); return }
        Task {
            do {
                let mpd = client()
                let fields = MPDClient.fields(try await mpd.request("addid \(MPDClient.quote(song.file))"))
                guard let id = Int(fields["id"] ?? "") else { throw MPDError(message: "MPD returned no queue ID.") }
                _ = try await mpd.request("playid \(id)")
                message = "Playing \(song.displayTitle)"
                await refresh()
            } catch { message = error.localizedDescription }
        }
    }

    func search() {
        if isLocal {
            searchResults = local.search(searchText)
            message = "\(searchResults.count) search results"
            return
        }
        Task {
            do {
                searchResults = try await client().search(searchText)
                message = "\(searchResults.count) search results"
            } catch { message = error.localizedDescription }
        }
    }

    func fill(to target: Int, autoStart: Bool = false) async {
        guard !isFilling else { return }
        isFilling = true
        defer { isFilling = false }
        if isLocal { local.fill(to: target, autoStart: autoStart); return }
        do {
            let mpd = client()
            let initial = try await mpd.status()
            guard !isLocal else { return }
            let missing = max(0, target - initial.queueLength)
            guard missing > 0 else { return }
            let count = try await mpd.libraryCount()
            guard !isLocal else { return }
            guard count > 0 else { throw MPDError(message: "MPD library is empty. Update it in Settings.") }
            var queued = Set(try await mpd.queue().map(\.file))
            var added = 0
            for _ in 0..<missing {
                if Task.isCancelled || isLocal { return }
                var chosen: Song?
                for _ in 0..<30 {
                    guard let candidate = try await mpd.librarySong(at: Int.random(in: 0..<count)) else { continue }
                    if chosen == nil { chosen = candidate }
                    if !queued.contains(candidate.file) && !recent.contains(candidate.file) {
                        chosen = candidate
                        break
                    }
                }
                guard let song = chosen else { throw MPDError(message: "MPD returned no library track.") }
                guard !isLocal else { return }
                _ = try await mpd.request("addid \(MPDClient.quote(song.file))")
                queued.insert(song.file)
                recent.append(song.file)
                if recent.count > 50 { recent.removeFirst() }
                added += 1
            }
            if autoStart && initial.state == "stop" && initial.queueLength == 0 && added > 0 {
                _ = try await mpd.request("play")
            }
            message = "Added \(added) random track\(added == 1 ? "" : "s")"
            await refresh()
        } catch { message = "Auto fill: \(error.localizedDescription)" }
    }

    func showAboutDialog() {
        showAbout = true
        if isLocal { statistics = local.statistics(); return }
        Task {
            do { statistics = try await client().statistics() }
            catch { message = error.localizedDescription }
        }
    }

    func pauseBeforeExit() async {
        if isLocal { local.pause(true); return }
        do {
            if try await client().status().state == "play" {
                _ = try await client().request("pause 1")
            }
        } catch { message = error.localizedDescription }
    }
}
