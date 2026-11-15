import AVFoundation
import Foundation

private struct LocalLibraryCache: Codable, Sendable {
    let folder: String
    let songs: [Song]
}

@MainActor final class LocalBackend {
    weak var store: PlayerStore?
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var nextID = 1
    private var recent: [String] = []
    private(set) var library: [Song] = []
    private var libraryByFile: [String: Song] = [:]
    private var libraryFolder = ""
    private var scanTask: Task<Void, Never>?
    private var folderTask: Task<Void, Never>?
    private var folderRequestID = 0
    private static let cacheFile = Settings.file.deletingLastPathComponent()
        .appendingPathComponent("local-library.json")

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func deactivate() {
        scanTask?.cancel()
        scanTask = nil
        folderTask?.cancel()
        folderTask = nil
        folderRequestID += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    func activate() {
        guard let store else { return }
        deactivate()
        store.queue = store.settings.localQueue.filter { FileManager.default.fileExists(atPath: $0.file) }
        nextID = (store.queue.map(\.id).max() ?? 0) + 1
        store.currentSong = nil
        store.status = MPDStatus([:])
        store.status.volume = Int(store.settings.localVolume * 100)
        store.status.random = store.settings.localRandom
        store.status.repeatQueue = store.settings.localRepeat
        store.status.consume = store.settings.localConsume
        store.connectionText = "Local Files · \((store.settings.musicFolder as NSString).lastPathComponent)"
        store.browserPath = ""
        store.entries = []
        store.searchResults = []
        store.dropTargetID = nil
        reindex()
        store.persistLocalQueue()
        player.volume = Float(store.settings.localVolume)
        if libraryFolder == store.settings.musicFolder {
            browse("")
            store.message = "Local library: \(library.count.formatted()) tracks"
        } else if loadCachedLibrary(for: store.settings.musicFolder) {
            browse("")
            store.message = "Local library: \(library.count.formatted()) cached tracks"
        } else {
            library = []
            libraryByFile = [:]
            scanLibrary()
        }
    }

    func scanLibrary() {
        guard let store else { return }
        scanTask?.cancel()
        let root = store.settings.musicFolder
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else {
            library = []
            libraryByFile = [:]
            libraryFolder = ""
            store.message = "Choose a music folder in the Source menu."
            return
        }
        store.message = "Scanning local music folder…"
        scanTask = Task {
            let scan = Task.detached(priority: .userInitiated) {
                await Self.readLibrary(root)
            }
            let songs = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            guard !Task.isCancelled, store.settings.source == .local,
                  store.settings.musicFolder == root else { return }
            scanTask = nil
            library = songs
            libraryByFile = Dictionary(uniqueKeysWithValues: songs.map { ($0.file, $0) })
            libraryFolder = root
            store.message = "Local library: \(songs.count.formatted()) tracks"
            browse("")
            let cacheFile = Self.cacheFile
            Task.detached(priority: .utility) {
                let cache = LocalLibraryCache(folder: root, songs: songs)
                guard let data = try? JSONEncoder().encode(cache) else { return }
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: cacheFile, options: .atomic)
            }
        }
    }

    private func loadCachedLibrary(for folder: String) -> Bool {
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let cache = try? JSONDecoder().decode(LocalLibraryCache.self, from: data),
              cache.folder == folder, !cache.songs.isEmpty else { return false }
        library = cache.songs
        libraryByFile = Dictionary(uniqueKeysWithValues: cache.songs.map { ($0.file, $0) })
        libraryFolder = folder
        return true
    }

    private nonisolated static func readLibrary(_ folder: String) async -> [Song] {
        let urls = audioFiles(in: folder)
        var songs: [Song] = []
        for url in urls {
            if Task.isCancelled { break }
            let asset = AVURLAsset(url: url)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            var song = Song(file: url.path,
                            title: url.deletingPathExtension().lastPathComponent,
                            album: url.deletingLastPathComponent().lastPathComponent,
                            duration: duration.isFinite ? duration : 0)
            for item in metadata {
                let value = (try? await item.load(.stringValue)) ?? ""
                switch item.commonKey?.rawValue {
                case "title": if !value.isEmpty { song.title = value }
                case "artist": song.artist = value
                case "albumName": song.album = value
                case "creator": if !value.isEmpty { song.composer = value }
                default: break
                }
                if item.identifier?.rawValue.lowercased().contains("composer") == true, !value.isEmpty {
                    song.composer = value
                }
            }
            songs.append(song)
        }
        return songs.sorted { $0.file.localizedStandardCompare($1.file) == .orderedAscending }
    }

    private nonisolated static func audioFiles(in folder: String) -> [URL] {
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "alac"]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard extensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            urls.append(url)
        }
        return urls
    }

    func browse(_ path: String) {
        guard let store else { return }
        let root = URL(fileURLWithPath: store.settings.musicFolder, isDirectory: true).standardizedFileURL.path
        let folder = path.isEmpty ? root : URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        guard folder == root || folder.hasPrefix(root + "/") else {
            store.message = "Folder is outside the selected music tree."
            return
        }
        do {
            let children = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: folder, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
            store.entries = children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { url in
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        return LibraryEntry(kind: "directory", path: url.path, song: nil)
                    }
                    if let song = libraryByFile[url.path] {
                        return LibraryEntry(kind: "file", path: url.path, song: song)
                    }
                    return nil
                }
            store.browserPath = path
        } catch { store.message = error.localizedDescription }
    }

    func search(_ query: String) -> [Song] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return Array(library.lazy.filter {
            $0.title.localizedCaseInsensitiveContains(text) ||
            $0.artist.localizedCaseInsensitiveContains(text) ||
            $0.album.localizedCaseInsensitiveContains(text) ||
            $0.composer.localizedCaseInsensitiveContains(text) ||
            $0.file.localizedCaseInsensitiveContains(text)
        }.prefix(300))
    }

    func add(_ song: Song, afterCurrent: Bool = false, persist: Bool = true) -> Int {
        guard let store else { return -1 }
        var copy = song
        copy.id = nextID
        nextID += 1
        let current = store.queue.firstIndex { $0.id == store.status.songID }
        let index = afterCurrent ? (current.map { $0 + 1 } ?? store.queue.count) : store.queue.count
        store.queue.insert(copy, at: index)
        reindex()
        if persist { store.persistLocalQueue() }
        return copy.id
    }

    func addFolder(_ path: String, afterCurrent: Bool) {
        guard let store else { return }
        let root = URL(fileURLWithPath: store.settings.musicFolder, isDirectory: true).standardizedFileURL.path
        let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        guard folder == root || folder.hasPrefix(root + "/") else {
            store.message = "Folder is outside the selected music tree."
            return
        }
        if scanTask == nil && libraryFolder == root {
            enqueue(library.filter { $0.file.hasPrefix(folder + "/") },
                    from: folder, afterCurrent: afterCurrent)
            return
        }
        guard folder != root else {
            store.message = "Wait for the local library scan to finish."
            return
        }
        guard folderTask == nil else {
            store.message = "Already adding a folder…"
            return
        }
        folderRequestID += 1
        let requestID = folderRequestID
        store.message = "Reading tracks from \((folder as NSString).lastPathComponent)…"
        folderTask = Task {
            let songs = await Self.readLibrary(folder)
            guard !Task.isCancelled, requestID == folderRequestID,
                  store.settings.source == .local, store.settings.musicFolder == root else { return }
            folderTask = nil
            enqueue(songs, from: folder, afterCurrent: afterCurrent)
        }
    }

    private func enqueue(_ songs: [Song], from folder: String, afterCurrent: Bool) {
        guard let store else { return }
        guard !songs.isEmpty else {
            store.message = "No supported audio files in \((folder as NSString).lastPathComponent)."
            return
        }
        let current = store.queue.firstIndex { $0.id == store.status.songID }
        let index = afterCurrent ? (current.map { $0 + 1 } ?? store.queue.count) : store.queue.count
        let copies = songs.map { song -> Song in
            var copy = song
            copy.id = nextID
            nextID += 1
            return copy
        }
        store.queue.insert(contentsOf: copies, at: index)
        reindex()
        store.persistLocalQueue()
        store.message = "Added \(songs.count) track\(songs.count == 1 ? "" : "s") from \((folder as NSString).lastPathComponent)"
    }

    func play(_ id: Int) {
        guard let store, let index = store.queue.firstIndex(where: { $0.id == id }) else { return }
        let song = store.queue[index]
        let changedTrack = store.status.songID != id
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: URL(fileURLWithPath: song.file))
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.next(finished: true) } }
        player.replaceCurrentItem(with: item)
        player.volume = Float(store.settings.localVolume)
        player.play()
        store.status.songID = id
        store.status.songPosition = index
        store.status.elapsed = 0
        store.status.duration = song.duration
        store.status.state = "play"
        store.currentSong = song
        store.message = "Playing \(song.displayTitle)"
        if changedTrack && store.settings.showTrackIsland { TrackIsland.shared.show(song: song) }
        publishPlayback()
    }

    func pause(_ value: Bool) {
        guard let store else { return }
        if value { player.pause(); store.status.state = "pause" }
        else { player.play(); store.status.state = "play" }
        publishPlayback()
    }

    func playPause() {
        guard let store else { return }
        if store.status.state == "play" { pause(true) }
        else if store.status.songID >= 0 { pause(false) }
        else if let first = store.queue.first { play(first.id) }
    }

    func stop() {
        guard let store else { return }
        player.pause()
        player.seek(to: .zero)
        store.status.state = "stop"
        store.status.elapsed = 0
        publishPlayback()
    }

    func next(finished: Bool = false) {
        guard let store, !store.queue.isEmpty else { stop(); return }
        let current = store.queue.firstIndex { $0.id == store.status.songID } ?? -1
        if finished && store.settings.localConsume && current >= 0 {
            store.queue.remove(at: current)
            reindex()
            store.persistLocalQueue()
            if store.queue.isEmpty { stop(); store.currentSong = nil; return }
        }
        let nextIndex: Int
        if store.settings.localRandom {
            nextIndex = Int.random(in: store.queue.indices)
        } else if finished && store.settings.localConsume {
            nextIndex = min(current, store.queue.count - 1)
        } else if current + 1 < store.queue.count {
            nextIndex = current + 1
        } else if store.settings.localRepeat {
            nextIndex = 0
        } else { stop(); return }
        play(store.queue[nextIndex].id)
    }

    func previous() {
        guard let store, !store.queue.isEmpty else { return }
        let current = store.queue.firstIndex { $0.id == store.status.songID } ?? 0
        let index = current > 0 ? current - 1 : (store.settings.localRepeat ? store.queue.count - 1 : 0)
        play(store.queue[index].id)
    }

    func seek(_ seconds: Double) {
        guard let store, store.status.songID >= 0 else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        store.status.elapsed = seconds
        publishPlayback()
    }

    func setVolume(_ value: Int) {
        guard let store else { return }
        store.settings.localVolume = Double(min(100, max(0, value))) / 100
        store.status.volume = value
        player.volume = Float(store.settings.localVolume)
        store.saveSettings()
    }

    func remove(_ id: Int) {
        guard let store, let index = store.queue.firstIndex(where: { $0.id == id }) else { return }
        let current = store.status.songID == id
        store.queue.remove(at: index)
        reindex()
        store.persistLocalQueue()
        if current {
            if let next = store.queue.dropFirst(index).first ?? store.queue.first { play(next.id) }
            else { player.replaceCurrentItem(with: nil); store.currentSong = nil; stop() }
        }
    }

    func move(_ id: Int, to position: Int) {
        guard let store, let old = store.queue.firstIndex(where: { $0.id == id }) else { return }
        let song = store.queue.remove(at: old)
        store.queue.insert(song, at: min(max(0, position), store.queue.count))
        reindex()
        store.persistLocalQueue()
    }

    func clear() {
        guard let store else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        store.queue = []
        store.currentSong = nil
        store.status.songID = -1
        store.status.songPosition = -1
        stop()
        store.persistLocalQueue()
    }

    func fill(to target: Int, autoStart: Bool) {
        if scanTask != nil { return }
        guard let store, !library.isEmpty else {
            store?.message = "Choose a music folder with supported audio files."
            return
        }
        let wasEmpty = store.queue.isEmpty
        let missing = max(0, target - store.queue.count)
        guard missing > 0 else { return }
        var queued = Set(store.queue.map(\.file))
        for _ in 0..<missing {
            var chosen = library.randomElement()!
            for _ in 0..<30 {
                let candidate = library.randomElement()!
                if !queued.contains(candidate.file) && !recent.contains(candidate.file) {
                    chosen = candidate
                    break
                }
            }
            _ = add(chosen, persist: false)
            queued.insert(chosen.file)
            recent.append(chosen.file)
            if recent.count > 50 { recent.removeFirst() }
        }
        if autoStart && wasEmpty && missing > 0, let first = store.queue.first { play(first.id) }
        store.persistLocalQueue()
        store.message = "Added \(missing) random track\(missing == 1 ? "" : "s")"
    }

    func statistics() -> MPDStatistics {
        var stats = MPDStatistics([:])
        stats.songs = library.count
        stats.artists = Set(library.map(\.artist).filter { !$0.isEmpty }).count
        stats.albums = Set(library.map(\.album).filter { !$0.isEmpty }).count
        stats.databasePlaytime = Int(library.reduce(0) { $0 + $1.duration })
        return stats
    }

    private func reindex() {
        guard let store else { return }
        for index in store.queue.indices { store.queue[index].position = index }
        store.status.queueLength = store.queue.count
        store.status.queueVersion += 1
        store.status.songPosition = store.queue.firstIndex { $0.id == store.status.songID } ?? -1
    }

    private func tick(_ seconds: Double) {
        guard let store, store.settings.source == .local, store.status.songID >= 0,
              seconds.isFinite else { return }
        let elapsed = max(0, floor(seconds))
        guard Int(elapsed) != Int(store.status.elapsed) else { return }
        store.status.elapsed = elapsed
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            store.status.duration = duration
        }
    }

    private func publishPlayback() {
        guard let store else { return }
        MediaControls.shared.update(song: store.currentSong, status: store.status)
    }
}
