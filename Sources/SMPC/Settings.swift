import Foundation

enum SourceMode: String, Codable {
    case local = "Local Files"
    case mpd = "MPD Client"
}

struct Settings: Codable {
    var host = "127.0.0.1"
    var port = 6600
    var source = SourceMode.mpd
    var musicFolder = ""
    var localVolume = 0.5
    var localRandom = false
    var localRepeat = false
    var localConsume = false
    var localAutoFill = false
    var localFillTarget = 20
    var mpdAutoFill = false
    var mpdFillTarget = 20
    var localQueue: [Song] = []
    var showFilePath = false
    var showTrackIsland = true
    var askPauseOnExit = false

    var autoFill: Bool {
        get { source == .local ? localAutoFill : mpdAutoFill }
        set { if source == .local { localAutoFill = newValue } else { mpdAutoFill = newValue } }
    }

    var fillTarget: Int {
        get { source == .local ? localFillTarget : mpdFillTarget }
        set { if source == .local { localFillTarget = newValue } else { mpdFillTarget = newValue } }
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, source, musicFolder, localVolume, localRandom, localRepeat,
             localConsume, localAutoFill, localFillTarget, mpdAutoFill, mpdFillTarget, localQueue,
             autoFill, fillTarget, showFilePath, showTrackIsland, askPauseOnExit
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 6600
        source = try container.decodeIfPresent(SourceMode.self, forKey: .source) ?? .mpd
        musicFolder = try container.decodeIfPresent(String.self, forKey: .musicFolder) ?? ""
        localVolume = try container.decodeIfPresent(Double.self, forKey: .localVolume) ?? 0.5
        localRandom = try container.decodeIfPresent(Bool.self, forKey: .localRandom) ?? false
        localRepeat = try container.decodeIfPresent(Bool.self, forKey: .localRepeat) ?? false
        localConsume = try container.decodeIfPresent(Bool.self, forKey: .localConsume) ?? false
        let oldAutoFill = try container.decodeIfPresent(Bool.self, forKey: .autoFill) ?? false
        let oldFillTarget = try container.decodeIfPresent(Int.self, forKey: .fillTarget) ?? 20
        localAutoFill = try container.decodeIfPresent(Bool.self, forKey: .localAutoFill)
            ?? (source == .local ? oldAutoFill : false)
        localFillTarget = try container.decodeIfPresent(Int.self, forKey: .localFillTarget)
            ?? (source == .local ? oldFillTarget : 20)
        mpdAutoFill = try container.decodeIfPresent(Bool.self, forKey: .mpdAutoFill)
            ?? (source == .mpd ? oldAutoFill : false)
        mpdFillTarget = try container.decodeIfPresent(Int.self, forKey: .mpdFillTarget)
            ?? (source == .mpd ? oldFillTarget : 20)
        localQueue = try container.decodeIfPresent([Song].self, forKey: .localQueue) ?? []
        showFilePath = try container.decodeIfPresent(Bool.self, forKey: .showFilePath) ?? false
        showTrackIsland = try container.decodeIfPresent(Bool.self, forKey: .showTrackIsland) ?? true
        askPauseOnExit = try container.decodeIfPresent(Bool.self, forKey: .askPauseOnExit) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(source, forKey: .source)
        try container.encode(musicFolder, forKey: .musicFolder)
        try container.encode(localVolume, forKey: .localVolume)
        try container.encode(localRandom, forKey: .localRandom)
        try container.encode(localRepeat, forKey: .localRepeat)
        try container.encode(localConsume, forKey: .localConsume)
        try container.encode(localAutoFill, forKey: .localAutoFill)
        try container.encode(localFillTarget, forKey: .localFillTarget)
        try container.encode(mpdAutoFill, forKey: .mpdAutoFill)
        try container.encode(mpdFillTarget, forKey: .mpdFillTarget)
        try container.encode(localQueue, forKey: .localQueue)
        try container.encode(showFilePath, forKey: .showFilePath)
        try container.encode(showTrackIsland, forKey: .showTrackIsland)
        try container.encode(askPauseOnExit, forKey: .askPauseOnExit)
    }

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("s-mpc/settings.json")
    }

    static func load() -> Settings {
        if let data = try? Data(contentsOf: file),
           let value = try? JSONDecoder().decode(Settings.self, from: data) { return value }

        // Carry over A-mpd's connection and display preferences on first launch.
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("a-mpd/settings.json")
        guard let data = try? Data(contentsOf: legacy),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Settings()
        }
        var settings = Settings()
        settings.host = values["Host"] as? String ?? settings.host
        settings.port = values["Port"] as? Int ?? settings.port
        // Keep this off until the user enables it; A-mpd may still be filling the same queue.
        settings.mpdFillTarget = values["FillTarget"] as? Int ?? settings.mpdFillTarget
        settings.showFilePath = values["ShowFilePath"] as? Bool ?? settings.showFilePath
        settings.askPauseOnExit = values["AskPauseOnExit"] as? Bool ?? settings.askPauseOnExit
        return settings
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.file, options: .atomic)
    }
}
