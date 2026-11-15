import Darwin
import Foundation

struct Song: Identifiable, Equatable, Sendable, Codable {
    var file: String
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var composer: String = ""
    var id: Int = -1
    var position: Int = -1
    var duration: Double = 0

    var displayTitle: String { title.isEmpty ? URL(fileURLWithPath: file).lastPathComponent : title }
    var displayArtist: String { artist.isEmpty ? "Unknown artist" : artist }
    var durationText: String { duration > 0 ? clock(duration) : "–" }
}

struct LibraryEntry: Sendable {
    var kind: String
    var path: String
    var song: Song?
    var name: String { (path as NSString).lastPathComponent }
}

struct MPDStatus: Sendable {
    var state = "stop"
    var volume = -1
    var songID = -1
    var songPosition = -1
    var queueLength = 0
    var queueVersion = 0
    var elapsed: Double = 0
    var duration: Double = 0
    var bitrate = 0
    var random = false
    var repeatQueue = false
    var consume = false

    init(_ fields: [String: String]) {
        state = fields["state"] ?? "stop"
        volume = Int(fields["volume"] ?? "") ?? -1
        songID = Int(fields["songid"] ?? "") ?? -1
        songPosition = Int(fields["song"] ?? "") ?? -1
        queueLength = Int(fields["playlistlength"] ?? "") ?? 0
        queueVersion = Int(fields["playlist"] ?? "") ?? 0
        elapsed = Double(fields["elapsed"] ?? "") ?? 0
        duration = Double(fields["duration"] ?? "") ?? 0
        bitrate = Int(fields["bitrate"] ?? "") ?? 0
        random = fields["random"] == "1"
        repeatQueue = fields["repeat"] == "1"
        consume = fields["consume"] == "1"
    }
}

struct MPDStatistics: Sendable {
    var artists = 0
    var albums = 0
    var songs = 0
    var uptime = 0
    var playtime = 0
    var databasePlaytime = 0
    var updated: Date?

    init(_ fields: [String: String]) {
        artists = Int(fields["artists"] ?? "") ?? 0
        albums = Int(fields["albums"] ?? "") ?? 0
        songs = Int(fields["songs"] ?? "") ?? 0
        uptime = Int(fields["uptime"] ?? "") ?? 0
        playtime = Int(fields["playtime"] ?? "") ?? 0
        databasePlaytime = Int(fields["db_playtime"] ?? "") ?? 0
        if let timestamp = TimeInterval(fields["db_update"] ?? ""), timestamp > 0 {
            updated = Date(timeIntervalSince1970: timestamp)
        }
    }
}

func clock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):" + String(format: "%02d", total % 60)
}

struct MPDError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct MPDClient: Sendable {
    let host: String
    let port: Int
    let password: String

    func request(_ command: String) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) { try requestSync(command) }.value
    }

    func status() async throws -> MPDStatus { MPDStatus(Self.fields(try await request("status"))) }
    func currentSong() async throws -> Song? { Self.songs(try await request("currentsong")).first }
    func queue() async throws -> [Song] { Self.songs(try await request("playlistinfo")) }
    func statistics() async throws -> MPDStatistics { MPDStatistics(Self.fields(try await request("stats"))) }
    func libraryCount() async throws -> Int {
        Int(Self.fields(try await request("searchcount \"(file != '')\""))["songs"] ?? "") ?? 0
    }
    func librarySong(at index: Int) async throws -> Song? {
        Self.songs(try await request("search \"(file != '')\" window \(index):\(index + 1)")).first
    }
    func search(_ text: String) async throws -> [Song] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return Self.songs(try await request("search any \(Self.quote(text)) window 0:300"))
    }
    func browse(_ path: String) async throws -> [LibraryEntry] {
        Self.entries(try await request(path.isEmpty ? "lsinfo" : "lsinfo \(Self.quote(path))"))
    }

    private func requestSync(_ command: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var first: UnsafeMutablePointer<addrinfo>?
        let lookup = getaddrinfo(host, String(port), &hints, &first)
        guard lookup == 0 else { throw MPDError(message: String(cString: gai_strerror(lookup))) }
        defer { freeaddrinfo(first) }

        var descriptor: Int32 = -1
        var address = first
        while let candidate = address {
            let info = candidate.pointee
            descriptor = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if descriptor >= 0 {
                if connect(descriptor, info.ai_addr, info.ai_addrlen) == 0 { break }
                Darwin.close(descriptor)
                descriptor = -1
            }
            address = info.ai_next
        }
        guard descriptor >= 0 else { throw MPDError(message: "Cannot connect to MPD at \(host):\(port).") }
        defer { Darwin.close(descriptor) }
        var timeout = timeval(tv_sec: 12, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let reader = SocketLines(descriptor)
        guard try reader.next().hasPrefix("OK MPD ") else { throw MPDError(message: "Invalid MPD greeting.") }
        if !password.isEmpty {
            try Self.write("password \(Self.quote(password))\n", to: descriptor)
            _ = try reader.response()
        }
        try Self.write(command + "\n", to: descriptor)
        return try reader.response()
    }

    private static func write(_ string: String, to descriptor: Int32) throws {
        let bytes = Array(string.utf8)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { raw in
                Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard sent > 0 else { throw MPDError(message: "MPD connection closed while sending.") }
            offset += sent
        }
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    static func fields(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            guard let separator = line.range(of: ": ") else { continue }
            result[String(line[..<separator.lowerBound]).lowercased()] = String(line[separator.upperBound...])
        }
        return result
    }

    static func songs(_ lines: [String]) -> [Song] { entries(lines).compactMap(\.song) }

    static func entries(_ lines: [String]) -> [LibraryEntry] {
        var result: [LibraryEntry] = []
        var currentKind = ""
        var currentPath = ""
        var attributes: [String: String] = [:]
        func finish() {
            guard !currentKind.isEmpty else { return }
            var song: Song?
            if currentKind == "file" {
                song = Song(file: currentPath,
                    title: attributes["title"] ?? "", artist: attributes["artist"] ?? "",
                    album: attributes["album"] ?? "", composer: attributes["composer"] ?? "",
                    id: Int(attributes["id"] ?? "") ?? -1,
                    position: Int(attributes["pos"] ?? "") ?? -1,
                    duration: Double(attributes["duration"] ?? attributes["time"] ?? "") ?? 0)
            }
            result.append(LibraryEntry(kind: currentKind, path: currentPath, song: song))
        }
        for line in lines {
            guard let separator = line.range(of: ": ") else { continue }
            let key = String(line[..<separator.lowerBound]).lowercased()
            let value = String(line[separator.upperBound...])
            if ["file", "directory", "playlist"].contains(key) {
                finish()
                currentKind = key
                currentPath = value
                attributes = [:]
            } else if attributes[key] == nil {
                attributes[key] = value
            }
        }
        finish()
        return result
    }
}

private final class SocketLines {
    private let descriptor: Int32
    private var pending = Data()
    init(_ descriptor: Int32) { self.descriptor = descriptor }

    func next() throws -> String {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                var line = pending.prefix(upTo: newline)
                if line.last == 13 { line = line.dropLast() }
                pending.removeSubrange(...newline)
                guard let text = String(data: line, encoding: .utf8) else {
                    throw MPDError(message: "Invalid UTF-8 from MPD.")
                }
                return text
            }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let received = Darwin.read(descriptor, &buffer, buffer.count)
            guard received > 0 else { throw MPDError(message: "MPD closed the connection or timed out.") }
            pending.append(contentsOf: buffer[..<received])
        }
    }

    func response() throws -> [String] {
        var lines: [String] = []
        while true {
            let line = try next()
            if line == "OK" { return lines }
            if line.hasPrefix("ACK ") { throw MPDError(message: line) }
            lines.append(line)
        }
    }
}
