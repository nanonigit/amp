import Foundation

public enum LibrarySection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tracks = "曲"
    case history = "履歴"
    case recentlyAdded = "最近追加した曲"
    case upNext = "次に再生"
    case albums = "アルバム"
    case artists = "アーティスト"
    case genres = "ジャンル"
    case playlists = "プレイリスト"
    case folders = "フォルダ"
    case favorites = "お気に入り"
    case cache = "キャッシュ"
    case settings = "設定と管理"
    case activityLog = "ログ"
    case diagnostics = "メタデータ診断"

    public var id: String { rawValue }
}

public enum StorageTopology {
    /// A separate Mac-local cache is only useful while the primary library is
    /// mounted outside the startup volume. Keep this path based so a detached
    /// external drive retains the same topology while it is unavailable.
    public static func usesSeparateLocalCache(primaryPath: String?) -> Bool {
        guard let primaryPath, !primaryPath.isEmpty else { return false }
        let standardized = URL(fileURLWithPath: primaryPath).standardizedFileURL.path
        return standardized == "/Volumes" || standardized.hasPrefix("/Volumes/")
    }
}

public enum LibraryActivityKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case added
    case addedToCache
    case addedToMainStorage
    case fileModified
    case metadataChanged
    case unavailable
    case restored
    case removedFromLibrary
    case movedToTrash

    public var id: String { rawValue }
}

public enum ActivityLogCategoryFilter: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case all
    case metadataChanged
    case added
    case removed
    case fileModified

    public var id: String { rawValue }

    public func title(isJapanese: Bool) -> String {
        switch self {
        case .all: isJapanese ? "すべて" : "All"
        case .metadataChanged: isJapanese ? "タグ・情報変更" : "Metadata Edits"
        case .added: isJapanese ? "曲追加" : "Added"
        case .removed: isJapanese ? "削除・ゴミ箱" : "Removed / Trashed"
        case .fileModified: isJapanese ? "ファイル変更" : "File Modified"
        }
    }

    public var kinds: Set<LibraryActivityKind> {
        switch self {
        case .all: []
        case .metadataChanged: [.metadataChanged]
        case .added: [.added, .addedToCache, .addedToMainStorage]
        case .removed: [.removedFromLibrary, .movedToTrash]
        case .fileModified: [.fileModified]
        }
    }
}

public enum LogRetentionLimit: Int, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case count1000 = 1000
    case count5000 = 5000
    case count10000 = 10000
    case count50000 = 50000

    public var id: Int { rawValue }

    public func title(isJapanese: Bool) -> String {
        switch self {
        case .count1000: isJapanese ? "1,000 件" : "1,000 items"
        case .count5000: isJapanese ? "5,000 件 (標準)" : "5,000 items (Default)"
        case .count10000: isJapanese ? "10,000 件" : "10,000 items"
        case .count50000: isJapanese ? "50,000 件" : "50,000 items"
        }
    }
}

public struct LibraryActivityChange: Codable, Hashable, Sendable {
    public let field: String
    public let oldValue: String
    public let newValue: String

    public init(field: String, oldValue: String, newValue: String) {
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public struct LibraryActivityEvent: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let kind: LibraryActivityKind
    public let trackID: Int64?
    public let filename: String
    public let title: String
    public let artist: String
    public let album: String
    public let relativePath: String
    public let absolutePath: String
    public let changes: [LibraryActivityChange]
    public let occurredAt: Date

    public init(
        id: Int64, kind: LibraryActivityKind, trackID: Int64?, filename: String,
        title: String, artist: String, album: String, relativePath: String,
        absolutePath: String, changes: [LibraryActivityChange], occurredAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.trackID = trackID
        self.filename = filename
        self.title = title
        self.artist = artist
        self.album = album
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.changes = changes
        self.occurredAt = occurredAt
    }
}

public struct LibraryActivityPage: Sendable {
    public let events: [LibraryActivityEvent]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public enum MetadataIssueKind: String, CaseIterable, Identifiable, Equatable, Sendable {
    case missingTitle
    case missingArtist
    case missingAlbum
    case missingYear
    case urlInMP3Metadata
    case commentInMP3
    case suspectedMojibake
    case duplicateTracks
    case suspectedVariations
    case corruptedOrEmpty
    public var id: String { rawValue }
}

public enum MetadataField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case title
    case artist
    case album
    case genre
    case comment
    public var id: String { rawValue }

    public static var variationFields: [MetadataField] {
        [.title, .artist, .album, .genre]
    }
}

public struct ExactMetadataFilter: Hashable, Sendable {
    public let field: MetadataField
    public let value: String

    public init(field: MetadataField, value: String) {
        self.field = field
        self.value = value
    }
}

public enum MetadataVariationReason: String, Sendable {
    case normalization
    case likelyTypo
}

public struct MetadataIssueSummary: Identifiable, Hashable, Sendable {
    public let kind: MetadataIssueKind
    public let count: Int
    public var id: MetadataIssueKind { kind }

    public init(kind: MetadataIssueKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public enum MusicBrainzAutoFillStatus: String, Codable, CaseIterable, Sendable {
    case completed
    case noMatch
    case transientFailure
}

public struct MusicBrainzAutoFillAttempt: Equatable, Sendable {
    public let albumKey: String
    public let fingerprint: String
    public let artist: String
    public let album: String
    public let status: MusicBrainzAutoFillStatus
    public let attemptCount: Int
    public let retryAfter: Date?
    public let lastError: String?
    public let attemptedAt: Date

    public init(
        albumKey: String,
        fingerprint: String,
        artist: String,
        album: String,
        status: MusicBrainzAutoFillStatus,
        attemptCount: Int,
        retryAfter: Date?,
        lastError: String?,
        attemptedAt: Date
    ) {
        self.albumKey = albumKey
        self.fingerprint = fingerprint
        self.artist = artist
        self.album = album
        self.status = status
        self.attemptCount = attemptCount
        self.retryAfter = retryAfter
        self.lastError = lastError
        self.attemptedAt = attemptedAt
    }
}

public struct MusicBrainzAutoFillSummary: Equatable, Sendable {
    public let completed: Int
    public let noMatch: Int
    public let transientFailure: Int

    public init(completed: Int = 0, noMatch: Int = 0, transientFailure: Int = 0) {
        self.completed = completed
        self.noMatch = noMatch
        self.transientFailure = transientFailure
    }

    public static let empty = MusicBrainzAutoFillSummary()
}

public enum MusicBrainzAutoFillPolicy {
    public static func shouldAnalyze(
        previous: MusicBrainzAutoFillAttempt?,
        fingerprint: String,
        now: Date
    ) -> Bool {
        guard let previous, previous.fingerprint == fingerprint else { return true }
        switch previous.status {
        case .completed:
            // A completed album normally disappears from the missing-number query.
            // Seeing it again means its metadata changed after completion.
            return true
        case .noMatch:
            return false
        case .transientFailure:
            return previous.retryAfter.map { $0 <= now } ?? true
        }
    }

    public static func retryDelay(attemptCount: Int) -> TimeInterval {
        let exponent = max(0, min(attemptCount - 1, 4))
        return min(24 * 60 * 60, TimeInterval(1 << exponent) * 60 * 60)
    }
}

public struct MetadataVariationCandidate: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let field: MetadataField
    public let valueA: String
    public let valueB: String
    public let trackCountA: Int
    public let trackCountB: Int
    public let reason: MetadataVariationReason
    public let editDistance: Int
}

public struct MetadataTerm: Hashable, Sendable {
    public let value: String
    public let normalized: String
    public let trackCount: Int

    public init(value: String, normalized: String, trackCount: Int) {
        self.value = value
        self.normalized = normalized
        self.trackCount = trackCount
    }
}

public struct StoredMetadataTerm: Hashable, Sendable {
    public let id: Int64
    public let prefix: String
    public let term: MetadataTerm
}

public struct MetadataVariationPage: Sendable {
    public let candidates: [MetadataVariationCandidate]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct MetadataAnalysisProgress: Sendable {
    public let field: MetadataField?
    public let processedTerms: Int
    public let candidates: Int
    public let isComplete: Bool

    public static let idle = MetadataAnalysisProgress(field: nil, processedTerms: 0, candidates: 0, isComplete: false)
}

public struct FacetPage: Sendable {
    public let facets: [Facet]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public enum TrackSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case title = "タイトル"
    case artist = "アーティスト"
    case album = "アルバム"
    case genre = "ジャンル"
    case year = "リリース年"
    case discNumber = "ディスク番号"
    case trackNumber = "トラック番号"
    case dateAdded = "追加日"
    case path = "ファイルパス"
    case duration = "時間"
    case format = "形式"

    public var id: String { rawValue }
}

public enum SortDirection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case ascending
    case descending
    public var id: String { rawValue }
}

public enum AlbumSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case name = "アルバム"
    case artist = "アーティスト"
    case year = "リリース年"
    case trackCount = "曲数"
    public var id: String { rawValue }
}

public enum ArtistSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case name = "アーティスト"
    case genre = "ジャンル"
    case albumCount = "アルバム数"
    case trackCount = "曲数"
    public var id: String { rawValue }
}

public enum TrackPlaybackScope: Equatable, Sendable {
    case library(query: String)
    case history(query: String)
    case recentlyAdded(query: String)
    case album(name: String, artist: String)
    case artist(name: String)
    case genre(name: String)
    case favorites
    case cache(query: String)
    case playlist(id: Int64)
    case metadataIssue(kind: MetadataIssueKind)
    case metadataValue(field: MetadataField, value: String)
}

public struct TrackPlaybackContext: Equatable, Sendable {
    public let scope: TrackPlaybackScope
    public let sort: TrackSort
    public let direction: SortDirection

    public init(scope: TrackPlaybackScope, sort: TrackSort, direction: SortDirection) {
        self.scope = scope
        self.sort = sort
        self.direction = direction
    }
}

public struct Track: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let rootID: Int64
    public let relativePath: String
    public let filename: String
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let genre: String
    public let year: String
    public let isCompilation: Bool
    public let discNumber: Int?
    public let trackNumber: Int?
    public let duration: Double
    public let fileSize: Int64
    public let modifiedAt: Date
    public let format: String
    public let bitrate: Int?
    public let hasArtwork: Bool
    public let isAvailable: Bool
    public let addedAt: Date
    public let isFavorite: Bool
    public let comment: String

    public init(
        id: Int64 = 0,
        rootID: Int64,
        relativePath: String,
        filename: String,
        title: String,
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        genre: String = "",
        year: String = "",
        isCompilation: Bool = false,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        duration: Double = 0,
        fileSize: Int64,
        modifiedAt: Date,
        format: String,
        bitrate: Int? = nil,
        hasArtwork: Bool = false,
        isAvailable: Bool = true,
        addedAt: Date = Date(),
        isFavorite: Bool = false,
        comment: String = ""
    ) {
        self.id = id
        self.rootID = rootID
        self.relativePath = relativePath
        self.filename = filename
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.year = year
        self.isCompilation = isCompilation
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.duration = duration
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.format = format
        self.bitrate = bitrate
        self.hasArtwork = hasArtwork
        self.isAvailable = isAvailable
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.comment = comment
    }

    /// Matches the artist key used by album grouping in the library database.
    public var albumNavigationArtist: String {
        let normalizedAlbumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedAlbumArtist.isEmpty { return normalizedAlbumArtist }
        return artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public struct MetadataMatchLocation: Identifiable, Hashable, Sendable {
        public var id: String { fieldName }
        public let fieldName: String
        public let value: String

        public init(fieldName: String, value: String) {
            self.fieldName = fieldName
            self.value = value
        }
    }

    public func urlMatchLocations(isJapanese: Bool) -> [MetadataMatchLocation] {
        var locations: [MetadataMatchLocation] = []
        if title.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "曲名" : "Title", value: title))
        }
        if artist.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アーティスト" : "Artist", value: artist))
        }
        if album.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アルバム" : "Album", value: album))
        }
        if albumArtist.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アルバムアーティスト" : "Album Artist", value: albumArtist))
        }
        if genre.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "ジャンル" : "Genre", value: genre))
        }
        if comment.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "コメント" : "Comment", value: comment))
        }
        if filename.containsURLPattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "ファイル名" : "Filename", value: filename))
        }
        return locations
    }

    public func mojibakeMatchLocations(isJapanese: Bool) -> [MetadataMatchLocation] {
        var locations: [MetadataMatchLocation] = []
        if title.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "曲名" : "Title", value: title))
        }
        if artist.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アーティスト" : "Artist", value: artist))
        }
        if album.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アルバム" : "Album", value: album))
        }
        if albumArtist.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "アルバムアーティスト" : "Album Artist", value: albumArtist))
        }
        if genre.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "ジャンル" : "Genre", value: genre))
        }
        if comment.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "コメント" : "Comment", value: comment))
        }
        if filename.containsMojibakePattern {
            locations.append(MetadataMatchLocation(fieldName: isJapanese ? "ファイル名" : "Filename", value: filename))
        }
        return locations
    }
}

public extension String {
    var containsURLPattern: Bool {
        let lower = self.lowercased()
        return lower.contains("http://")
            || lower.contains("https://")
            || lower.contains("www.")
            || lower.contains("://")
            || lower.contains(".com/")
            || lower.contains(".net/")
            || lower.contains(".org/")
            || lower.contains(".ru/")
            || lower.contains(".io/")
            || lower.hasSuffix(".com")
            || lower.hasSuffix(".net")
            || lower.hasSuffix(".org")
            || lower.contains(".com ")
            || lower.contains(".net ")
            || lower.contains(".org ")
    }

    var containsMojibakePattern: Bool {
        self.contains("")
            || self.contains("Ã")
            || self.contains("Â")
            || self.contains("â€")
            || self.contains("ÔÌ")
            || self.contains("¼")
            || self.contains("縺")
            || self.contains("繧")
            || self.contains("譁")
    }
}

public struct TrackMetadataEdit: Hashable, Codable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var composer: String
    public var lyricist: String
    public var arranger: String
    public var conductor: String
    public var publisher: String
    public var genre: String
    public var year: String
    public var isCompilation: Bool
    public var discNumber: Int?
    public var totalDiscs: Int?
    public var trackNumber: Int?
    public var totalTracks: Int?
    public var bpm: String
    public var initialKey: String
    public var isrc: String
    public var copyright: String
    public var grouping: String
    public var subtitle: String
    public var originalAlbum: String
    public var originalArtist: String
    public var comment: String
    public var lyrics: String
    public var url: String
    public var artworkData: Data?

    public init(track: Track) {
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        composer = ""
        lyricist = ""
        arranger = ""
        conductor = ""
        publisher = ""
        genre = track.genre
        year = ""
        isCompilation = track.isCompilation
        discNumber = track.discNumber
        totalDiscs = nil
        trackNumber = track.trackNumber
        totalTracks = nil
        bpm = ""
        initialKey = ""
        isrc = ""
        copyright = ""
        grouping = ""
        subtitle = ""
        originalAlbum = ""
        originalArtist = ""
        comment = ""
        lyrics = ""
        url = ""
        artworkData = nil
    }

    /// Removes only leading ASCII and Japanese full-width spaces from a title.
    /// Spaces inside or at the end of the title remain untouched.
    public func normalizingLeadingTitleSpaces() -> TrackMetadataEdit {
        var normalized = self
        normalized.title = String(title.drop(while: { $0 == " " || $0 == "　" }))
        return normalized
    }

    public func normalizingLeadingAndTrailingWhitespace() -> TrackMetadataEdit {
        var normalized = self
        normalized.title = MetadataTextNormalizer.trimLeadingAndTrailingSpaces(title)
        normalized.artist = MetadataTextNormalizer.trimLeadingAndTrailingSpaces(artist)
        normalized.album = MetadataTextNormalizer.trimLeadingAndTrailingSpaces(album)
        normalized.albumArtist = MetadataTextNormalizer.trimLeadingAndTrailingSpaces(albumArtist)
        normalized.genre = GenreNormalizer.normalize(genre)
        return normalized
    }

    /// Normalizes only character-width variants. Broad compatibility
    /// normalization is intentionally avoided so Roman numerals, circled
    /// numbers, ligatures, and intentional spacing remain untouched.
    public func normalizingCharacterWidths() -> TrackMetadataEdit {
        var normalized = self
        normalized.title = MetadataTextNormalizer.normalizedWidths(title)
        normalized.artist = MetadataTextNormalizer.normalizedWidths(artist)
        normalized.album = MetadataTextNormalizer.normalizedWidths(album)
        normalized.albumArtist = MetadataTextNormalizer.normalizedWidths(albumArtist)
        normalized.composer = MetadataTextNormalizer.normalizedWidths(composer)
        normalized.lyricist = MetadataTextNormalizer.normalizedWidths(lyricist)
        normalized.arranger = MetadataTextNormalizer.normalizedWidths(arranger)
        normalized.conductor = MetadataTextNormalizer.normalizedWidths(conductor)
        normalized.publisher = MetadataTextNormalizer.normalizedWidths(publisher)
        normalized.genre = GenreNormalizer.normalize(genre)
        normalized.grouping = MetadataTextNormalizer.normalizedWidths(grouping)
        normalized.subtitle = MetadataTextNormalizer.normalizedWidths(subtitle)
        normalized.originalAlbum = MetadataTextNormalizer.normalizedWidths(originalAlbum)
        normalized.originalArtist = MetadataTextNormalizer.normalizedWidths(originalArtist)
        return normalized
    }

    public func hasTextChanges(comparedWith track: Track) -> Bool {
        title != track.title || artist != track.artist || album != track.album
            || albumArtist != track.albumArtist || genre != track.genre
    }
}

public struct PendingMetadataEdit: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let trackID: Int64
    public let edit: TrackMetadataEdit
    public let updatedAt: Date

    public init(id: Int64, trackID: Int64, edit: TrackMetadataEdit, updatedAt: Date) {
        self.id = id
        self.trackID = trackID
        self.edit = edit
        self.updatedAt = updatedAt
    }
}

public extension Track {
    /// Returns an in-memory representation of metadata that was successfully written to the file.
    func applying(_ edit: TrackMetadataEdit) -> Track {
        Track(
            id: id,
            rootID: rootID,
            relativePath: relativePath,
            filename: filename,
            title: edit.title,
            artist: edit.artist,
            album: edit.album,
            albumArtist: edit.albumArtist,
            genre: edit.genre,
            year: edit.year.isEmpty ? year : edit.year,
            isCompilation: edit.isCompilation,
            discNumber: edit.discNumber,
            trackNumber: edit.trackNumber,
            duration: duration,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            format: format,
            bitrate: bitrate,
            hasArtwork: edit.artworkData != nil || hasArtwork,
            isAvailable: isAvailable,
            addedAt: addedAt,
            isFavorite: isFavorite,
            comment: edit.comment
        )
    }
}

public enum MetadataTextNormalizer {
    public static func trimLeadingAndTrailingSpaces(_ value: String) -> String {
        var s = value[...]
        while let first = s.first, first == " " || first == "　" || first.isNewline {
            s.removeFirst()
        }
        while let last = s.last, last == " " || last == "　" || last.isNewline {
            s.removeLast()
        }
        return String(s)
    }

    public static func normalizedWidths(_ value: String) -> String {
        var result = ""
        var halfwidthKana = String.UnicodeScalarView()

        func appendKana() {
            guard !halfwidthKana.isEmpty else { return }
            result.append(String(halfwidthKana).precomposedStringWithCompatibilityMapping)
            halfwidthKana.removeAll(keepingCapacity: true)
        }

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0xFF61...0xFF9F:
                halfwidthKana.append(scalar)
            case 0xFF01...0xFF5E:
                appendKana()
                if let ascii = UnicodeScalar(scalar.value - 0xFEE0) {
                    result.unicodeScalars.append(ascii)
                }
            default:
                appendKana()
                result.unicodeScalars.append(scalar)
            }
        }
        appendKana()
        return result
    }
}

public enum GenreNormalizer {
    private static let exactJapaneseMap: [String: String] = [
        // --- Basic genres ---
        "ロック": "Rock",
        "ポップス": "Pop",
        "ポップ": "Pop",
        "ジャズ": "Jazz",
        "クラシック": "Classical",
        "交響曲": "Classical",
        "協奏曲": "Classical",
        "ブルース": "Blues",
        "ソウル": "Soul",
        "ソウルミュージック": "Soul",
        "ファンク": "Funk",
        "ディスコ": "Disco",
        "レゲエ": "Reggae",
        "カントリー": "Country",
        "フォーク": "Folk",
        "フォークソング": "Folk",
        "ゴスペル": "Gospel",
        "ラテン": "Latin",

        // --- J-Pop / K-Pop ---
        "J-POP": "J-Pop",
        "JPOP": "J-Pop",
        "J POP": "J-Pop",
        "Jポップ": "J-Pop",
        "ジェイポップ": "J-Pop",
        "K-POP": "K-Pop",
        "KPOP": "K-Pop",
        "K POP": "K-Pop",
        "邦楽": "J-Pop",
        "洋楽": "Western Pop",

        // --- Anime / Game ---
        "アニメ": "Anime",
        "アニソン": "Anime",
        "アニメソング": "Anime",
        "ゲーム": "Video Game Music",
        "ゲームミュージック": "Video Game Music",
        "ゲーム音楽": "Video Game Music",
        "ボーカロイド": "Vocaloid",
        "ボカロ": "Vocaloid",

        // --- Hip Hop / Rap ---
        "ヒップホップ": "Hip Hop",
        "ラップ": "Hip Hop",

        // --- Electronic / Dance ---
        "エレクトロニック": "Electronic",
        "エレクトロニカ": "Electronica",
        "エレクトロ": "Electro",
        "電子音楽": "Electronic",
        "テクノ": "Techno",
        "ハウス": "House",
        "トランス": "Trance",
        "ダンス": "Dance",
        "ダンスミュージック": "Dance",
        "ユーロビート": "Eurobeat",
        "ドラムンベース": "Drum and Bass",
        "ダブステップ": "Dubstep",
        "シンセポップ": "Synth Pop",
        "シンセ・ポップ": "Synth Pop",
        "エレクトロポップ": "Electropop",
        "ニューウェーブ": "New Wave",
        "ニュー・ウェーブ": "New Wave",
        "インダストリアル": "Industrial",

        // --- Rock sub-genres ---
        "ハードロック": "Hard Rock",
        "オルタナティヴ": "Alternative Rock",
        "オルタナティブ": "Alternative Rock",
        "オルタナティヴ・ロック": "Alternative Rock",
        "オルタナティブ・ロック": "Alternative Rock",
        "オルタナティヴロック": "Alternative Rock",
        "オルタナティブロック": "Alternative Rock",
        "プログレ": "Progressive Rock",
        "プログレッシブ・ロック": "Progressive Rock",
        "プログレッシブロック": "Progressive Rock",
        "サイケデリック": "Psychedelic",
        "サイケデリック・ロック": "Psychedelic Rock",
        "サイケデリックロック": "Psychedelic Rock",
        "ポストロック": "Post-Rock",
        "ポスト・ロック": "Post-Rock",
        "ガレージロック": "Garage Rock",
        "ガレージ・ロック": "Garage Rock",
        "サザンロック": "Southern Rock",
        "サザン・ロック": "Southern Rock",
        "グランジ": "Grunge",
        "シューゲイザー": "Shoegaze",
        "シューゲイズ": "Shoegaze",

        // --- Metal sub-genres ---
        "メタル": "Metal",
        "ヘヴィメタル": "Heavy Metal",
        "ヘビーメタル": "Heavy Metal",
        "デスメタル": "Death Metal",
        "デス・メタル": "Death Metal",
        "ブラックメタル": "Black Metal",
        "ブラック・メタル": "Black Metal",
        "パワーメタル": "Power Metal",
        "パワー・メタル": "Power Metal",
        "スラッシュメタル": "Thrash Metal",
        "スラッシュ・メタル": "Thrash Metal",
        "ドゥームメタル": "Doom Metal",
        "ドゥーム・メタル": "Doom Metal",
        "スピードメタル": "Speed Metal",
        "スピード・メタル": "Speed Metal",
        "メロディックデスメタル": "Melodic Death Metal",
        "メロディック・デスメタル": "Melodic Death Metal",
        "メロデス": "Melodic Death Metal",
        "プログレッシブメタル": "Progressive Metal",
        "プログレッシブ・メタル": "Progressive Metal",
        "ゴシックメタル": "Gothic Metal",
        "ゴシック・メタル": "Gothic Metal",
        "フォークメタル": "Folk Metal",
        "フォーク・メタル": "Folk Metal",
        "ニューメタル": "Nu Metal",
        "ニュー・メタル": "Nu Metal",
        "ネオクラシカルメタル": "Neoclassical Metal",
        "ネオクラシカル・メタル": "Neoclassical Metal",
        "シンフォニックメタル": "Symphonic Metal",
        "シンフォニック・メタル": "Symphonic Metal",
        "シンフォニックパワーメタル": "Symphonic Power Metal",
        "シンフォニック・パワーメタル": "Symphonic Power Metal",
        "シンフォニックブラックメタル": "Symphonic Black Metal",
        "シンフォニック・ブラックメタル": "Symphonic Black Metal",

        // --- Symphonic / Orchestral ---
        "シンフォニック": "Symphonic",
        "シンフォニックロック": "Symphonic Rock",
        "シンフォニック・ロック": "Symphonic Rock",

        // --- Punk ---
        "パンク": "Punk",
        "パンクロック": "Punk Rock",
        "パンク・ロック": "Punk Rock",
        "ハードコア": "Hardcore",
        "ハードコアパンク": "Hardcore Punk",
        "ハードコア・パンク": "Hardcore Punk",
        "ポストパンク": "Post-Punk",
        "ポスト・パンク": "Post-Punk",
        "ポップパンク": "Pop Punk",
        "ポップ・パンク": "Pop Punk",
        "スカパンク": "Ska Punk",
        "スカ・パンク": "Ska Punk",
        "メロコア": "Melodic Hardcore",

        // --- Jazz sub-genres ---
        "ジャズ・フュージョン": "Jazz Fusion",
        "ジャズフュージョン": "Jazz Fusion",
        "ジャズ・ファンク": "Jazz Funk",
        "ジャズファンク": "Jazz Funk",
        "ジャズ・ヒップホップ": "Jazz Hip Hop",
        "ジャズヒップホップ": "Jazz Hip Hop",
        "ジャズ・クリスマス": "Christmas Jazz",
        "ジャズクリスマス": "Christmas Jazz",
        "ジャズ・ロック": "Jazz Rock",
        "ジャズロック": "Jazz Rock",
        "スムースジャズ": "Smooth Jazz",
        "スムース・ジャズ": "Smooth Jazz",
        "アシッドジャズ": "Acid Jazz",
        "アシッド・ジャズ": "Acid Jazz",
        "フリージャズ": "Free Jazz",
        "フリー・ジャズ": "Free Jazz",
        "フュージョン": "Fusion",

        // --- R&B / Soul ---
        "R&B": "R&B",
        "アール・アンド・ビー": "R&B",
        "リズム・アンド・ブルース": "R&B",
        "ネオソウル": "Neo Soul",
        "ネオ・ソウル": "Neo Soul",
        "モータウン": "Motown",

        // --- Soundtrack / OST ---
        "サウンドトラック": "Soundtrack",
        "サントラ": "Soundtrack",
        "劇伴": "Soundtrack",
        "映画音楽": "Film Score",

        // --- World / Traditional ---
        "ワールドミュージック": "World Music",
        "ワールド": "World",
        "民謡": "Traditional Folk",
        "伝統音楽": "Traditional",
        "沖縄民謡": "Okinawan Folk Music",
        "現代": "Contemporary",
        "現代クラシック": "Contemporary Classical",
        "讃美歌": "Hymn",
        "子ども向けアニメソング": "Children's Anime Songs",
        "実験": "Experimental",
        "実験的ロック": "Experimental Rock",
        "実験電子": "Experimental Electronic",
        "渋谷系": "Shibuya-Kei",
        "吹奏楽": "Wind Ensemble",
        "伝統邦楽": "Traditional Japanese Music",
        "電子": "Electronic",
        "特撮": "Tokusatsu",
        "日本のフォーク": "Japanese Folk",
        "日本のロック": "Japanese Rock",
        "日本語ヒップホップ": "Japanese Hip Hop",
        "演歌": "Enka",
        "歌謡曲": "Kayokyoku",
        "シティポップ": "City Pop",
        "シティ・ポップ": "City Pop",
        "シャンソン": "Chanson",
        "ボサノバ": "Bossa Nova",
        "ボサノヴァ": "Bossa Nova",
        "サンバ": "Samba",
        "フラメンコ": "Flamenco",
        "タンゴ": "Tango",
        "ケルト": "Celtic",
        "ケルティック": "Celtic",
        "アフロビート": "Afrobeat",

        // --- Ambient / New Age ---
        "環境音楽": "Ambient",
        "アンビエント": "Ambient",
        "ニューエイジ": "New Age",
        "チルアウト": "Chillout",
        "ドローン": "Drone",

        // --- Reggae / Ska / Dub ---
        "スカ": "Ska",
        "ダブ": "Dub",
        "ダンスホール": "Dancehall",

        // --- Children / Holiday ---
        "童謡": "Children's Music",
        "キッズ": "Children's Music",
        "クリスマス": "Christmas",
        "クリスマスソング": "Christmas",

        // --- Other ---
        "ノベルティ・ミュージック": "Novelty",
        "ノベルティ": "Novelty",
        "ハードコアテクノ": "Hardcore Techno",
        "ハードコア・テクノ": "Hardcore Techno",
        "ハードコア・ヒップホップ": "Hardcore Hip Hop",
        "ハードコアヒップホップ": "Hardcore Hip Hop",
        "ハードバップ": "Hard Bop",
        "ハードバップ・ジャズ": "Hard Bop",
        "ハード・バップ": "Hard Bop",
        "バロック・ポップ": "Baroque Pop",
        "バロックポップ": "Baroque Pop",
        "バロック音楽": "Baroque",
        "バロック": "Baroque",
        "ヒップホップ／ラップ": "Hip Hop / Rap",
        "ヒップホップ/ラップ": "Hip Hop / Rap",
        "インディー": "Indie",
        "インディーズ": "Indie",
        "インディーロック": "Indie Rock",
        "インディー・ロック": "Indie Rock",
        // --- Newly requested genres ---
        "フレンチ・ハウス": "French House",
        "フレンチハウス": "French House",
        "フレンチ・ヒップホップ": "French Hip Hop",
        "フレンチヒップホップ": "French Hip Hop",
        "フレンチ・ポップ": "French Pop",
        "フレンチポップ": "French Pop",
        "フレンチ・ポップス": "French Pop",
        "フレンチポップス": "French Pop",
        "ブラジル音楽": "Brazilian Music",
        "サンバロック": "Samba Rock",
        "サンバ・ロック": "Samba Rock",
        "ブラックゲイズ": "Blackgaze",
        "ブラックンド・スラッシュメタル": "Blackened Thrash Metal",
        "ブラックンドスラッシュメタル": "Blackened Thrash Metal",
        "ブラックンド・デスメタル": "Blackened Death Metal",
        "ブラックンドデスメタル": "Blackened Death Metal",
        "ブリットポップ": "Britpop",
        "ブリット・ポップ": "Britpop",
        "ブルーグラス": "Bluegrass",
        "ブルースロック": "Blues Rock",
        "ブルース・ロック": "Blues Rock",
        "ブルータルデスメタル": "Brutal Death Metal",
        "ブルータル・デスメタル": "Brutal Death Metal",
        "ブレイクコア": "Breakcore",
        "ブレイク・コア": "Breakcore",
        "ブレイクビーツ": "Breakbeat",
        "ブレイク・ビーツ": "Breakbeat",
        "プログレッシブハウス": "Progressive House",
        "プログレッシブ・ハウス": "Progressive House",
        "プログレッシブ・デスメタル": "Progressive Death Metal",
        "プログレッシブデスメタル": "Progressive Death Metal",
        "プログレッシブ・トランス": "Progressive Trance",
        "プログレッシブトランス": "Progressive Trance",
        "プログレッシブ・パワーメタル": "Progressive Power Metal",
        "プログレッシブパワーメタル": "Progressive Power Metal",
        "ペイガンメタル": "Pagan Metal",
        "ペイガン・メタル": "Pagan Metal",
        "ホラーコア": "Horrorcore",
        "ホラーコア・ヒップホップ": "Horrorcore Hip Hop",
        "ホラーコアヒップホップ": "Horrorcore Hip Hop",
        "ホラーパンク": "Horror Punk",
        "ホラー・パンク": "Horror Punk",
        "ホラーメタル": "Horror Metal",
        "ホラー・メタル": "Horror Metal",
        "ボサノヴァ・ジャズ": "Bossa Nova Jazz",
        "ボサノバ・ジャズ": "Bossa Nova Jazz",
        "ボレロ": "Bolero",
        "ボーカル・ジャズ": "Vocal Jazz",
        "ボーカルジャズ": "Vocal Jazz",
        "ボーカル・ポップ": "Vocal Pop",
        "ボーカルポップ": "Vocal Pop",
        "ポストハードコア": "Post-Hardcore",
        "ポスト・ハードコア": "Post-Hardcore",
        "ポスト・グランジ": "Post-Grunge",
        "ポストグランジ": "Post-Grunge",
        "ポップラップ": "Pop Rap",
        "ポップ・ラップ": "Pop Rap",
        "ポップロック": "Pop Rock",
        "ポップ・ロック": "Pop Rock",
        "マッシュアップ": "Mashup",
        "マーチャル・インダストリアル": "Martial Industrial",
        "マーチャルインダストリアル": "Martial Industrial",
        "ミニマル・テクノ": "Minimal Techno",
        "ミニマルテクノ": "Minimal Techno",
        "ミュージカル・ソング": "Musical Song",
        "ミュージカルソング": "Musical Song",
        "ミンスコア": "Mincecore",
        "メタルコア": "Metalcore",
        "メロディック・ハードコア・パンク": "Melodic Hardcore Punk",
        "メロディックハードコアパンク": "Melodic Hardcore Punk",
        "メロディック・ハードロック": "Melodic Hard Rock",
        "メロディックハードロック": "Melodic Hard Rock",
        "メロディック・ブラックメタル": "Melodic Black Metal",
        "メロディックブラックメタル": "Melodic Black Metal",
        "メンフィス・アンダーグラウンド・ヒップホップ": "Memphis Underground Hip Hop",
        "メンフィスアンダーグラウンドヒップホップ": "Memphis Underground Hip Hop",
        "メンフィス・ラップ": "Memphis Rap",
        "メンフィスラップ": "Memphis Rap",
        "モルナ": "Morna",
        "ユーロダンス": "Eurodance",
        "ラップロック": "Rap Rock",
        "ラップ・ロック": "Rap Rock",
        "ラテンジャズ": "Latin Jazz",
        "ラテン・ジャズ": "Latin Jazz",
        "ラテンポップ": "Latin Pop",
        "ラテン・ポップ": "Latin Pop",
        "ラテン・エレクトロニカ": "Latin Electronica",
        "ラテンエレクトロニカ": "Latin Electronica",
        "ヴィジュアル系ロック": "Visual Kei Rock",
        "ビジュアル系ロック": "Visual Kei Rock",
        "ジャズ・サウンドトラック": "Jazz Soundtrack",
        "ジャズサウンドトラック": "Jazz Soundtrack",
        "ストーナー・メタル": "Stoner Metal",
        "ストーナーメタル": "Stoner Metal",
        "スポークンワード／コメディ": "Spoken Word / Comedy",
        "スポークンワード/コメディ": "Spoken Word / Comedy",
        "スラッジ・メタル": "Sludge Metal",
        "スラッジメタル": "Sludge Metal",
        "ソウル・ジャズ": "Soul Jazz",
        "ソウルジャズ": "Soul Jazz",
        "ソウル・ポップ": "Soul Pop",
        "ソウルポップ": "Soul Pop",
        "ソウル／R&B": "Soul / R&B",
        "ソウル/R&B": "Soul / R&B",
        "ソフト・ロック": "Soft Rock",
        "ソフトロック": "Soft Rock",
        "ダーク・アンビエント": "Dark Ambient",
        "ダークアンビエント": "Dark Ambient",
        "ダーク・キャバレー": "Dark Cabaret",
        "ダークキャバレー": "Dark Cabaret",
        "キャバレー": "Cabaret",

        // --- Building-block words for substring replacement ---
        "フレンチ": "French",
        "ブラジル": "Brazilian",
        "ブラックンド": "Blackened",
        "ブリット": "Brit",
        "ブルータル": "Brutal",
        "ブレイク": "Break",
        "ビーツ": "Beats",
        "ゲイズ": "Gaze",
        "ペイガン": "Pagan",
        "ホラー": "Horror",
        "ボーカル": "Vocal",
        "マーチャル": "Martial",
        "ミニマル": "Minimal",
        "ミュージカル": "Musical",
        "ミンス": "Mince",
        "コア": "Core",
        "メンフィス": "Memphis",
        "アンダーグラウンド": "Underground",
        "ユーロ": "Euro",
        "バップ": "Bop",
        "ブラック": "Black",
        "パワー": "Power",
        "スピード": "Speed",
        "デス": "Death",
        "スラッシュ": "Thrash",
        "ドゥーム": "Doom",
        "ゴシック": "Gothic",
        "メロディック": "Melodic",
        "プログレッシブ": "Progressive",
        "ネオクラシカル": "Neoclassical",
        "スムース": "Smooth",
        "アシッド": "Acid",
        "フリー": "Free",
        "ネオ": "Neo",
        "ポスト": "Post",
        "ニュー": "New"
    ]

    private static let acronyms: Set<String> = [
        "R&B", "EDM", "IDM", "EBM", "AOR", "OST", "DJ", "CD", "UK", "US", "BPM", "LO-FI", "HI-FI"
    ]

    /// A punctuation- and case-insensitive index. Canonical values are also
    /// indexed, so Japanese, English casing, middle-dot, slash and dash
    /// variants converge on the same stable display value.
    private static let canonicalAliases: [String: String] = {
        var aliases: [String: String] = [:]
        for (raw, canonical) in exactJapaneseMap {
            aliases[lookupKey(raw)] = canonical
            aliases[lookupKey(canonical)] = canonical
        }
        let englishAliases: [String: String] = [
            "hiphop": "Hip Hop",
            "hip-hop": "Hip Hop",
            "rnb": "R&B",
            "r and b": "R&B",
            "rhythm and blues": "R&B",
            "drum n bass": "Drum and Bass",
            "drum & bass": "Drum and Bass",
            "dnb": "Drum and Bass",
            "lofi": "Lo-Fi",
            "lo-fi": "Lo-Fi",
            "j pop": "J-Pop",
            "j-pop": "J-Pop",
            "jpop": "J-Pop",
            "k pop": "K-Pop",
            "k-pop": "K-Pop",
            "kpop": "K-Pop",
            "j rock": "J-Rock",
            "j-rock": "J-Rock",
            "smooth jazz": "Smooth Jazz",
            "smooth-jazz": "Smooth Jazz",
            "soul r&b": "Soul / R&B",
            "soul/r&b": "Soul / R&B",
            "soul-r&b": "Soul / R&B",
            "spoken word comedy": "Spoken Word / Comedy",
            "spoken word / comedy": "Spoken Word / Comedy"
        ]
        for (raw, canonical) in englishAliases {
            aliases[lookupKey(raw)] = canonical
            aliases[lookupKey(canonical)] = canonical
        }
        return aliases
    }()

    private static func stripJapaneseSuffixes(_ text: String) -> String {
        var str = text
        let suffixes = [
            "に分類された音楽", "に分頼された音楽", "に分頻された音楽", "に分された音楽",
            "に分類された", "に分頼された", "に分頻された", "に分された",
            "の音楽", "音楽"
        ]
        for suffix in suffixes {
            if str.hasSuffix(suffix) {
                str = String(str.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return str
    }

    public static func normalize(_ genre: String) -> String {
        var trimmed = MetadataTextNormalizer.trimLeadingAndTrailingSpaces(genre)
        guard !trimmed.isEmpty else { return "" }

        trimmed = stripJapaneseSuffixes(trimmed)

        if let mapped = canonicalAliases[lookupKey(trimmed)] {
            return mapped
        }

        var cleaned = normalizedSeparators(trimmed)

        cleaned = stripJapaneseSuffixes(cleaned)

        if let mapped = canonicalAliases[lookupKey(cleaned)] {
            return mapped
        }

        // Strip parenthetical Japanese descriptions: "AOR (ウェストコースト ロック)" → "AOR"
        cleaned = stripJapaneseParenthetical(cleaned)

        let cleanedTrimmed = cleaned.trimmingCharacters(in: .whitespaces)
        if let mapped = canonicalAliases[lookupKey(cleanedTrimmed)] {
            return mapped
        }

        if containsJapanese(cleanedTrimmed) {
            // Sort by longest key first to avoid partial replacements
            let sortedKeys = exactJapaneseMap.keys.sorted { $0.count > $1.count }
            var result = cleanedTrimmed
            for jp in sortedKeys {
                if result.contains(jp), let en = exactJapaneseMap[jp] {
                    result = result.replacingOccurrences(of: jp, with: en)
                }
            }
            result = normalizedSeparators(result).trimmingCharacters(in: .whitespaces)
            if let mapped = canonicalAliases[lookupKey(result)] {
                return mapped
            }
            // Never turn an unknown label into a misleading partial English
            // value. It remains visible until an explicit translation is added.
            guard !containsJapanese(result) else { return trimmed }
            return toTitleCase(result)
        }

        let titled = toTitleCase(cleanedTrimmed)
        return canonicalAliases[lookupKey(titled)] ?? titled
    }

    public static func lookupKey(_ genre: String) -> String {
        let folded = genre.precomposedStringWithCompatibilityMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0.value == 0x26
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func normalizedSeparators(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("://") || lower.contains("http:") || lower.contains("https:") || lower.contains("www.") {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var normalized = value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "・", with: " ")
            .replacingOccurrences(of: "／", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "＆", with: "&")
        for dash in ["-", "‐", "‑", "‒", "–", "—", "―", "−"] {
            normalized = normalized.replacingOccurrences(of: dash, with: " ")
        }
        return normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func containsJapanese(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF: true
            default: false
            }
        }
    }

    public static func toTitleCase(_ string: String) -> String {
        let words = string.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }

        let formattedWords = words.map { word -> String in
            if word.contains("/") {
                let parts = word.components(separatedBy: "/")
                return parts.map { formatSingleWord($0) }.joined(separator: "/")
            }
            return formatSingleWord(word)
        }

        var result = formattedWords.joined(separator: " ")

        result = result
            .replacingOccurrences(of: "J Pop", with: "J-Pop", options: .caseInsensitive)
            .replacingOccurrences(of: "J-pop", with: "J-Pop")
            .replacingOccurrences(of: "K Pop", with: "K-Pop", options: .caseInsensitive)
            .replacingOccurrences(of: "K-pop", with: "K-Pop")
            .replacingOccurrences(of: "J Rock", with: "J-Rock", options: .caseInsensitive)
            .replacingOccurrences(of: "J-rock", with: "J-Rock")
            .replacingOccurrences(of: "R & B", with: "R&B", options: .caseInsensitive)
            .replacingOccurrences(of: "R&b", with: "R&B")
            .replacingOccurrences(of: "R And B", with: "R&B", options: .caseInsensitive)
            .replacingOccurrences(of: "Hip-hop", with: "Hip-Hop")
            .replacingOccurrences(of: "Afro-cuban", with: "Afro-Cuban")

        return result
    }

    private static func formatSingleWord(_ word: String) -> String {
        let upper = word.uppercased()
        if acronyms.contains(upper) {
            return upper
        }

        if word.contains("-") {
            let subparts = word.components(separatedBy: "-")
            return subparts.map { formatSingleWord($0) }.joined(separator: "-")
        }

        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst().lowercased()
    }

    /// Strips parenthetical content that contains Japanese characters.
    /// "AOR (ウェストコースト ロック)" → "AOR"
    /// "Rock (ロック)" → "Rock"
    /// "Alternative Rock (indie)" → "Alternative Rock (indie)" (no Japanese → keep)
    private static func stripJapaneseParenthetical(_ string: String) -> String {
        var result = string
        // Handle both (…) patterns
        while let openRange = result.range(of: "(") {
            guard let closeRange = result[openRange.upperBound...].range(of: ")") else { break }
            let inside = String(result[openRange.upperBound..<closeRange.lowerBound])
            let insideHasJapanese = inside.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FAF: return true
                default: return false
                }
            }
            if insideHasJapanese {
                // Remove the parenthetical and any leading space before it
                var removeStart = openRange.lowerBound
                if removeStart > result.startIndex {
                    let before = result.index(before: removeStart)
                    if result[before] == " " {
                        removeStart = before
                    }
                }
                result.removeSubrange(removeStart...closeRange.lowerBound)
            } else {
                break // No Japanese in this parenthetical, stop
            }
        }
        return result
    }

}

public struct ReleaseTrack: Codable, Hashable, Sendable {
    public let discNumber: Int
    public let trackNumber: Int
    public let title: String
    public let artist: String
    
    public init(discNumber: Int, trackNumber: Int, title: String, artist: String) {
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.title = title
        self.artist = artist
    }
}

public struct MusicMetadataCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let releaseID: String
    public let recordingTitle: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let discNumber: Int
    public let trackNumber: Int
    public let mediumTrackCount: Int?
    public let releaseDate: String?
    public let releaseStatus: String?
    public let matchScore: Int

    public init(
        id: String,
        releaseID: String,
        recordingTitle: String,
        artist: String,
        album: String,
        albumArtist: String,
        discNumber: Int,
        trackNumber: Int,
        mediumTrackCount: Int?,
        releaseDate: String?,
        releaseStatus: String?,
        matchScore: Int
    ) {
        self.id = id
        self.releaseID = releaseID
        self.recordingTitle = recordingTitle
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.mediumTrackCount = mediumTrackCount
        self.releaseDate = releaseDate
        self.releaseStatus = releaseStatus
        self.matchScore = matchScore
    }
}

public enum MusicBrainzMetadataMatcher {
    public static func candidates(from data: Data, matching track: Track) throws -> [MusicMetadataCandidate] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        var candidates: [MusicMetadataCandidate] = []

        for recording in response.recordings {
            let recordingArtist = joinedCredit(recording.artistCredit)
            for release in recording.releases ?? [] {
                let albumArtist = joinedCredit(release.artistCredit)
                for medium in release.media ?? [] {
                    for releaseTrack in medium.tracks ?? [] {
                        let trackNumber = integerTrackNumber(releaseTrack.number)
                            ?? medium.trackOffset.map { $0 + 1 }
                        guard let trackNumber, trackNumber > 0, medium.position > 0 else { continue }
                        let duration = releaseTrack.length ?? recording.length
                        let score = matchScore(
                            track: track,
                            recordingTitle: recording.title,
                            recordingArtist: recordingArtist,
                            album: release.title,
                            durationMilliseconds: duration,
                            apiScore: recording.score,
                            status: release.status,
                            format: medium.format
                        )
                        candidates.append(MusicMetadataCandidate(
                            id: "\(release.id)-\(medium.position)-\(trackNumber)",
                            releaseID: release.id,
                            recordingTitle: recording.title,
                            artist: recordingArtist,
                            album: release.title,
                            albumArtist: albumArtist,
                            discNumber: medium.position,
                            trackNumber: trackNumber,
                            mediumTrackCount: medium.trackCount,
                            releaseDate: release.date,
                            releaseStatus: release.status,
                            matchScore: score
                        ))
                    }
                }
            }
        }

        var seen = Set<String>()
        return candidates
            .sorted {
                if $0.matchScore != $1.matchScore { return $0.matchScore > $1.matchScore }
                let leftDate = $0.releaseDate ?? "9999"
                let rightDate = $1.releaseDate ?? "9999"
                if leftDate != rightDate { return leftDate < rightDate }
                return $0.album.localizedStandardCompare($1.album) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
    }

    private static func matchScore(
        track: Track,
        recordingTitle: String,
        recordingArtist: String,
        album: String,
        durationMilliseconds: Int?,
        apiScore: Int?,
        status: String?,
        format: String?
    ) -> Int {
        var score = apiScore ?? 0
        if normalized(recordingTitle) == normalized(track.title) { score += 30 }
        if !track.artist.isEmpty, normalized(recordingArtist) == normalized(track.artist) { score += 30 }
        if !track.album.isEmpty, normalized(album) == normalized(track.album) { score += 40 }
        if let durationMilliseconds, track.duration > 0 {
            let difference = abs(Double(durationMilliseconds) / 1_000 - track.duration)
            if difference <= 2 { score += 20 }
            else if difference <= 5 { score += 12 }
            else if difference <= 15 { score += 4 }
        }
        if status?.localizedCaseInsensitiveCompare("Official") == .orderedSame { score += 10 }
        let normalizedFormat = format?.lowercased() ?? ""
        if normalizedFormat.contains("dvd") || normalizedFormat.contains("blu-ray") { score -= 15 }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func integerTrackNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        if let exact = Int(value) { return exact }
        let digits = value.drop { !$0.isNumber }.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func joinedCredit(_ credits: [ArtistCredit]?) -> String {
        credits?.map { credit in
            (credit.name ?? credit.artist?.name ?? "") + (credit.joinphrase ?? "")
        }.joined() ?? ""
    }

    private struct SearchResponse: Decodable {
        let recordings: [Recording]
    }

    private struct Recording: Decodable {
        let id: String
        let title: String
        let score: Int?
        let length: Int?
        let artistCredit: [ArtistCredit]?
        let releases: [Release]?

        enum CodingKeys: String, CodingKey {
            case id, title, score, length, releases
            case artistCredit = "artist-credit"
        }
    }

    private struct Release: Decodable {
        let id: String
        let title: String
        let status: String?
        let date: String?
        let artistCredit: [ArtistCredit]?
        let media: [Medium]?

        enum CodingKeys: String, CodingKey {
            case id, title, status, date, media
            case artistCredit = "artist-credit"
        }
    }

    private struct Medium: Decodable {
        let position: Int
        let format: String?
        let tracks: [ReleaseTrack]?
        let trackOffset: Int?
        let trackCount: Int?

        enum CodingKeys: String, CodingKey {
            case position, format
            case tracks = "track"
            case trackOffset = "track-offset"
            case trackCount = "track-count"
        }
    }

    private struct ReleaseTrack: Decodable {
        let number: String?
        let length: Int?
    }

    private struct ArtistCredit: Decodable {
        let name: String?
        let joinphrase: String?
        let artist: CreditedArtist?
    }

    private struct CreditedArtist: Decodable { let name: String }
}

public struct BatchMetadataChanges: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: String?
    public var isCompilation: Bool?
    public var discNumber: Int?
    public var changesDiscNumber: Bool
    public var totalDiscs: Int?
    public var changesTotalDiscs: Bool
    public var trackNumber: Int?
    public var changesTrackNumber: Bool
    public var incrementsTrackNumber: Bool
    public var totalTracks: Int?
    public var changesTotalTracks: Bool
    public var composer: String?
    public var lyricist: String?
    public var arranger: String?
    public var conductor: String?
    public var publisher: String?
    public var bpm: String?
    public var grouping: String?
    public var copyright: String?
    public var url: String?
    public var comment: String?
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        year: String? = nil,
        isCompilation: Bool? = nil,
        discNumber: Int? = nil,
        changesDiscNumber: Bool = false,
        totalDiscs: Int? = nil,
        changesTotalDiscs: Bool = false,
        trackNumber: Int? = nil,
        changesTrackNumber: Bool = false,
        incrementsTrackNumber: Bool = false,
        totalTracks: Int? = nil,
        changesTotalTracks: Bool = false,
        composer: String? = nil,
        lyricist: String? = nil,
        arranger: String? = nil,
        conductor: String? = nil,
        publisher: String? = nil,
        bpm: String? = nil,
        grouping: String? = nil,
        copyright: String? = nil,
        url: String? = nil,
        comment: String? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.year = year
        self.isCompilation = isCompilation
        self.discNumber = discNumber
        self.changesDiscNumber = changesDiscNumber
        self.totalDiscs = totalDiscs
        self.changesTotalDiscs = changesTotalDiscs
        self.trackNumber = trackNumber
        self.changesTrackNumber = changesTrackNumber
        self.incrementsTrackNumber = incrementsTrackNumber
        self.totalTracks = totalTracks
        self.changesTotalTracks = changesTotalTracks
        self.composer = composer
        self.lyricist = lyricist
        self.arranger = arranger
        self.conductor = conductor
        self.publisher = publisher
        self.bpm = bpm
        self.grouping = grouping
        self.copyright = copyright
        self.url = url
        self.comment = comment
        self.artworkData = artworkData
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil && genre == nil && year == nil && isCompilation == nil &&
            comment == nil && !changesDiscNumber && !changesTotalDiscs && !changesTrackNumber && !changesTotalTracks &&
            composer == nil && lyricist == nil && arranger == nil && conductor == nil && publisher == nil &&
            bpm == nil && grouping == nil && copyright == nil && url == nil && artworkData == nil
    }

    public func applying(to track: Track, offset: Int = 0) -> TrackMetadataEdit {
        var edit = TrackMetadataEdit(track: track)
        if let title { edit.title = title }
        if let artist { edit.artist = artist }
        if let album { edit.album = album }
        if let albumArtist { edit.albumArtist = albumArtist }
        if let genre { edit.genre = genre }
        if let year { edit.year = year }
        if let isCompilation { edit.isCompilation = isCompilation }
        if let composer { edit.composer = composer }
        if let lyricist { edit.lyricist = lyricist }
        if let arranger { edit.arranger = arranger }
        if let conductor { edit.conductor = conductor }
        if let publisher { edit.publisher = publisher }
        if let bpm { edit.bpm = bpm }
        if let grouping { edit.grouping = grouping }
        if let copyright { edit.copyright = copyright }
        if let url { edit.url = url }
        if let comment { edit.comment = comment }
        if changesDiscNumber { edit.discNumber = discNumber }
        if changesTotalDiscs { edit.totalDiscs = totalDiscs }
        if changesTrackNumber {
            if incrementsTrackNumber, let base = trackNumber {
                edit.trackNumber = base + offset
            } else {
                edit.trackNumber = trackNumber
            }
        }
        if changesTotalTracks { edit.totalTracks = totalTracks }
        if let artworkData { edit.artworkData = artworkData }
        return edit
    }
}

public enum ImportState: String, Sendable, Codable {
    case staged
    case moved
    case keptLocal
    case failed
}

public struct PendingImport: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let localPath: String
    public let filename: String
    public let state: ImportState
    public let createdAt: Date
    public let errorMessage: String?
}

public struct StorageDestination: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let path: String
    public let bookmark: Data
    public let isPrimary: Bool
    public let isAvailable: Bool
}

public enum LibraryDifferenceKind: String, Sendable, Codable {
    case registeredButMissing
    case onStorageButUnregistered
}

public struct LibraryDifference: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let rootID: Int64
    public let relativePath: String
    public let kind: LibraryDifferenceKind
}

public struct CachedLyrics: Sendable, Hashable {
    public let trackID: Int64
    public let provider: String
    public let plainLyrics: String
    public let syncedLyrics: String?
    public let updatedAt: Date
}

public struct TrackPage: Sendable {
    public let tracks: [Track]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int

    public var hasPrevious: Bool { offset > 0 }
    public var hasNext: Bool { offset + tracks.count < totalCount }
}

public struct Facet: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct GenreKnowledge: Equatable, Sendable {
    public let rawGenre: String
    public let canonicalName: String
    public let summaryJapanese: String
    public let summaryEnglish: String
    public let sourceTitle: String
    public let sourceURL: URL
    public let resolvedAt: Date

    public init(
        rawGenre: String,
        canonicalName: String,
        summaryJapanese: String,
        summaryEnglish: String,
        sourceTitle: String,
        sourceURL: URL,
        resolvedAt: Date
    ) {
        self.rawGenre = rawGenre
        self.canonicalName = canonicalName
        self.summaryJapanese = summaryJapanese
        self.summaryEnglish = summaryEnglish
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.resolvedAt = resolvedAt
    }
}

public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let year: String
    public let trackCount: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        artist: String,
        year: String = "",
        trackCount: Int
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.year = year
        self.trackCount = trackCount
    }
}

public struct AlbumSummaryPage: Sendable {
    public let albums: [AlbumSummary]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct ArtistSummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let genre: String
    public let albumCount: Int
    public let trackCount: Int
    public var id: String { name }

    public init(name: String, genre: String = "", albumCount: Int, trackCount: Int) {
        self.name = name
        self.genre = genre
        self.albumCount = albumCount
        self.trackCount = trackCount
    }
}

public struct ArtistSummaryPage: Sendable {
    public let artists: [ArtistSummary]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct LibraryStorageSummary: Equatable, Sendable {
    public let totalBytes: Int64
    public let absoluteRootPaths: [String]

    public init(totalBytes: Int64, absoluteRootPaths: [String]) {
        self.totalBytes = totalBytes
        self.absoluteRootPaths = absoluteRootPaths
    }

    public static let empty = LibraryStorageSummary(totalBytes: 0, absoluteRootPaths: [])
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let itemCount: Int
}

public struct ScanRoot: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let displayName: String
    public let bookmark: Data
    public let volumeUUID: String?
    public let lastKnownPath: String
    public let isAvailable: Bool
}

public enum ScanState: String, Sendable {
    case running
    case paused
    case cancelled
    case failed
    case completed
}

public struct ScanProgress: Sendable {
    public let sessionID: Int64
    public let state: ScanState
    public let discovered: Int
    public let processed: Int
    public let insertedOrUpdated: Int
    public let skipped: Int
    public let errors: Int
    public let tracksPerSecond: Double
    public let currentPath: String

    public static let idle = ScanProgress(
        sessionID: 0,
        state: .completed,
        discovered: 0,
        processed: 0,
        insertedOrUpdated: 0,
        skipped: 0,
        errors: 0,
        tracksPerSecond: 0,
        currentPath: ""
    )
}

public struct TrackImport: Sendable {
    public let identityKey: String
    public let fileResourceID: String?
    public let track: Track

    public init(identityKey: String, fileResourceID: String?, track: Track) {
        self.identityKey = identityKey
        self.fileResourceID = fileResourceID
        self.track = track
    }
}

public struct SyntheticBenchmarkResult: Codable, Sendable {
    public let requestedCount: Int
    public let insertedCount: Int
    public let insertSeconds: Double
    public let searchMilliseconds: Double
    public let pageMilliseconds: Double
    public let deepOffsetMilliseconds: Double
    public let playlist100kSeconds: Double
    public let playlistPageMilliseconds: Double
    public let databaseBytes: Int64
    public let generatedAt: Date
}

public enum MassiveMusicError: LocalizedError, Sendable {
    case invalidPageSize
    case scanRootUnavailable
    case bookmarkResolutionFailed
    case trackUnavailable
    case unsupportedAudioFormat(String)
    case insufficientStorageSpace(requiredBytes: Int64, availableBytes: Int64)
    case metadataWriteFailed(String)
    case invalidPlaylistName

    public var errorDescription: String? {
        switch self {
        case .invalidPageSize: "ページサイズが不正です。"
        case .scanRootUnavailable: "ドライブが接続されていません。"
        case .bookmarkResolutionFailed: "音楽フォルダへのアクセス権を復元できません。"
        case .trackUnavailable: "曲ファイルを利用できません。"
        case let .unsupportedAudioFormat(ext): "未対応の音声形式です: \(ext)"
        case let .insufficientStorageSpace(requiredBytes, availableBytes):
            "保管先の空き容量が不足しています（必要: \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file))、空き: \(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file))）。曲ファイルは変更していません。"
        case let .metadataWriteFailed(reason): "曲情報を書き込めませんでした: \(reason)"
        case .invalidPlaylistName: "プレイリスト名を入力してください。"
        }
    }

    public var isRepairableID3Damage: Bool {
        guard case let .metadataWriteFailed(reason) = self else { return false }
        return reason.contains("ID3フレーム") || reason.contains("ID3タグ") || reason.contains("ID3v2")
    }

    public var requiresID3v23Conversion: Bool {
        guard case let .metadataWriteFailed(reason) = self else { return false }
        return reason.contains("ID3v2.2以前")
    }

    public var isInsufficientStorageSpace: Bool {
        guard case .insufficientStorageSpace = self else { return false }
        return true
    }
}

public struct ListeningInsights: Sendable {
    public struct TopTrack: Identifiable, Hashable, Sendable {
        public var id: Int64 { track.id }
        public let track: Track
        public let playCount: Int

        public init(track: Track, playCount: Int) {
            self.track = track
            self.playCount = playCount
        }
    }

    public struct TopEntity: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        public let count: Int
        public let subtext: String

        public init(name: String, count: Int, subtext: String) {
            self.name = name
            self.count = count
            self.subtext = subtext
        }
    }

    public struct TimeOfDayVibe: Identifiable, Hashable, Sendable {
        public var id: String { period }
        public let period: String       // "morning", "afternoon", "evening", "night"
        public let title: String        // "朝 (06:00〜12:00)", etc.
        public let icon: String         // "sun.horizon", "sun.max", "moon.stars", "sparkles"
        public let topGenre: String
        public let playCount: Int
        public let sampleTracks: [Track]
        public let topTracks: [TopTrack]

        public init(
            period: String,
            title: String,
            icon: String,
            topGenre: String,
            playCount: Int,
            sampleTracks: [Track],
            topTracks: [TopTrack] = []
        ) {
            self.period = period
            self.title = title
            self.icon = icon
            self.topGenre = topGenre
            self.playCount = playCount
            self.sampleTracks = sampleTracks
            self.topTracks = topTracks
        }
    }

    public struct GenreSlice: Identifiable, Hashable, Sendable {
        public var id: String { genre }
        public let genre: String
        public let count: Int
        public let percentage: Double
        public let topTracks: [TopTrack]

        public init(genre: String, count: Int, percentage: Double, topTracks: [TopTrack] = []) {
            self.genre = genre
            self.count = count
            self.percentage = percentage
            self.topTracks = topTracks
        }
    }

    public let totalPlayedCount: Int
    public let topTracks: [TopTrack]
    public let topArtists: [TopEntity]
    public let topGenres: [GenreSlice]
    public let timeOfDayVibes: [TimeOfDayVibe]
    public let rediscoveryTracks: [Track]
    public let currentVibeTracks: [Track]

    public init(
        totalPlayedCount: Int,
        topTracks: [TopTrack],
        topArtists: [TopEntity],
        topGenres: [GenreSlice],
        timeOfDayVibes: [TimeOfDayVibe],
        rediscoveryTracks: [Track],
        currentVibeTracks: [Track]
    ) {
        self.totalPlayedCount = totalPlayedCount
        self.topTracks = topTracks
        self.topArtists = topArtists
        self.topGenres = topGenres
        self.timeOfDayVibes = timeOfDayVibes
        self.rediscoveryTracks = rediscoveryTracks
        self.currentVibeTracks = currentVibeTracks
    }

    public static let empty = ListeningInsights(
        totalPlayedCount: 0,
        topTracks: [],
        topArtists: [],
        topGenres: [],
        timeOfDayVibes: [],
        rediscoveryTracks: [],
        currentVibeTracks: []
    )
}

public enum CloudSyncProvider: String, CaseIterable, Identifiable, Sendable {
    case iCloud = "iCloud"
    case dropbox = "dropbox"
    case googleDrive = "googleDrive"
    case custom = "custom"

    public var id: String { rawValue }

    public func title(isJapanese: Bool) -> String {
        switch self {
        case .iCloud: return isJapanese ? "iCloud Drive (iPhone / iPad用)" : "iCloud Drive (for iPhone / iPad)"
        case .dropbox: return "Dropbox"
        case .googleDrive: return "Google Drive"
        case .custom: return isJapanese ? "カスタム共有フォルダ…" : "Custom Shared Folder…"
        }
    }

    public var icon: String {
        switch self {
        case .iCloud: return "icloud.fill"
        case .dropbox: return "shippingbox.fill"
        case .googleDrive: return "externaldrive.fill.badge.icloud"
        case .custom: return "folder.fill"
        }
    }
}

