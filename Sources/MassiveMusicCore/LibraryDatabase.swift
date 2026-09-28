import Foundation
import GRDB

public final class LibraryDatabase: @unchecked Sendable {
    public static let defaultPageSize = 200
    public static let scanCommitSize = 750
    public static let playlistCommitSize = 1_000

    private let pool: DatabasePool
    public let databaseURL: URL

    public init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.maximumReaderCount = 6
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA cache_size = -32768")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            db.add(function: DatabaseFunction("REGEXP", argumentCount: 2, pure: true) { values in
                guard let pattern = String.fromDatabaseValue(values[0]),
                      let text = String.fromDatabaseValue(values[1]) else {
                    return false
                }
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    return false
                }
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            })
        }
        pool = try DatabasePool(path: url.path, configuration: configuration)
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        try Self.makeMigrator().migrate(pool)
    }

    public static func applicationSupportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let defaultURL = base.appending(path: "MassiveMusic", directoryHint: .isDirectory)
            .appending(path: "MassiveMusic.sqlite")
        let containerURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.local.MassiveMusic/Data/Library/Application Support/MassiveMusic", directoryHint: .isDirectory)
            .appending(path: "MassiveMusic.sqlite")
        return preferredApplicationSupportDatabase(
            defaultURL: defaultURL,
            containerURL: containerURL,
            containerDatabaseExists: FileManager.default.fileExists(atPath: containerURL.path)
        )
    }

    public static func preferredApplicationSupportDatabase(
        defaultURL: URL,
        containerURL: URL,
        containerDatabaseExists: Bool
    ) -> URL {
        guard defaultURL.standardizedFileURL != containerURL.standardizedFileURL,
              containerDatabaseExists else { return defaultURL }
        return containerURL
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: Schema.initial)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [1, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v2_library_experience") { db in
            try db.execute(sql: Schema.libraryExperience)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [2, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v3_track_editing_and_exclusions") { db in
            try db.execute(sql: Schema.trackEditingAndExclusions)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [3, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v4_metadata_diagnostics") { db in
            try db.execute(sql: Schema.metadataDiagnostics)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [4, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v5_play_queue") { db in
            try db.execute(sql: Schema.playQueue)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [5, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v6_pinned_offline_cache") { db in
            try db.execute(sql: Schema.pinnedOfflineCache)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [6, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v7_library_activity_log") { db in
            try db.execute(sql: Schema.libraryActivityLog)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [7, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v8_compilation_tag") { db in
            try db.execute(sql: Schema.compilationTag)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [8, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v9_pending_metadata_edits") { db in
            try db.execute(sql: Schema.pendingMetadataEdits)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [9, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v10_musicbrainz_autofill_attempts") { db in
            try db.execute(sql: Schema.musicBrainzAutoFillAttempts)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [10, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v11_year_tag") { db in
            try db.execute(sql: Schema.yearTag)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [11, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v12_genre_knowledge") { db in
            try db.execute(sql: Schema.genreKnowledge)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [12, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v14_comment_tag") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(tracks)")
            let hasComment = columns.contains { row in
                (row["name"] as? String)?.lowercased() == "comment"
            }
            if !hasComment {
                try db.execute(sql: Schema.commentTag)
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [14, Date().timeIntervalSince1970]
            )
        }
        return migrator
    }

    public func journalMode() throws -> String {
        try pool.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
        }
    }

    public func schemaVersion() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
        }
    }

    public func trackCount(availableOnly: Bool = false) throws -> Int {
        try pool.read { db in
            let suffix = availableOnly ? " WHERE is_available = 1" : ""
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks\(suffix)") ?? 0
        }
    }

    public func favoriteTrackCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_favorite = 1") ?? 0
        }
    }

    public func recentlyAddedTrackCount() throws -> Int {
        try trackCount()
    }

    public func recentlyPlayedTrackCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE last_played_at IS NOT NULL AND is_available = 1") ?? 0
        }
    }

    public func librarySidebarCounts() throws -> (
        tracks: Int,
        albums: Int,
        artists: Int,
        genres: Int,
        folders: Int,
        cached: Int,
        cachedBytes: Int64
    ) {
        try pool.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    (SELECT COUNT(*) FROM tracks) AS tracks,
                    (SELECT COUNT(*) FROM (
                        SELECT 1 FROM tracks
                        WHERE is_available = 1 AND album <> ''
                        GROUP BY album COLLATE NOCASE, artist COLLATE NOCASE
                    )) AS albums,
                    (SELECT COUNT(DISTINCT artist COLLATE NOCASE) FROM tracks
                        WHERE is_available = 1 AND artist <> '') AS artists,
                    0 AS genres,
                    (SELECT COUNT(*) FROM (
                        SELECT 1 FROM tracks
                        WHERE is_available = 1 AND relative_path <> ''
                        GROUP BY CASE
                            WHEN instr(relative_path, '/') > 0
                            THEN substr(relative_path, 1, instr(relative_path, '/') - 1)
                            ELSE '/'
                        END COLLATE NOCASE
                    )) AS folders,
                    (SELECT COUNT(*) FROM local_cache) AS cached,
                    (SELECT COALESCE(SUM(file_size), 0) FROM local_cache) AS cached_bytes
                """)
            let rawGenres = try String.fetchAll(db, sql: """
                SELECT genre FROM tracks
                WHERE is_available = 1 AND trim(genre) <> ''
                GROUP BY genre COLLATE NOCASE
                """)
            let canonicalGenreCount = Set(rawGenres.map(GenreNormalizer.normalize)).count
            return (
                tracks: row?["tracks"] ?? 0,
                albums: row?["albums"] ?? 0,
                artists: row?["artists"] ?? 0,
                genres: canonicalGenreCount,
                folders: row?["folders"] ?? 0,
                cached: row?["cached"] ?? 0,
                cachedBytes: row?["cached_bytes"] ?? 0
            )
        }
    }

    public func unavailableTrackCount() throws -> Int {
        try pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 0") ?? 0 }
    }

    public func activityLogPage(
        kinds: Set<LibraryActivityKind> = [],
        query: String = "",
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> LibraryActivityPage {
        guard (1...50_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            var predicates: [String] = []
            var arguments: StatementArguments = []
            if !kinds.isEmpty {
                let orderedKinds = kinds.sorted { $0.rawValue < $1.rawValue }
                predicates.append("kind IN (\(Array(repeating: "?", count: orderedKinds.count).joined(separator: ",")))")
                arguments += StatementArguments(orderedKinds.map(\.rawValue))
            }
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                predicates.append("(filename LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\' OR relative_path LIKE ? ESCAPE '\\' OR absolute_path LIKE ? ESCAPE '\\')")
                let escaped = trimmedQuery
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let pattern = "%\(escaped)%"
                arguments += [pattern, pattern, pattern, pattern, pattern, pattern]
            }
            let whereSQL = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM library_activity_log\(whereSQL)", arguments: arguments
            ) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM library_activity_log\(whereSQL) ORDER BY occurred_at DESC, id DESC LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return LibraryActivityPage(
                events: rows.map(Self.decodeActivityEvent), offset: safeOffset,
                limit: limit, totalCount: total
            )
        }
    }

    public func recordTrackActivity(
        trackID: Int64,
        kind: LibraryActivityKind,
        absolutePath: String
    ) throws {
        try pool.write { db in
            guard let trackRow = try Row.fetchOne(
                db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [trackID]
            ) else { return }
            try Self.insertActivity(
                db: db, kind: kind, trackRow: trackRow, changes: [],
                absolutePathOverride: absolutePath
            )
            try Self.pruneActivityLog(db: db)
        }
    }

    public func track(id: Int64) throws -> Track? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decodeTrack(row)
        }
    }

    public func protectedTracksForCaching(afterID: Int64, limit: Int = 50) throws -> [Track] {
        guard (1...500).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT t.* FROM tracks t
                    WHERE t.id > ?
                      AND t.is_available = 1
                      AND (
                          t.is_favorite = 1
                          OR EXISTS (
                              SELECT 1 FROM playlist_items i WHERE i.track_id = t.id
                          )
                      )
                    ORDER BY t.id
                    LIMIT ?
                    """,
                arguments: [afterID, limit]
            ).map(Self.decodeTrack)
        }
    }

    public func setTrackAvailability(id: Int64, isAvailable: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE tracks SET is_available = ? WHERE id = ?",
                arguments: [isAvailable, id]
            )
        }
    }

    /// Returns a bounded keyset page so maintenance never materializes the
    /// entire library and remains stable while each repaired title is updated.
    public func tracksWithLeadingTitleSpaces(afterID: Int64, limit: Int = defaultPageSize) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks
                    WHERE id > ? AND is_available = 1
                      AND substr(title, 1, 1) IN (' ', '　')
                    ORDER BY id LIMIT ?
                    """,
                arguments: [afterID, limit]
            )
            return rows.map(Self.decodeTrack)
        }
    }

    /// Streams a bounded ID-ordered maintenance page. Width normalization is
    /// evaluated in Swift because SQLite GLOB ranges produce Unicode false
    /// positives for this data set.
    public func tracksForWidthNormalization(afterID: Int64, limit: Int = defaultPageSize) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM tracks WHERE id > ? AND is_available = 1 ORDER BY id LIMIT ?",
                arguments: [afterID, limit]
            )
            return rows.map(Self.decodeTrack)
        }
    }

    /// Returns all tracks (regardless of availability) for genre normalization.
    /// Works even when the SSD is disconnected since it reads from the local DB cache.
    public func tracksForGenreNormalization(afterID: Int64, limit: Int = defaultPageSize) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks WHERE id > ?
                      AND trim(genre) != '' AND genre != '未判定' AND lower(trim(genre)) != 'unknown'
                    ORDER BY id LIMIT ?
                    """,
                arguments: [afterID, limit]
            )
            return rows.map(Self.decodeTrack)
        }
    }

    public func saveGenreKnowledge(_ knowledge: GenreKnowledge) throws {
        let rawKey = GenreNormalizer.lookupKey(knowledge.rawGenre)
        guard !rawKey.isEmpty else {
            throw MassiveMusicError.metadataWriteFailed("Genre knowledge requires a non-empty raw label")
        }
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO genre_knowledge(
                        raw_key, raw_genre, canonical_name, summary_ja, summary_en,
                        source_title, source_url, resolved_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(raw_key) DO UPDATE SET
                        raw_genre = excluded.raw_genre,
                        canonical_name = excluded.canonical_name,
                        summary_ja = excluded.summary_ja,
                        summary_en = excluded.summary_en,
                        source_title = excluded.source_title,
                        source_url = excluded.source_url,
                        resolved_at = excluded.resolved_at
                    """,
                arguments: [
                    rawKey, knowledge.rawGenre, knowledge.canonicalName,
                    knowledge.summaryJapanese, knowledge.summaryEnglish,
                    knowledge.sourceTitle, knowledge.sourceURL.absoluteString,
                    knowledge.resolvedAt.timeIntervalSince1970
                ]
            )
        }
    }

    public func genreKnowledge(forRawGenre rawGenre: String) throws -> GenreKnowledge? {
        let rawKey = GenreNormalizer.lookupKey(rawGenre)
        guard !rawKey.isEmpty else { return nil }
        return try pool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM genre_knowledge WHERE raw_key = ?",
                arguments: [rawKey]
            ).flatMap(Self.decodeGenreKnowledge)
        }
    }

    public func genreKnowledge(forCanonicalName canonicalName: String) throws -> GenreKnowledge? {
        try pool.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM genre_knowledge
                    WHERE canonical_name = ? COLLATE NOCASE
                    ORDER BY resolved_at DESC LIMIT 1
                    """,
                arguments: [canonicalName]
            ).flatMap(Self.decodeGenreKnowledge)
        }
    }

    public func allGenreKnowledge() throws -> [GenreKnowledge] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM genre_knowledge ORDER BY canonical_name COLLATE NOCASE, raw_key"
            ).compactMap(Self.decodeGenreKnowledge)
        }
    }

    private static func decodeGenreKnowledge(_ row: Row) -> GenreKnowledge? {
        guard let sourceURL = URL(string: row["source_url"] as String) else { return nil }
        return GenreKnowledge(
            rawGenre: row["raw_genre"],
            canonicalName: row["canonical_name"],
            summaryJapanese: row["summary_ja"],
            summaryEnglish: row["summary_en"],
            sourceTitle: row["source_title"],
            sourceURL: sourceURL,
            resolvedAt: Date(timeIntervalSince1970: row["resolved_at"])
        )
    }

    public func mp3TracksForID3Migration(afterID: Int64, limit: Int = defaultPageSize) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM tracks WHERE id > ? AND is_available = 1 AND lower(format) = 'mp3' ORDER BY id LIMIT ?",
                arguments: [afterID, limit]
            )
            return rows.map(Self.decodeTrack)
        }
    }

    public func isExcluded(identityKey: String) throws -> Bool {
        try pool.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                arguments: [identityKey]
            ) ?? false
        }
    }

    @discardableResult
    public func removeTrackFromLibrary(id: Int64, fileWasTrashed: Bool) throws -> Bool {
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE id = ?",
                arguments: [id]
            ) else { return false }
            try Self.insertActivity(
                db: db, kind: fileWasTrashed ? .movedToTrash : .removedFromLibrary,
                trackRow: row, changes: []
            )
            try db.execute(
                sql: """
                    INSERT INTO excluded_tracks(identity_key, root_id, relative_path, removed_at, file_was_trashed)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(identity_key) DO UPDATE SET removed_at = excluded.removed_at,
                        file_was_trashed = excluded.file_was_trashed
                    """,
                arguments: [row["identity_key"], row["root_id"], row["relative_path"], Date().timeIntervalSince1970, fileWasTrashed]
            )
            try db.execute(sql: "DELETE FROM tracks WHERE id = ?", arguments: [id])
            let removed = db.changesCount > 0
            try Self.pruneActivityLog(db: db)
            return removed
        }
    }

    public func updateTrackMetadata(
        id: Int64,
        edit: TrackMetadataEdit,
        fileSize: Int64,
        modifiedAt: Date
    ) throws {
        var normalizedEdit = edit
        normalizedEdit.genre = GenreNormalizer.normalize(edit.genre)
        try pool.write { db in
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id])
            try db.execute(
                sql: """
                    UPDATE tracks SET title = ?, artist = ?, album = ?, album_artist = ?, genre = ?, year = ?, is_compilation = ?,
                        disc_number = ?, track_number = ?, comment = ?, file_size = ?, modified_at = ?,
                        has_artwork = CASE WHEN ? THEN 1 ELSE has_artwork END
                    WHERE id = ?
                    """,
                arguments: [normalizedEdit.title, normalizedEdit.artist, normalizedEdit.album, normalizedEdit.albumArtist,
                            normalizedEdit.genre, normalizedEdit.year, normalizedEdit.isCompilation, normalizedEdit.discNumber,
                            normalizedEdit.trackNumber, normalizedEdit.comment, fileSize, modifiedAt.timeIntervalSince1970,
                            normalizedEdit.artworkData != nil, id]
            )
            if let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) {
                try Self.refreshMetadataVariationCandidates(db: db, previous: previous, updated: updated)
                let changes = Self.activityChanges(from: previous, to: updated)
                if !changes.isEmpty {
                    try Self.insertActivity(db: db, kind: .metadataChanged, trackRow: updated, changes: changes)
                } else {
                    try Self.insertActivity(db: db, kind: .fileModified, trackRow: updated, changes: [])
                }
                try Self.pruneActivityLog(db: db)
            }
        }
    }

    public func queuePendingMetadataEdit(
        id: Int64,
        edit: TrackMetadataEdit,
        fileSize: Int64,
        modifiedAt: Date
    ) throws {
        var normalizedEdit = edit
        normalizedEdit.genre = GenreNormalizer.normalize(edit.genre)
        let payload = try JSONEncoder().encode(normalizedEdit)
        let payloadJSON = String(decoding: payload, as: UTF8.self)
        try pool.write { db in
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id])
            try db.execute(
                sql: """
                    UPDATE tracks SET title = ?, artist = ?, album = ?, album_artist = ?, genre = ?, year = ?, is_compilation = ?,
                        disc_number = ?, track_number = ?, comment = ?, file_size = ?, modified_at = ?,
                        has_artwork = CASE WHEN ? THEN 1 ELSE has_artwork END
                    WHERE id = ?
                    """,
                arguments: [normalizedEdit.title, normalizedEdit.artist, normalizedEdit.album, normalizedEdit.albumArtist,
                            normalizedEdit.genre, normalizedEdit.year, normalizedEdit.isCompilation,
                            normalizedEdit.discNumber, normalizedEdit.trackNumber, normalizedEdit.comment, fileSize, modifiedAt.timeIntervalSince1970,
                            normalizedEdit.artworkData != nil, id]
            )
            try db.execute(
                sql: """
                    INSERT INTO pending_metadata_edits(track_id, edit_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(track_id) DO UPDATE SET
                        edit_json = excluded.edit_json,
                        updated_at = excluded.updated_at
                    """,
                arguments: [id, payloadJSON, Date().timeIntervalSince1970]
            )
            if let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) {
                try Self.refreshMetadataVariationCandidates(db: db, previous: previous, updated: updated)
                let changes = Self.activityChanges(from: previous, to: updated)
                if !changes.isEmpty {
                    try Self.insertActivity(db: db, kind: .metadataChanged, trackRow: updated, changes: changes)
                    try Self.pruneActivityLog(db: db)
                }
            }
        }
    }

    public func pendingMetadataEdits(limit: Int = 100) throws -> [PendingMetadataEdit] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, track_id, edit_json, updated_at
                    FROM pending_metadata_edits
                    ORDER BY updated_at ASC, id ASC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).compactMap { row in
                let json: String = row["edit_json"]
                guard let data = json.data(using: .utf8),
                      let edit = try? JSONDecoder().decode(TrackMetadataEdit.self, from: data) else {
                    return nil
                }
                return PendingMetadataEdit(
                    id: row["id"],
                    trackID: row["track_id"],
                    edit: edit,
                    updatedAt: Date(timeIntervalSince1970: row["updated_at"])
                )
            }
        }
    }

    public func removePendingMetadataEdit(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM pending_metadata_edits WHERE id = ?", arguments: [id])
        }
    }

    /// Records an automatically inferred genre without touching the audio file.
    /// This keeps playback responsive and avoids prompting for an external drive
    /// merely because a song started playing.
    public func updateTrackGenre(id: Int64, genre: String) throws {
        let normalized = GenreNormalizer.normalize(genre)
        guard !normalized.isEmpty else { return }
        try pool.write { db in
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id])
            try db.execute(sql: "UPDATE tracks SET genre = ? WHERE id = ?", arguments: [normalized, id])
            if let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) {
                let changes = Self.activityChanges(from: previous, to: updated)
                if !changes.isEmpty {
                    try Self.insertActivity(db: db, kind: .metadataChanged, trackRow: updated, changes: changes)
                    try Self.pruneActivityLog(db: db)
                }
            }
        }
    }

    public func updateTrackYear(id: Int64, year: String) throws {
        let normalized = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try pool.write { db in
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id])
            try db.execute(sql: "UPDATE tracks SET year = ? WHERE id = ?", arguments: [normalized, id])
            if let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) {
                let changes = Self.activityChanges(from: previous, to: updated)
                if !changes.isEmpty {
                    try Self.insertActivity(db: db, kind: .metadataChanged, trackRow: updated, changes: changes)
                    try Self.pruneActivityLog(db: db)
                }
            }
        }
    }

    public func missingYearTrackCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM tracks
                WHERE is_available = 1
                  AND (trim(year) = '' OR year = '0' OR year IS NULL)
                """) ?? 0
        }
    }

    public func tracksMissingYear(
        afterID: Int64,
        limit: Int = defaultPageSize
    ) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE id > ? AND is_available = 1
                  AND (trim(year) = '' OR year = '0' OR year IS NULL)
                ORDER BY id ASC
                LIMIT ?
                """, arguments: [afterID, limit]).map(Self.decodeTrack)
        }
    }

    public func missingGenreTrackCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM tracks
                WHERE is_available = 1
                  AND (trim(genre) = '' OR genre = '未判定' OR lower(trim(genre)) = 'unknown')
                """) ?? 0
        }
    }

    public func tracksMissingGenre(
        afterID: Int64,
        limit: Int = defaultPageSize
    ) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE id > ? AND is_available = 1
                  AND (trim(genre) = '' OR genre = '未判定' OR lower(trim(genre)) = 'unknown')
                ORDER BY id ASC
                LIMIT ?
                """, arguments: [afterID, limit]).map(Self.decodeTrack)
        }
    }

    /// Reuses a genre already assigned to the same album and credited artist.
    /// A matching album is required so an artist's genre cannot be spread across
    /// unrelated releases.
    public func consensusGenreForAlbum(track: Track) throws -> String? {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !album.isEmpty else { return nil }
        let creditedArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            : track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !creditedArtist.isEmpty else { return nil }

        return try pool.read { db in
            let rawGenre = try String.fetchOne(db, sql: """
                SELECT genre
                FROM tracks
                WHERE id <> ?
                  AND is_available = 1
                  AND album = ? COLLATE NOCASE
                  AND COALESCE(NULLIF(trim(album_artist), ''), trim(artist)) = ? COLLATE NOCASE
                  AND trim(genre) <> ''
                  AND genre <> '未判定'
                  AND lower(trim(genre)) <> 'unknown'
                GROUP BY genre COLLATE NOCASE
                ORDER BY COUNT(*) DESC, genre COLLATE NOCASE ASC
                LIMIT 1
                """, arguments: [track.id, album, creditedArtist])
            return rawGenre.map(GenreNormalizer.normalize)
        }
    }

    public func albumTrackCount(album: String, artist: String) throws -> Int {
        try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM tracks
                    WHERE album = ? COLLATE NOCASE AND artist = ? COLLATE NOCASE
                    """,
                arguments: [album, artist]
            ) ?? 0
        }
    }

    public func representativeArtworkTrack(album: String, artist: String) throws -> Track? {
        try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1
                      AND has_artwork = 1
                      AND album = ? COLLATE NOCASE
                      AND COALESCE(NULLIF(album_artist, ''), artist) = ? COLLATE NOCASE
                    ORDER BY COALESCE(disc_number, 0), COALESCE(track_number, 0), id
                    LIMIT 1
                    """,
                arguments: [album, artist]
            )
            return row.map(Self.decodeTrack)
        }
    }

    public func allTracksMissingNumbers() throws -> [Track] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM tracks WHERE track_number IS NULL OR disc_number IS NULL"
            )
            return rows.map(Self.decodeTrack)
        }
    }

    public func musicBrainzAutoFillAttempts() throws -> [String: MusicBrainzAutoFillAttempt] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM musicbrainz_autofill_attempts")
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let attempt = Self.decodeMusicBrainzAutoFillAttempt(row) else { return nil }
                return (attempt.albumKey, attempt)
            })
        }
    }

    public func musicBrainzAutoFillAttempt(albumKey: String) throws -> MusicBrainzAutoFillAttempt? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM musicbrainz_autofill_attempts WHERE album_key = ?",
                arguments: [albumKey]
            ) else { return nil }
            return Self.decodeMusicBrainzAutoFillAttempt(row)
        }
    }

    public func recordMusicBrainzAutoFillAttempt(
        albumKey: String,
        fingerprint: String,
        artist: String,
        album: String,
        status: MusicBrainzAutoFillStatus,
        retryAfter: Date?,
        lastError: String?,
        attemptedAt: Date = Date()
    ) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO musicbrainz_autofill_attempts(
                        album_key, fingerprint, artist, album, status, attempt_count,
                        retry_after, last_error, attempted_at
                    ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
                    ON CONFLICT(album_key) DO UPDATE SET
                        fingerprint = excluded.fingerprint,
                        artist = excluded.artist,
                        album = excluded.album,
                        status = excluded.status,
                        attempt_count = CASE
                            WHEN musicbrainz_autofill_attempts.fingerprint = excluded.fingerprint
                            THEN musicbrainz_autofill_attempts.attempt_count + 1
                            ELSE 1
                        END,
                        retry_after = excluded.retry_after,
                        last_error = excluded.last_error,
                        attempted_at = excluded.attempted_at
                    """,
                arguments: [
                    albumKey, fingerprint, artist, album, status.rawValue,
                    retryAfter?.timeIntervalSince1970, lastError, attemptedAt.timeIntervalSince1970
                ]
            )
        }
    }

    public func musicBrainzAutoFillSummary() throws -> MusicBrainzAutoFillSummary {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT status, COUNT(*) AS count FROM musicbrainz_autofill_attempts GROUP BY status"
            )
            let counts = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (MusicBrainzAutoFillStatus, Int)? in
                guard let status = MusicBrainzAutoFillStatus(rawValue: row["status"]) else { return nil }
                return (status, row["count"])
            })
            return MusicBrainzAutoFillSummary(
                completed: counts[.completed, default: 0],
                noMatch: counts[.noMatch, default: 0],
                transientFailure: counts[.transientFailure, default: 0]
            )
        }
    }

    public func clearMusicBrainzAutoFillAttempts(status: MusicBrainzAutoFillStatus) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM musicbrainz_autofill_attempts WHERE status = ?",
                arguments: [status.rawValue]
            )
        }
    }

    public func pageTracks(
        query: String = "",
        defaultSearchField: MetadataField? = nil,
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize,
        availableOnly: Bool = false
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let searchFilter = Self.searchFilter(for: query, defaultField: defaultSearchField)

        return try pool.read { db in
            var whereParts: [String] = []
            var arguments: StatementArguments = []
            var from = "tracks t"
            searchFilter?.apply(from: &from, whereParts: &whereParts, arguments: &arguments, tableAlias: "t")
            if availableOnly { whereParts.append("t.is_available = 1") }
            let whereSQL = whereParts.isEmpty ? "" : " WHERE " + whereParts.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(from)\(whereSQL)",
                arguments: arguments
            ) ?? 0
            let orderSQL = Self.orderSQL(sort, direction: direction)
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(orderSQL) LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack),
                offset: safeOffset,
                limit: limit,
                totalCount: total
            )
        }
    }

    public func pageTracks(
        matching filter: ExactMetadataFilter,
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let column = switch filter.field {
        case .title: "title"
        case .artist: "artist"
        case .album: "album"
        case .genre: "genre"
        case .comment: "comment"
        }
        return try pool.read { db in
            let total = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM tracks WHERE \(column) = ?", arguments: [filter.value]
            ) ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM tracks t WHERE t.\(column) = ? ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: [filter.value, limit, safeOffset]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    @discardableResult
    public func enqueueNext(trackID: Int64) throws -> Bool {
        try pool.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tracks WHERE id = ? AND is_available = 1)", arguments: [trackID]) == true else {
                return false
            }
            let nextPosition = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM play_queue")) ?? 0
            try db.execute(
                sql: "INSERT INTO play_queue(track_id, position, added_at) VALUES (?, ?, ?)",
                arguments: [trackID, nextPosition, Date().timeIntervalSince1970]
            )
            return true
        }
    }

    public func playQueuePage(offset: Int = 0, limit: Int = defaultPageSize) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM play_queue") ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM play_queue q JOIN tracks t ON t.id = q.track_id
                ORDER BY q.position, q.id LIMIT ? OFFSET ?
                """, arguments: [limit, safeOffset])
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func dequeueNext() throws -> Track? {
        try pool.write { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT q.id AS queue_id, t.* FROM play_queue q JOIN tracks t ON t.id = q.track_id
                WHERE t.is_available = 1 ORDER BY q.position, q.id LIMIT 1
                """) else {
                try db.execute(sql: "DELETE FROM play_queue WHERE track_id NOT IN (SELECT id FROM tracks WHERE is_available = 1)")
                return nil
            }
            let queueID: Int64 = row["queue_id"]
            try db.execute(sql: "DELETE FROM play_queue WHERE id = ?", arguments: [queueID])
            return Self.decodeTrack(row)
        }
    }

    public func removeFromPlayQueue(trackID: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM play_queue WHERE id = (SELECT id FROM play_queue WHERE track_id = ? ORDER BY position, id LIMIT 1)", arguments: [trackID])
        }
    }

    public func clearPlayQueue() throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM play_queue") }
    }

    public func metadataIssueSummaries() throws -> [MetadataIssueSummary] {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.missingTitle)) THEN 1 ELSE 0 END) AS missing_title,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.missingArtist)) THEN 1 ELSE 0 END) AS missing_artist,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.missingAlbum)) THEN 1 ELSE 0 END) AS missing_album,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.missingYear)) THEN 1 ELSE 0 END) AS missing_year,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.urlInMP3Metadata)) THEN 1 ELSE 0 END) AS url_metadata,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.commentInMP3)) THEN 1 ELSE 0 END) AS comment_count,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.suspectedMojibake)) THEN 1 ELSE 0 END) AS mojibake,
                    SUM(CASE WHEN \(Self.metadataIssuePredicate(.corruptedOrEmpty)) THEN 1 ELSE 0 END) AS corrupted_count
                FROM tracks t
                """) else { return [] }
            let duplicateCount = try Int.fetchOne(db, sql: Self.duplicateMetadataCountSQL) ?? 0
            return [
                MetadataIssueSummary(kind: .missingTitle, count: row["missing_title"] ?? 0),
                MetadataIssueSummary(kind: .missingArtist, count: row["missing_artist"] ?? 0),
                MetadataIssueSummary(kind: .missingAlbum, count: row["missing_album"] ?? 0),
                MetadataIssueSummary(kind: .missingYear, count: row["missing_year"] ?? 0),
                MetadataIssueSummary(kind: .urlInMP3Metadata, count: row["url_metadata"] ?? 0),
                MetadataIssueSummary(kind: .commentInMP3, count: row["comment_count"] ?? 0),
                MetadataIssueSummary(kind: .suspectedMojibake, count: row["mojibake"] ?? 0),
                MetadataIssueSummary(kind: .duplicateTracks, count: duplicateCount),
                MetadataIssueSummary(kind: .corruptedOrEmpty, count: row["corrupted_count"] ?? 0)
            ]
        }
    }

    public func pageMetadataIssues(
        kind: MetadataIssueKind,
        field: MetadataField? = nil,
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard kind != .suspectedVariations else { throw MassiveMusicError.invalidPageSize }
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        if kind == .duplicateTracks {
            return try pool.read { db in
                let total = try Int.fetchOne(db, sql: Self.duplicateMetadataCountSQL) ?? 0
                let rows = try Row.fetchAll(
                    db,
                    sql: "\(Self.duplicateMetadataTracksCTE) SELECT t.* \(Self.duplicateMetadataJoinSQL) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                    arguments: [limit, safeOffset]
                )
                return TrackPage(
                    tracks: rows.map(Self.decodeTrack), offset: safeOffset,
                    limit: limit, totalCount: total
                )
            }
        }
        let predicate = Self.metadataIssuePredicate(kind, field: field)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks t WHERE \(predicate)") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM tracks t WHERE \(predicate) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: [limit, safeOffset]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func resetPendingMetadataAnalysis() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM metadata_terms")
            try db.execute(sql: "DELETE FROM metadata_variation_candidates WHERE status = 'pending'")
        }
    }

    public func distinctMetadataTerms(
        field: MetadataField,
        after value: String?,
        limit: Int = 1_000
    ) throws -> [(value: String, count: Int)] {
        let column = Self.metadataColumn(field)
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(column) AS value, COUNT(*) AS track_count
                FROM tracks
                WHERE trim(\(column)) <> '' AND (? IS NULL OR \(column) > ? COLLATE BINARY)
                GROUP BY \(column) COLLATE BINARY
                ORDER BY \(column) COLLATE BINARY
                LIMIT ?
                """, arguments: [value, value, limit])
            return rows.map { ($0["value"], $0["track_count"]) }
        }
    }

    public func insertMetadataTerms(
        field: MetadataField,
        terms: [(value: String, normalized: String, prefix: String, count: Int)]
    ) throws {
        guard !terms.isEmpty else { return }
        try pool.write { db in
            for term in terms {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO metadata_terms(field, value, normalized, prefix, char_count, track_count)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [field.rawValue, term.value, term.normalized, term.prefix,
                                      term.normalized.count, term.count])
            }
        }
    }

    public func generateNormalizationCandidates() throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO metadata_variation_candidates(
                    field, value_a, value_b, track_count_a, track_count_b, reason, edit_distance, status, created_at
                )
                SELECT a.field, a.value, b.value, a.track_count, b.track_count,
                       'normalization', 0, 'pending', ?
                FROM metadata_terms a
                JOIN metadata_terms b ON b.field = a.field AND b.normalized = a.normalized AND b.id > a.id
                WHERE a.normalized <> ''
                  AND a.id = (SELECT MIN(c.id) FROM metadata_terms c WHERE c.field = a.field AND c.normalized = a.normalized)
                """, arguments: [Date().timeIntervalSince1970])
            return db.changesCount
        }
    }

    public func metadataPrefixes(field: MetadataField, after prefix: String?, limit: Int = 500) throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT prefix FROM metadata_terms
                WHERE field = ? AND prefix <> '' AND (? IS NULL OR prefix > ? COLLATE BINARY)
                GROUP BY prefix COLLATE BINARY ORDER BY prefix COLLATE BINARY LIMIT ?
                """, arguments: [field.rawValue, prefix, prefix, limit])
        }
    }

    public func metadataTerms(field: MetadataField, prefix: String, limit: Int = 201) throws -> [MetadataTerm] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT value, normalized, track_count FROM metadata_terms
                WHERE field = ? AND prefix = ? COLLATE BINARY AND char_count BETWEEN 4 AND 80
                ORDER BY normalized COLLATE BINARY LIMIT ?
                """, arguments: [field.rawValue, prefix, limit]).map {
                    MetadataTerm(value: $0["value"], normalized: $0["normalized"], trackCount: $0["track_count"])
                }
        }
    }

    public func storedMetadataTerms(
        field: MetadataField,
        afterPrefix: String?,
        afterID: Int64?,
        limit: Int = 1_000
    ) throws -> [StoredMetadataTerm] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, prefix, value, normalized, track_count FROM metadata_terms
                WHERE field = ? AND prefix <> '' AND char_count BETWEEN 4 AND 80
                  AND (? IS NULL OR prefix > ? COLLATE BINARY OR (prefix = ? COLLATE BINARY AND id > ?))
                ORDER BY prefix COLLATE BINARY, id LIMIT ?
                """, arguments: [field.rawValue, afterPrefix, afterPrefix, afterPrefix, afterID, limit]).map {
                    StoredMetadataTerm(
                        id: $0["id"], prefix: $0["prefix"],
                        term: MetadataTerm(value: $0["value"], normalized: $0["normalized"], trackCount: $0["track_count"])
                    )
                }
        }
    }

    @discardableResult
    public func insertTypoCandidate(
        field: MetadataField,
        first: MetadataTerm,
        second: MetadataTerm,
        distance: Int
    ) throws -> Bool {
        let ordered = first.value < second.value ? (first, second) : (second, first)
        return try pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO metadata_variation_candidates(
                    field, value_a, value_b, track_count_a, track_count_b, reason, edit_distance, status, created_at
                ) VALUES (?, ?, ?, ?, ?, 'likelyTypo', ?, 'pending', ?)
                """, arguments: [field.rawValue, ordered.0.value, ordered.1.value,
                                  ordered.0.trackCount, ordered.1.trackCount, distance, Date().timeIntervalSince1970])
            return db.changesCount > 0
        }
    }

    public func metadataVariationCount(field: MetadataField? = nil) throws -> Int {
        try pool.read { db in
            if let field {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending' AND field = ?",
                    arguments: [field.rawValue]
                ) ?? 0
            }
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending'"
            ) ?? 0
        }
    }

    public func pageMetadataVariations(
        field: MetadataField? = nil,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> MetadataVariationPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total: Int
            let rows: [Row]
            if let field {
                total = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending' AND field = ?",
                    arguments: [field.rawValue]
                ) ?? 0
                rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM metadata_variation_candidates
                    WHERE status = 'pending' AND field = ?
                    ORDER BY CASE reason WHEN 'normalization' THEN 0 ELSE 1 END, value_a COLLATE NOCASE
                    LIMIT ? OFFSET ?
                    """, arguments: [field.rawValue, limit, safeOffset])
            } else {
                total = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending'"
                ) ?? 0
                rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM metadata_variation_candidates WHERE status = 'pending'
                    ORDER BY CASE reason WHEN 'normalization' THEN 0 ELSE 1 END, field, value_a COLLATE NOCASE
                    LIMIT ? OFFSET ?
                    """, arguments: [limit, safeOffset])
            }
            let candidates = rows.compactMap { row -> MetadataVariationCandidate? in
                guard let field = MetadataField(rawValue: row["field"]),
                      let reason = MetadataVariationReason(rawValue: row["reason"]) else { return nil }
                return MetadataVariationCandidate(
                    id: row["id"], field: field, valueA: row["value_a"], valueB: row["value_b"],
                    trackCountA: row["track_count_a"], trackCountB: row["track_count_b"],
                    reason: reason, editDistance: row["edit_distance"]
                )
            }
            return MetadataVariationPage(candidates: candidates, offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func ignoreMetadataVariation(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE metadata_variation_candidates SET status = 'ignored' WHERE id = ?", arguments: [id])
        }
    }

    private static func refreshMetadataVariationCandidates(db: Database, previous: Row?, updated: Row) throws {
        guard let previous else { return }
        for field in MetadataField.variationFields {
            let column = metadataColumn(field)
            let oldValue: String = previous[column]
            let newValue: String = updated[column]
            guard oldValue != newValue else { continue }

            let affectedArguments: StatementArguments = [
                field.rawValue, oldValue, newValue, oldValue, newValue
            ]
            try db.execute(sql: """
                UPDATE metadata_variation_candidates
                SET track_count_a = (
                        SELECT COUNT(*) FROM tracks
                        WHERE \(column) = metadata_variation_candidates.value_a COLLATE BINARY
                    ),
                    track_count_b = (
                        SELECT COUNT(*) FROM tracks
                        WHERE \(column) = metadata_variation_candidates.value_b COLLATE BINARY
                    )
                WHERE field = ? AND status = 'pending'
                  AND (value_a = ? COLLATE BINARY OR value_a = ? COLLATE BINARY
                    OR value_b = ? COLLATE BINARY OR value_b = ? COLLATE BINARY)
                """, arguments: affectedArguments)
            try db.execute(sql: """
                DELETE FROM metadata_variation_candidates
                WHERE field = ? AND status = 'pending'
                  AND (value_a = ? COLLATE BINARY OR value_a = ? COLLATE BINARY
                    OR value_b = ? COLLATE BINARY OR value_b = ? COLLATE BINARY)
                  AND (track_count_a = 0 OR track_count_b = 0)
                """, arguments: affectedArguments)
        }
    }

    public func pageFavoriteTracks(
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_favorite = 1") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM tracks t WHERE is_favorite = 1 ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: [limit, max(0, offset)]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: max(0, offset), limit: limit, totalCount: total)
        }
    }

    public func pageRecentlyPlayedTracks(
        query: String = "",
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let searchFilter = Self.searchFilter(for: query)

        return try pool.read { db in
            var whereParts: [String] = ["t.last_played_at IS NOT NULL", "t.is_available = 1"]
            var arguments: StatementArguments = []
            var from = "tracks t"
            searchFilter?.apply(from: &from, whereParts: &whereParts, arguments: &arguments, tableAlias: "t")
            let whereSQL = whereParts.isEmpty ? "" : " WHERE " + whereParts.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(from)\(whereSQL)",
                arguments: arguments
            ) ?? 0
            let orderSQL = sort == .title && direction == .ascending
                ? "t.last_played_at DESC, t.id DESC"
                : Self.orderSQL(sort, direction: direction)
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(orderSQL) LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack),
                offset: safeOffset,
                limit: limit,
                totalCount: total
            )
        }
    }

    @discardableResult
    public func toggleFavorite(trackID: Int64) throws -> Bool {
        try pool.write { db in
            try db.execute(sql: "UPDATE tracks SET is_favorite = CASE is_favorite WHEN 1 THEN 0 ELSE 1 END WHERE id = ?", arguments: [trackID])
            return (try Bool.fetchOne(db, sql: "SELECT is_favorite FROM tracks WHERE id = ?", arguments: [trackID])) ?? false
        }
    }

    public func setFavorite(trackID: Int64, isFavorite: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE tracks SET is_favorite = ? WHERE id = ?",
                arguments: [isFavorite, trackID]
            )
        }
    }

    public func setFavorites(trackIDs: [Int64], isFavorite: Bool) throws {
        let uniqueIDs = Array(Set(trackIDs))
        guard !uniqueIDs.isEmpty else { return }
        try pool.write { db in
            let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ",")
            var arguments = StatementArguments([isFavorite])
            arguments += StatementArguments(uniqueIDs)
            try db.execute(
                sql: "UPDATE tracks SET is_favorite = ? WHERE id IN (\(placeholders))",
                arguments: arguments
            )
        }
    }

    public func markPlayed(trackID: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE tracks SET play_count = play_count + 1, last_played_at = ? WHERE id = ?", arguments: [Date().timeIntervalSince1970, trackID])
        }
    }

    public func fetchListeningInsights() throws -> ListeningInsights {
        return try pool.read { db in
            let totalPlayed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM tracks WHERE last_played_at IS NOT NULL AND is_available = 1"
            ) ?? 0

            let topTrackRows = try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE is_available = 1 AND play_count > 0
                ORDER BY play_count DESC, last_played_at DESC
                LIMIT 5
            """)
            let topTracks = topTrackRows.map { row in
                let track = Self.decodeTrack(row)
                let count: Int = row["play_count"] ?? 1
                return ListeningInsights.TopTrack(track: track, playCount: count)
            }

            let topArtistRows = try Row.fetchAll(db, sql: """
                SELECT artist, SUM(play_count) AS total_plays, COUNT(*) as track_count
                FROM tracks
                WHERE is_available = 1 AND play_count > 0 AND artist <> ''
                GROUP BY artist COLLATE NOCASE
                ORDER BY total_plays DESC, last_played_at DESC
                LIMIT 5
            """)
            let topArtists = topArtistRows.map { row -> ListeningInsights.TopEntity in
                let artist: String = row["artist"]
                let plays: Int = row["total_plays"] ?? 0
                let count: Int = row["track_count"] ?? 0
                return ListeningInsights.TopEntity(name: artist, count: plays, subtext: "\(count) songs")
            }

            let topGenreRows = try Row.fetchAll(db, sql: """
                SELECT genre, SUM(play_count) AS total_plays
                FROM tracks
                WHERE is_available = 1 AND play_count > 0 AND genre <> ''
                GROUP BY genre COLLATE NOCASE
                ORDER BY total_plays DESC
                LIMIT 5
            """)
            let totalGenrePlays = max(1, topGenreRows.reduce(0) { $0 + ((try? $1["total_plays"]) ?? 0) })
            var topGenres: [ListeningInsights.GenreSlice] = []
            for row in topGenreRows {
                let genre: String = row["genre"]
                let plays: Int = row["total_plays"] ?? 0
                let pct = Double(plays) / Double(totalGenrePlays)

                let genreTrackRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1 AND genre = ? COLLATE NOCASE
                    ORDER BY play_count DESC, last_played_at DESC
                    LIMIT 8
                """, arguments: [genre])
                let genreTopTracks = genreTrackRows.map { trRow in
                    let track = Self.decodeTrack(trRow)
                    let plays: Int = trRow["play_count"] ?? 1
                    return ListeningInsights.TopTrack(track: track, playCount: max(1, plays))
                }

                topGenres.append(ListeningInsights.GenreSlice(
                    genre: genre,
                    count: plays,
                    percentage: pct,
                    topTracks: genreTopTracks
                ))
            }

            let periods: [(period: String, titleJa: String, titleEn: String, icon: String, hourStart: Int, hourEnd: Int)] = [
                ("morning", "朝 (05:00〜12:00)", "Morning (05:00–12:00)", "sun.horizon.fill", 5, 11),
                ("afternoon", "昼 (12:00〜17:00)", "Afternoon (12:00–17:00)", "sun.max.fill", 12, 16),
                ("evening", "夕・夜 (17:00〜22:00)", "Evening (17:00–22:00)", "sunset.fill", 17, 21),
                ("night", "深夜 (22:00〜05:00)", "Night (22:00–05:00)", "moon.stars.fill", 22, 4)
            ]

            var timeOfDayVibes: [ListeningInsights.TimeOfDayVibe] = []
            for p in periods {
                let condition = p.hourStart <= p.hourEnd
                    ? "CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) BETWEEN \(p.hourStart) AND \(p.hourEnd)"
                    : "(CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) >= \(p.hourStart) OR CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) <= \(p.hourEnd))"

                let topGenre = try String.fetchOne(db, sql: """
                    SELECT genre FROM tracks
                    WHERE is_available = 1 AND last_played_at IS NOT NULL AND genre <> ''
                      AND \(condition)
                    GROUP BY genre COLLATE NOCASE
                    ORDER BY COUNT(*) DESC
                    LIMIT 1
                """) ?? "—"

                let count = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM tracks
                    WHERE is_available = 1 AND last_played_at IS NOT NULL
                      AND \(condition)
                """) ?? 0

                let rankingRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1 AND last_played_at IS NOT NULL
                      AND \(condition)
                    ORDER BY play_count DESC, last_played_at DESC
                    LIMIT 10
                """)
                let topTracks: [ListeningInsights.TopTrack] = rankingRows.map { row in
                    let track = Self.decodeTrack(row)
                    let plays: Int = row["play_count"] ?? 1
                    return ListeningInsights.TopTrack(track: track, playCount: max(1, plays))
                }

                timeOfDayVibes.append(ListeningInsights.TimeOfDayVibe(
                    period: p.period,
                    title: p.titleJa,
                    icon: p.icon,
                    topGenre: topGenre,
                    playCount: count,
                    sampleTracks: topTracks.map(\.track),
                    topTracks: topTracks
                ))
            }

            let thirtyDaysAgo = Date().timeIntervalSince1970 - (30 * 24 * 3600)
            let rediscoveryRows = try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE is_available = 1 AND (is_favorite = 1 OR play_count >= 1)
                  AND (last_played_at IS NULL OR last_played_at < ?)
                ORDER BY last_played_at ASC, RANDOM()
                LIMIT 5
            """, arguments: [thirtyDaysAgo])
            let rediscoveryTracks = rediscoveryRows.map(Self.decodeTrack)

            let currentHour = Calendar.current.component(.hour, from: Date())
            let currentCondition = (5...11).contains(currentHour) ? "CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) BETWEEN 5 AND 11"
                : (12...16).contains(currentHour) ? "CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) BETWEEN 12 AND 16"
                : (17...21).contains(currentHour) ? "CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) BETWEEN 17 AND 21"
                : "(CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) >= 22 OR CAST(strftime('%H', last_played_at, 'unixepoch', 'localtime') AS INT) <= 4)"

            var vibeRows = try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE is_available = 1 AND last_played_at IS NOT NULL
                  AND \(currentCondition)
                ORDER BY last_played_at DESC
                LIMIT 20
            """)
            if vibeRows.isEmpty {
                vibeRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1
                    ORDER BY play_count DESC, is_favorite DESC, RANDOM()
                    LIMIT 20
                """)
            }
            let currentVibeTracks = vibeRows.map(Self.decodeTrack)

            return ListeningInsights(
                totalPlayedCount: totalPlayed,
                topTracks: topTracks,
                topArtists: topArtists,
                topGenres: topGenres,
                timeOfDayVibes: timeOfDayVibes,
                rediscoveryTracks: rediscoveryTracks,
                currentVibeTracks: currentVibeTracks
            )
        }
    }

    public func similarTracks(to track: Track, limit: Int = 12) throws -> [Track] {
        guard (1...100).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let genre = track.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let albumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)

            if genre.isEmpty && artist.isEmpty && albumArtist.isEmpty {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM tracks
                    WHERE id <> ? AND is_available = 1
                    ORDER BY play_count ASC, RANDOM()
                    LIMIT ?
                    """, arguments: [track.id, limit])
                return rows.map(Self.decodeTrack)
            }

            let rows = try Row.fetchAll(db, sql: """
                WITH candidates AS (
                    SELECT t.*,
                           ROW_NUMBER() OVER(
                               PARTITION BY t.artist 
                               ORDER BY t.play_count ASC, RANDOM()
                           ) as artist_track_rank
                    FROM tracks t
                    WHERE t.id <> ? AND t.is_available = 1
                      AND (
                          (? <> '' AND t.genre = ?)
                          OR (? <> '' AND t.artist = ?)
                          OR (? <> '' AND t.album_artist = ?)
                      )
                )
                SELECT * FROM candidates
                WHERE (artist <> ? AND artist_track_rank <= 2)
                   OR (artist = ? AND artist_track_rank <= 1)
                ORDER BY 
                    CASE 
                        WHEN ? <> '' AND genre = ? AND artist <> ? THEN 0
                        WHEN ? <> '' AND genre = ? THEN 1
                        WHEN ? <> '' AND artist = ? THEN 2
                        ELSE 3
                    END ASC,
                    play_count ASC,
                    RANDOM()
                LIMIT ?
                """, arguments: [
                    track.id,
                    genre, genre,
                    artist, artist,
                    albumArtist, albumArtist,
                    artist, artist,
                    genre, genre, artist,
                    genre, genre,
                    artist, artist,
                    limit
                ])
            return rows.map(Self.decodeTrack)
        }
    }

    public func setSetting(_ value: String, forKey key: String) throws {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO app_settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
        }
    }

    public func setting(forKey key: String) throws -> String? {
        try pool.read { db in try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key]) }
    }

    public func removeSetting(forKey key: String) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM app_settings WHERE key = ?", arguments: [key])
        }
    }

    public func addStorageDestination(name: String, path: String, bookmark: Data, makePrimary: Bool = true) throws -> Int64 {
        try pool.write { db in
            if makePrimary { try db.execute(sql: "UPDATE storage_destinations SET is_primary = 0") }
            try db.execute(sql: """
                INSERT INTO storage_destinations(name, path, bookmark, is_primary, is_available, created_at)
                VALUES (?, ?, ?, ?, 1, ?)
                ON CONFLICT(path) DO UPDATE SET name = excluded.name, bookmark = excluded.bookmark,
                    is_primary = excluded.is_primary, is_available = 1
                """, arguments: [name, path, bookmark, makePrimary, Date().timeIntervalSince1970])
            return try Int64.fetchOne(db, sql: "SELECT id FROM storage_destinations WHERE path = ?", arguments: [path]) ?? 0
        }
    }
    public func renameVibeStorageDestinationToMain() throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE storage_destinations SET name = 'メイン保管先' WHERE name = 'Vibe'")
            try db.execute(sql: "UPDATE scan_roots SET display_name = 'メイン保管先' WHERE display_name = 'Vibe'")
            try db.execute(sql: "DELETE FROM tracks WHERE id NOT IN (SELECT MIN(id) FROM tracks GROUP BY identity_key)")
        }
    }

    public func storageDestinations() throws -> [StorageDestination] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM storage_destinations ORDER BY is_primary DESC, name COLLATE NOCASE").map {
                StorageDestination(id: $0["id"], name: $0["name"], path: $0["path"], bookmark: $0["bookmark"], isPrimary: $0["is_primary"], isAvailable: $0["is_available"])
            }
        }
    }

    public func addPendingImport(localPath: String, filename: String) throws -> Int64 {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO pending_imports(local_path, filename, state, created_at) VALUES (?, ?, 'staged', ?)", arguments: [localPath, filename, Date().timeIntervalSince1970])
            return db.lastInsertedRowID
        }
    }

    public func pendingImports() throws -> [PendingImport] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM pending_imports ORDER BY created_at DESC LIMIT 1000").compactMap { row in
                guard let state = ImportState(rawValue: row["state"]) else { return nil }
                return PendingImport(id: row["id"], localPath: row["local_path"], filename: row["filename"], state: state, createdAt: Date(timeIntervalSince1970: row["created_at"]), errorMessage: row["error_message"])
            }
        }
    }
    public func pendingImport(id: Int64) throws -> PendingImport? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM pending_imports WHERE id = ?", arguments: [id]) else { return nil }
            guard let state = ImportState(rawValue: row["state"]) else { return nil }
            return PendingImport(id: row["id"], localPath: row["local_path"], filename: row["filename"], state: state, createdAt: Date(timeIntervalSince1970: row["created_at"]), errorMessage: row["error_message"])
        }
    }
    public func trackID(forIdentityKey identityKey: String) throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM tracks WHERE identity_key = ?", arguments: [identityKey])
        }
    }

    public func trackID(rootID: Int64, relativePath: String) throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tracks WHERE root_id = ? AND relative_path = ? LIMIT 1",
                arguments: [rootID, relativePath]
            )
        }
    }

    public func updatePendingImport(id: Int64, state: ImportState, localPath: String? = nil, error: String? = nil) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE pending_imports SET state = ?, local_path = COALESCE(?, local_path), error_message = ? WHERE id = ?", arguments: [state.rawValue, localPath, error, id])
        }
    }

    public func cachedLyrics(trackID: Int64) throws -> CachedLyrics? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM lyrics WHERE track_id = ?", arguments: [trackID]) else { return nil }
            return CachedLyrics(trackID: trackID, provider: row["provider"], plainLyrics: row["plain_lyrics"], syncedLyrics: row["synced_lyrics"], updatedAt: Date(timeIntervalSince1970: row["updated_at"]))
        }
    }

    public func saveLyrics(trackID: Int64, provider: String, plain: String, synced: String?) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO lyrics(track_id, provider, plain_lyrics, synced_lyrics, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET provider = excluded.provider, plain_lyrics = excluded.plain_lyrics,
                    synced_lyrics = excluded.synced_lyrics, updated_at = excluded.updated_at
                """, arguments: [trackID, provider, plain, synced, Date().timeIntervalSince1970])
        }
    }

    public func cachedPath(trackID: Int64) throws -> String? {
        try pool.read { db in try String.fetchOne(db, sql: "SELECT local_path FROM local_cache WHERE track_id = ?", arguments: [trackID]) }
    }

    public func cachedTrackIDs(in trackIDs: [Int64]) throws -> Set<Int64> {
        guard !trackIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: trackIDs.count).joined(separator: ",")
        return try pool.read { db in
            Set(try Int64.fetchAll(
                db,
                sql: "SELECT track_id FROM local_cache WHERE track_id IN (\(placeholders))",
                arguments: StatementArguments(trackIDs)
            ))
        }
    }

    public func allCachedTrackIDs() throws -> Set<Int64> {
        try pool.read { db in
            Set(try Int64.fetchAll(db, sql: "SELECT track_id FROM local_cache"))
        }
    }

    public func trackExists(id: Int64) throws -> Bool {
        try pool.read { db in
            (try Int.fetchOne(db, sql: "SELECT 1 FROM tracks WHERE id = ?", arguments: [id])) != nil
        }
    }

    public func findTrackIDMatching(fileSize: Int64, format: String, title: String? = nil, artist: String? = nil) throws -> Int64? {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, title, artist FROM tracks WHERE file_size = ?",
                arguments: [fileSize]
            )
            if rows.count == 1 {
                return rows[0]["id"]
            }
            if let title, !title.isEmpty {
                if let match = rows.first(where: { row in
                    let rowTitle: String = row["title"] ?? ""
                    return rowTitle.localizedCaseInsensitiveCompare(title) == .orderedSame
                }) {
                    return match["id"]
                }
                if let artist, !artist.isEmpty {
                    if let id = try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM tracks WHERE title = ? COLLATE NOCASE AND artist = ? COLLATE NOCASE",
                        arguments: [title, artist]
                    ) {
                        return id
                    }
                }
                if let id = try Int64.fetchOne(
                    db,
                    sql: "SELECT id FROM tracks WHERE title = ? COLLATE NOCASE",
                    arguments: [title]
                ) {
                    return id
                }
            }
            return rows.first?["id"]
        }
    }

    public func pageCachedTracks(
        query: String = "",
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let searchFilter = Self.searchFilter(for: query)
        return try pool.read { db in
            var from = "local_cache c JOIN tracks t ON t.id = c.track_id"
            var whereParts: [String] = []
            var arguments: StatementArguments = []
            searchFilter?.apply(from: &from, whereParts: &whereParts, arguments: &arguments, tableAlias: "t")
            let whereSQL = whereParts.isEmpty ? "" : " WHERE " + whereParts.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM \(from)\(whereSQL)", arguments: arguments
            ) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func recordCachedTrack(trackID: Int64, path: String, fileSize: Int64, pinned: Bool = false) throws {
        try pool.write { db in
            let previousPath = try String.fetchOne(
                db, sql: "SELECT local_path FROM local_cache WHERE track_id = ?", arguments: [trackID]
            )
            let now = Date().timeIntervalSince1970
            try db.execute(sql: """
                INSERT INTO local_cache(track_id, local_path, file_size, cached_at, last_accessed_at, is_pinned)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET local_path = excluded.local_path,
                    file_size = excluded.file_size, last_accessed_at = excluded.last_accessed_at,
                    is_pinned = CASE WHEN excluded.is_pinned = 1 THEN 1 ELSE local_cache.is_pinned END
                """, arguments: [trackID, path, fileSize, now, now, pinned])
            if previousPath != path,
               let trackRow = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [trackID]) {
                try Self.insertActivity(
                    db: db, kind: .addedToCache, trackRow: trackRow, changes: [],
                    absolutePathOverride: path
                )
                try Self.pruneActivityLog(db: db)
            }
        }
    }

    public func cachedTracksBeyondLimit(_ limit: Int) throws -> [(Int64, String)] {
        try pool.read { db in
            let targetLimit = max(0, limit)

            // 保護されていない通常の再生キャッシュ曲数
            let evictableCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM local_cache c
                    LEFT JOIN tracks t ON t.id = c.track_id
                    WHERE (c.is_pinned IS NULL OR c.is_pinned = 0)
                      AND (t.is_favorite IS NULL OR t.is_favorite = 0)
                      AND NOT EXISTS (SELECT 1 FROM playlist_items i WHERE i.track_id = c.track_id)
                    """
            ) ?? 0

            // お気に入り、プレイリスト、明示的ピン留めされている保護曲数
            let protectedCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM local_cache c
                    LEFT JOIN tracks t ON t.id = c.track_id
                    WHERE (c.is_pinned = 1)
                       OR (t.is_favorite = 1)
                       OR EXISTS (SELECT 1 FROM playlist_items i WHERE i.track_id = c.track_id)
                    """
            ) ?? 0

            let allowedEvictable = max(0, targetLimit - protectedCount)
            let excess = evictableCount - allowedEvictable
            let deleteCount = max(0, excess)
            guard deleteCount > 0 else { return [] }

            return try Row.fetchAll(
                db,
                sql: """
                    SELECT c.track_id, c.local_path
                    FROM local_cache c
                    LEFT JOIN tracks t ON t.id = c.track_id
                    WHERE (c.is_pinned IS NULL OR c.is_pinned = 0)
                      AND (t.is_favorite IS NULL OR t.is_favorite = 0)
                      AND NOT EXISTS (SELECT 1 FROM playlist_items i WHERE i.track_id = c.track_id)
                    ORDER BY c.last_accessed_at ASC
                    LIMIT ?
                    """,
                arguments: [deleteCount]
            ).map { ($0["track_id"], $0["local_path"]) }
        }
    }

    public func setCachedTrackPinned(trackID: Int64, pinned: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE local_cache SET is_pinned = ? WHERE track_id = ?",
                arguments: [pinned, trackID]
            )
        }
    }

    public func isCachedTrackPinned(trackID: Int64) throws -> Bool {
        try pool.read { db in
            (try Bool.fetchOne(
                db,
                sql: "SELECT is_pinned FROM local_cache WHERE track_id = ?",
                arguments: [trackID]
            )) ?? false
        }
    }

    public func removeCachedTrack(trackID: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM local_cache WHERE track_id = ?", arguments: [trackID]) }
    }

    public func pageTracksAfter(
        query: String = "",
        defaultSearchField: MetadataField? = nil,
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        after cursor: Track?,
        logicalOffset: Int = 0,
        limit: Int = defaultPageSize,
        availableOnly: Bool = false,
        knownTotal: Int? = nil
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let searchFilter = Self.searchFilter(for: query, defaultField: defaultSearchField)
        return try pool.read { db in
            var baseWhere: [String] = []
            var baseArguments: StatementArguments = []
            var from = "tracks t"
            searchFilter?.apply(from: &from, whereParts: &baseWhere, arguments: &baseArguments, tableAlias: "t")
            if availableOnly { baseWhere.append("t.is_available = 1") }
            let countWhere = baseWhere.isEmpty ? "" : " WHERE " + baseWhere.joined(separator: " AND ")
            let total: Int
            if let knownTotal {
                total = knownTotal
            } else {
                total = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(from)\(countWhere)", arguments: baseArguments
                ) ?? 0
            }

            var pageWhere = baseWhere
            var pageArguments = baseArguments
            if let cursor {
                let predicate = Self.cursorPredicate(sort: sort, direction: direction, cursor: cursor)
                pageWhere.append(predicate.sql)
                pageArguments += predicate.arguments
            }
            let whereSQL = pageWhere.isEmpty ? "" : " WHERE " + pageWhere.joined(separator: " AND ")
            pageArguments += [limit]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack), offset: max(0, logicalOffset),
                limit: limit, totalCount: total
            )
        }
    }

    public func facetPage(
        section: LibrarySection,
        query: String? = nil,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> FacetPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        if section == .genres {
            return try pool.read { db in
                try Self.canonicalGenreFacetPage(
                    db: db, query: query, offset: offset, limit: limit
                )
            }
        }
        let expression: String
        switch section {
        case .albums: expression = "album"
        case .artists: expression = "artist"
        case .genres: preconditionFailure("Handled above")
        case .folders: expression = "CASE WHEN instr(relative_path, '/') > 0 THEN substr(relative_path, 1, instr(relative_path, '/') - 1) ELSE '/' END"
        default: return FacetPage(facets: [], offset: 0, limit: limit, totalCount: 0)
        }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            var filters = ["is_available = 1", "\(expression) <> ''"]
            var filterArgs: StatementArguments = []
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                let escaped = trimmed
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                filters.append("\(expression) LIKE ? ESCAPE '\\' COLLATE NOCASE")
                filterArgs += ["%\(escaped)%"]
            }
            let filterSQL = filters.joined(separator: " AND ")
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks
                    WHERE \(filterSQL)
                    GROUP BY \(expression) COLLATE NOCASE
                )
                """, arguments: filterArgs) ?? 0
            var pageArgs = filterArgs
            pageArgs += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT \(expression) AS name, COUNT(*) AS count
                    FROM tracks
                    WHERE \(filterSQL)
                    GROUP BY \(expression)
                    ORDER BY name COLLATE NOCASE
                    LIMIT ? OFFSET ?
                    """,
                arguments: pageArgs
            )
            return FacetPage(
                facets: rows.map { Facet(name: $0["name"], count: $0["count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func pageAlbums(
        artistFilter: String? = nil,
        genreFilter: String? = nil,
        search: String? = nil,
        sort: AlbumSort = .name,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> AlbumSummaryPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let expression = "artist"
            var filters: [String] = []
            var filterArgs: StatementArguments = []
            if let artistFilter {
                filters.append("(artist = ? COLLATE NOCASE OR album_artist = ? COLLATE NOCASE)")
                filterArgs += [artistFilter, artistFilter]
            }
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "genre", canonicalGenre: genreFilter)
                filters.append(genre.sql)
                filterArgs += genre.arguments
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                filters.append("(album LIKE ? ESCAPE '\\' COLLATE NOCASE OR artist LIKE ? ESCAPE '\\' COLLATE NOCASE OR album_artist LIKE ? ESCAPE '\\' COLLATE NOCASE)")
                filterArgs += ["%\(escaped)%", "%\(escaped)%", "%\(escaped)%"]
            }
            let filterSQL = filters.map { " AND \($0)" }.joined()
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks
                    WHERE is_available = 1 AND album <> ''\(filterSQL)
                    GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                )
                """, arguments: filterArgs) ?? 0
            var args = filterArgs
            args += [limit, safeOffset]
            
            let sortDir = direction == .ascending ? "ASC" : "DESC"
            let orderClause: String
            switch sort {
            case .name:
                orderClause = "name COLLATE NOCASE \(sortDir), artist COLLATE NOCASE \(sortDir)"
            case .artist:
                orderClause = "artist COLLATE NOCASE \(sortDir), name COLLATE NOCASE \(sortDir)"
            case .year:
                orderClause = "CASE WHEN year IS NULL OR year = '' THEN 1 ELSE 0 END, year \(sortDir), name COLLATE NOCASE ASC"
            case .trackCount:
                orderClause = "track_count \(sortDir), name COLLATE NOCASE \(sortDir)"
            }

            let rows = try Row.fetchAll(db, sql: """
                SELECT album AS name, \(expression) AS artist, MIN(NULLIF(year, '')) AS year, COUNT(*) AS track_count
                FROM tracks
                WHERE is_available = 1 AND album <> ''\(filterSQL)
                GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                ORDER BY \(orderClause)
                LIMIT ? OFFSET ?
                """, arguments: args)
            return AlbumSummaryPage(
                albums: rows.map { AlbumSummary(name: $0["name"], artist: $0["artist"], year: $0["year"] ?? "", trackCount: $0["track_count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func pageArtists(
        genreFilter: String? = nil,
        search: String? = nil,
        sort: ArtistSort = .name,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> ArtistSummaryPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            var filters = ["is_available = 1"]
            var filterArgs: StatementArguments = []
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "genre", canonicalGenre: genreFilter)
                filters.append(genre.sql)
                filterArgs += genre.arguments
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                filters.append("artist LIKE ? ESCAPE '\\' COLLATE NOCASE")
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                filterArgs += ["%\(escaped)%"]
            }
            let filterSQL = filters.joined(separator: " AND ")
            let sortExpression = "CASE WHEN lower(name) LIKE 'the %' THEN substr(name, 5) ELSE name END"
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT artist COLLATE NOCASE) FROM tracks WHERE \(filterSQL)",
                arguments: filterArgs
            ) ?? 0
            var pageArguments = filterArgs
            pageArguments += [limit, safeOffset]
            
            let sortDir = direction == .ascending ? "ASC" : "DESC"
            let orderClause: String
            switch sort {
            case .name:
                orderClause = "\(sortExpression) COLLATE NOCASE \(sortDir), name COLLATE NOCASE \(sortDir)"
            case .genre:
                orderClause = "CASE WHEN genre = '' THEN 1 ELSE 0 END, genre COLLATE NOCASE \(sortDir), \(sortExpression) COLLATE NOCASE ASC"
            case .albumCount:
                orderClause = "album_count \(sortDir), \(sortExpression) COLLATE NOCASE \(sortDir)"
            case .trackCount:
                orderClause = "track_count \(sortDir), \(sortExpression) COLLATE NOCASE \(sortDir)"
            }

            let rows = try Row.fetchAll(db, sql: """
                WITH filtered_tracks AS (
                    SELECT artist, album, genre
                    FROM tracks
                    WHERE \(filterSQL)
                ), artist_rollup AS (
                    SELECT artist AS name,
                           COUNT(DISTINCT NULLIF(album, '')) AS album_count,
                           COUNT(*) AS track_count
                    FROM filtered_tracks
                    GROUP BY artist COLLATE NOCASE
                ), ranked_genres AS (
                    SELECT artist,
                           genre,
                           ROW_NUMBER() OVER (
                               PARTITION BY artist COLLATE NOCASE
                               ORDER BY COUNT(*) DESC, genre COLLATE NOCASE ASC
                           ) AS genre_rank
                    FROM filtered_tracks
                    WHERE trim(genre) <> ''
                    GROUP BY artist COLLATE NOCASE, genre COLLATE NOCASE
                )
                SELECT artist_rollup.name,
                       COALESCE(ranked_genres.genre, '') AS genre,
                       artist_rollup.album_count,
                       artist_rollup.track_count
                FROM artist_rollup
                LEFT JOIN ranked_genres
                  ON ranked_genres.artist = artist_rollup.name COLLATE NOCASE
                 AND ranked_genres.genre_rank = 1
                ORDER BY \(orderClause)
                LIMIT ? OFFSET ?
                """, arguments: pageArguments)
            return ArtistSummaryPage(
                artists: rows.map { ArtistSummary(name: $0["name"], genre: $0["genre"], albumCount: $0["album_count"], trackCount: $0["track_count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func artistSummary(named name: String) throws -> ArtistSummary? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT artist AS name,
                       COALESCE((
                           SELECT genre
                           FROM tracks AS genre_tracks
                           WHERE genre_tracks.is_available = 1
                             AND genre_tracks.artist = tracks.artist COLLATE NOCASE
                             AND trim(genre_tracks.genre) <> ''
                           GROUP BY genre COLLATE NOCASE
                           ORDER BY COUNT(*) DESC, genre COLLATE NOCASE ASC
                           LIMIT 1
                       ), '') AS genre,
                       COUNT(DISTINCT NULLIF(album, '')) AS album_count,
                       COUNT(*) AS track_count
                FROM tracks WHERE is_available = 1 AND artist = ? COLLATE NOCASE
                GROUP BY artist COLLATE NOCASE
                """, arguments: [name]) else { return nil }
            return ArtistSummary(name: row["name"], genre: row["genre"], albumCount: row["album_count"], trackCount: row["track_count"])
        }
    }

    public func libraryStorageSummary(
        albumFilter: AlbumSummary? = nil,
        artistFilter: String? = nil,
        genreFilter: String? = nil
    ) throws -> LibraryStorageSummary {
        try pool.read { db in
            let albumArtistExpression = "COALESCE(NULLIF(t.album_artist, ''), t.artist)"
            var predicates = ["t.is_available = 1"]
            var arguments: StatementArguments = []
            if let albumFilter {
                predicates += ["t.album = ? COLLATE NOCASE", "\(albumArtistExpression) = ? COLLATE NOCASE"]
                arguments += [albumFilter.name, albumFilter.artist]
            } else if let artistFilter {
                predicates.append("t.artist = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "t.genre", canonicalGenre: genreFilter)
                predicates.append(genre.sql)
                arguments += genre.arguments
            }
            let whereSQL = predicates.joined(separator: " AND ")
            let totalBytes = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(t.file_size), 0) FROM tracks t WHERE \(whereSQL)",
                arguments: arguments
            ) ?? 0
            let paths = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT r.last_known_path
                    FROM tracks t
                    JOIN scan_roots r ON r.id = t.root_id
                    WHERE \(whereSQL)
                    ORDER BY r.last_known_path COLLATE NOCASE
                    """,
                arguments: arguments
            )
            return LibraryStorageSummary(totalBytes: totalBytes, absoluteRootPaths: paths)
        }
    }

    public func pageTracksForArtist(
        artist: String,
        sort: TrackSort = .artist,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            // An empty album-artist tag is normal and must not make every track
            // appear under the logical "Unknown Artist" group.
            let artistPredicate = artist.isEmpty
                ? "artist = ''"
                : "(artist = ? COLLATE NOCASE OR album_artist = ? COLLATE NOCASE)"
            let artistArguments: StatementArguments = artist.isEmpty ? [] : [artist, artist]
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 1 AND \(artistPredicate)",
                arguments: artistArguments
            ) ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t WHERE t.is_available = 1 AND \(artistPredicate)
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: artistArguments + [limit, safeOffset])
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func pageTracksForGenre(
        genre: String,
        sort: TrackSort = .album,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let genrePredicate = try Self.genrePredicate(db: db, column: "genre", canonicalGenre: genre)
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 1 AND \(genrePredicate.sql)",
                arguments: genrePredicate.arguments
            ) ?? 0
            let trackGenrePredicate = try Self.genrePredicate(db: db, column: "t.genre", canonicalGenre: genre)
            var pageArguments = trackGenrePredicate.arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t
                WHERE t.is_available = 1 AND \(trackGenrePredicate.sql)
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: pageArguments)
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func offsetForTrackTitle(
        startingAt value: String,
        albumFilter: AlbumSummary? = nil,
        artistFilter: String? = nil,
        genreFilter: String? = nil,
        availableOnly: Bool = false
    ) throws -> Int {
        try pool.read { db in
            let albumArtistExpression = "COALESCE(NULLIF(t.album_artist, ''), t.artist)"
            var predicates: [String] = []
            var arguments: StatementArguments = []
            if availableOnly { predicates.append("t.is_available = 1") }
            if let albumFilter {
                predicates += ["t.album = ? COLLATE NOCASE", "\(albumArtistExpression) = ? COLLATE NOCASE"]
                arguments += [albumFilter.name, albumFilter.artist]
            }
            if let artistFilter {
                predicates.append("t.artist = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "t.genre", canonicalGenre: genreFilter)
                predicates.append(genre.sql)
                arguments += genre.arguments
            }
            predicates.append("t.title < ? COLLATE NOCASE")
            arguments += [value]
            return try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM tracks t WHERE \(predicates.joined(separator: " AND "))",
                arguments: arguments
            ) ?? 0
        }
    }

    public func offsetForAlbum(
        startingAt value: String,
        artistFilter: String? = nil,
        genreFilter: String? = nil,
        search: String? = nil
    ) throws -> Int {
        try pool.read { db in
            let expression = "COALESCE(NULLIF(album_artist, ''), artist)"
            var predicates = ["is_available = 1", "album <> ''", "album < ? COLLATE NOCASE"]
            var arguments: StatementArguments = [value]
            if let artistFilter {
                predicates.append("\(expression) = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "genre", canonicalGenre: genreFilter)
                predicates.append(genre.sql)
                arguments += genre.arguments
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                predicates.append("(album LIKE ? ESCAPE '\\' COLLATE NOCASE OR artist LIKE ? ESCAPE '\\' COLLATE NOCASE OR album_artist LIKE ? ESCAPE '\\' COLLATE NOCASE)")
                arguments += ["%\(escaped)%", "%\(escaped)%", "%\(escaped)%"]
            }
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks WHERE \(predicates.joined(separator: " AND "))
                    GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                )
                """, arguments: arguments) ?? 0
        }
    }

    public func offsetForArtist(
        startingAt value: String,
        direction: SortDirection = .ascending,
        genreFilter: String? = nil,
        search: String? = nil
    ) throws -> Int {
        try pool.read { db in
            let sortExpression = "CASE WHEN lower(artist) LIKE 'the %' THEN substr(artist, 5) ELSE artist END"
            let comparison = direction == .ascending ? "<" : ">"
            var predicates = [
                "is_available = 1",
                "substr(\(sortExpression), 1, 1) \(comparison) ? COLLATE NOCASE"
            ]
            var arguments: StatementArguments = [value]
            if let genreFilter {
                let genre = try Self.genrePredicate(db: db, column: "genre", canonicalGenre: genreFilter)
                predicates.append(genre.sql)
                arguments += genre.arguments
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                predicates.append("artist LIKE ? ESCAPE '\\' COLLATE NOCASE")
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                arguments += ["%\(escaped)%"]
            }
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT artist COLLATE NOCASE) FROM tracks WHERE \(predicates.joined(separator: " AND "))",
                arguments: arguments
            ) ?? 0
        }
    }

    public func pageTracksForAlbum(
        album: AlbumSummary,
        sort: TrackSort = .album,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let artistExpression = "t.artist"
            let arguments: StatementArguments = [album.name, album.artist]
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks t WHERE t.is_available = 1 AND t.album = ? COLLATE NOCASE AND \(artistExpression) = ? COLLATE NOCASE", arguments: arguments) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t
                WHERE t.is_available = 1 AND t.album = ? COLLATE NOCASE AND \(artistExpression) = ? COLLATE NOCASE
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: pageArguments)
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func upsertTracks(_ imports: [TrackImport], sessionID: Int64) throws -> Int {
        guard !imports.isEmpty else { return 0 }
        return try pool.write { db in
            var changed = 0
            for item in imports {
                if try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                    arguments: [item.identityKey]
                ) == true { continue }
                changed += try Self.upsertTrackAndLog(db: db, item: item, sessionID: sessionID)
            }
            try Self.refreshDimensions(db: db, imports: imports)
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func signature(identityKey: String) throws -> (size: Int64, modifiedAt: Date)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT file_size, modified_at FROM tracks WHERE identity_key = ?",
                arguments: [identityKey]
            ) else { return nil }
            return (row["file_size"], Date(timeIntervalSince1970: row["modified_at"]))
        }
    }

    public func markSeen(identityKey: String, sessionID: Int64) throws {
        try pool.write { db in
            let previous = try Row.fetchOne(
                db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]
            )
            try db.execute(
                sql: "UPDATE tracks SET last_seen_session_id = ?, is_available = 1 WHERE identity_key = ?",
                arguments: [sessionID, identityKey]
            )
            if let previous, previous["is_available"] as Bool == false,
               let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]) {
                try Self.insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
                try Self.pruneActivityLog(db: db)
            }
        }
    }

    public func commitScanBatch(
        imports: [TrackImport],
        unchangedIdentityKeys: [String],
        sessionID: Int64
    ) throws -> Int {
        guard !imports.isEmpty || !unchangedIdentityKeys.isEmpty else { return 0 }
        return try pool.write { db in
            var changed = 0
            for item in imports {
                if try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                    arguments: [item.identityKey]
                ) == true { continue }
                changed += try Self.upsertTrackAndLog(db: db, item: item, sessionID: sessionID)
            }
            for identityKey in unchangedIdentityKeys {
                let previous = try Row.fetchOne(
                    db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]
                )
                try db.execute(
                    sql: "UPDATE tracks SET last_seen_session_id = ?, is_available = 1 WHERE identity_key = ?",
                    arguments: [sessionID, identityKey]
                )
                if let previous, previous["is_available"] as Bool == false,
                   let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]) {
                    try Self.insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
                }
            }
            try Self.refreshDimensions(db: db, imports: imports)
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func markMissingTracks(rootID: Int64, sessionID: Int64) throws -> Int {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO library_activity_log(
                        kind, track_id, root_id, relative_path, absolute_path, filename,
                        title, artist, album, changes_json, occurred_at
                    )
                    SELECT ?, t.id, t.root_id, t.relative_path,
                        CASE WHEN COALESCE(r.last_known_path, '') = '' THEN t.relative_path
                             ELSE rtrim(r.last_known_path, '/') || '/' || t.relative_path END,
                        t.filename, t.title, t.artist, t.album, '[]', ?
                    FROM tracks t
                    LEFT JOIN scan_roots r ON r.id = t.root_id
                    WHERE t.root_id = ? AND t.is_available = 1
                      AND COALESCE(t.last_seen_session_id, 0) <> ?
                    """,
                arguments: [LibraryActivityKind.unavailable.rawValue, Date().timeIntervalSince1970, rootID, sessionID]
            )
            try db.execute(
                sql: "UPDATE tracks SET is_available = 0 WHERE root_id = ? AND is_available = 1 AND COALESCE(last_seen_session_id, 0) <> ?",
                arguments: [rootID, sessionID]
            )
            let changed = db.changesCount
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func addScanRoot(
        displayName: String,
        bookmark: Data,
        volumeUUID: String?,
        path: String
    ) throws -> Int64 {
        let normalizedPath = path.precomposedStringWithCanonicalMapping
        return try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scan_roots(display_name, bookmark, volume_uuid, last_known_path, is_available, created_at)
                    VALUES (?, ?, ?, ?, 1, ?)
                    ON CONFLICT(last_known_path) DO UPDATE SET
                        display_name = excluded.display_name,
                        bookmark = excluded.bookmark,
                        volume_uuid = excluded.volume_uuid,
                        is_available = 1
                    """,
                arguments: [displayName, bookmark, volumeUUID, normalizedPath, Date().timeIntervalSince1970]
            )
            guard let rootID = try Int64.fetchOne(db, sql: "SELECT id FROM scan_roots WHERE last_known_path = ?", arguments: [normalizedPath]) else {
                throw MassiveMusicError.metadataWriteFailed("Failed to resolve scan root ID for path: \(normalizedPath)")
            }
            return rootID
        }
    }

    public func scanRoots() throws -> [ScanRoot] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scan_roots ORDER BY id").map { row in
                ScanRoot(
                    id: row["id"],
                    displayName: row["display_name"],
                    bookmark: row["bookmark"],
                    volumeUUID: row["volume_uuid"],
                    lastKnownPath: row["last_known_path"],
                    isAvailable: row["is_available"]
                )
            }
        }
    }

    public func scanRoot(id: Int64) throws -> ScanRoot? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scan_roots WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return ScanRoot(
                id: row["id"], displayName: row["display_name"], bookmark: row["bookmark"],
                volumeUUID: row["volume_uuid"], lastKnownPath: row["last_known_path"],
                isAvailable: row["is_available"]
            )
        }
    }

    public func setRootAvailability(id: Int64, isAvailable: Bool, path: String? = nil) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE scan_roots SET is_available = ?, last_known_path = COALESCE(?, last_known_path) WHERE id = ?",
                arguments: [isAvailable, path, id]
            )
        }
    }

    public func updateScanRootAuthorization(id: Int64, bookmark: Data, path: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE scan_roots SET bookmark = ?, last_known_path = ?, is_available = 1 WHERE id = ?",
                arguments: [bookmark, path, id]
            )
        }
    }

    public func createScanSession(rootID: Int64, resumeCursor: String? = nil) throws -> Int64 {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scan_sessions(root_id, state, started_at, resume_cursor, discovered, processed, changed_count, skipped, error_count)
                    VALUES (?, 'running', ?, ?, 0, 0, 0, 0, 0)
                    """,
                arguments: [rootID, Date().timeIntervalSince1970, resumeCursor]
            )
            return db.lastInsertedRowID
        }
    }

    public func resumableSession(rootID: Int64) throws -> (id: Int64, cursor: String?)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, resume_cursor FROM scan_sessions
                    WHERE root_id = ? AND state IN ('running', 'paused', 'cancelled', 'failed')
                    ORDER BY id DESC LIMIT 1
                    """,
                arguments: [rootID]
            ) else { return nil }
            return (row["id"], row["resume_cursor"])
        }
    }

    public func updateScanSession(
        id: Int64,
        state: ScanState,
        cursor: String?,
        discovered: Int,
        processed: Int,
        changed: Int,
        skipped: Int,
        errors: Int,
        finished: Bool = false
    ) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE scan_sessions SET state = ?, resume_cursor = ?, discovered = ?, processed = ?,
                        changed_count = ?, skipped = ?, error_count = ?, finished_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    state.rawValue, cursor, discovered, processed, changed, skipped, errors,
                    finished ? Date().timeIntervalSince1970 : nil, id
                ]
            )
        }
    }

    public func recordScanError(sessionID: Int64, path: String, message: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO scan_errors(session_id, path, message, created_at) VALUES (?, ?, ?, ?)",
                arguments: [sessionID, path, String(message.prefix(2_000)), Date().timeIntervalSince1970]
            )
        }
    }

    public func playlists() throws -> [Playlist] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name, COUNT(i.id) AS item_count
                FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
                GROUP BY p.id ORDER BY p.name COLLATE NOCASE
                """)
            return rows.map { Playlist(id: $0["id"], name: $0["name"], itemCount: $0["item_count"]) }
        }
    }

    public func reconcilePlaylistsIfNeeded() throws {
        try pool.write { db in
            let emptyPlaylists = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name FROM playlists p
                LEFT JOIN playlist_items i ON i.playlist_id = p.id
                GROUP BY p.id
                HAVING COUNT(i.id) = 0
            """)
            
            for row in emptyPlaylists {
                let playlistID: Int64 = row["id"]
                let name: String = row["name"]
                
                let albumCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE album = ?", arguments: [name]) ?? 0
                if albumCount > 0 {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO playlist_items(playlist_id, track_id, position, created_at)
                        SELECT ?, id, ROW_NUMBER() OVER (ORDER BY track_number, title) - 1, ?
                        FROM tracks WHERE album = ?
                    """, arguments: [playlistID, Date().timeIntervalSince1970, name])
                }
            }
        }
    }

    public func createPlaylist(name: String) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MassiveMusicError.invalidPlaylistName }
        return try pool.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: "INSERT INTO playlists(name, created_at, updated_at) VALUES (?, ?, ?)",
                arguments: [trimmed, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    public func renamePlaylist(id: Int64, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MassiveMusicError.invalidPlaylistName }
        try pool.write { db in
            try db.execute(
                sql: "UPDATE playlists SET name = ?, updated_at = ? WHERE id = ?",
                arguments: [trimmed, Date().timeIntervalSince1970, id]
            )
        }
    }

    public func deletePlaylist(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM playlists WHERE id = ?", arguments: [id])
        }
    }

    public func addTracks(
        _ trackIDs: any Sequence<Int64>,
        toPlaylist playlistID: Int64,
        progress: (@Sendable (Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> Int {
        var iterator = trackIDs.makeIterator()
        var totalAdded = 0
        var nextPosition = try pool.read { db in
            (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            )) ?? 0
        }
        while isCancelled?() != true {
            var chunk: [Int64] = []
            chunk.reserveCapacity(Self.playlistCommitSize)
            while chunk.count < Self.playlistCommitSize, let id = iterator.next() { chunk.append(id) }
            if chunk.isEmpty { break }
            let added = try pool.write { db in
                var count = 0
                for trackID in chunk {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO playlist_items(playlist_id, track_id, position, created_at) VALUES (?, ?, ?, ?)",
                        arguments: [playlistID, trackID, nextPosition, Date().timeIntervalSince1970]
                    )
                    count += db.changesCount
                    nextPosition += 1
                }
                try db.execute(
                    sql: "UPDATE playlists SET updated_at = ? WHERE id = ?",
                    arguments: [Date().timeIntervalSince1970, playlistID]
                )
                return count
            }
            totalAdded += added
            progress?(totalAdded)
        }
        return totalAdded
    }

    public func playlistTracks(
        playlistID: Int64,
        offset: Int,
        limit: Int = defaultPageSize,
        sort: TrackSort? = nil,
        direction: SortDirection = .ascending
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            ) ?? 0
            let orderSQL = sort.map { Self.orderSQL($0, direction: direction) } ?? "i.position"
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.* FROM playlist_items i
                    JOIN tracks t ON t.id = i.track_id
                    WHERE i.playlist_id = ? ORDER BY \(orderSQL) LIMIT ? OFFSET ?
                    """,
                arguments: [playlistID, limit, max(0, offset)]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: max(0, offset), limit: limit, totalCount: total)
        }
    }

    public func removeTrack(_ trackID: Int64, fromPlaylist playlistID: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM playlist_items WHERE playlist_id = ? AND track_id = ?",
                arguments: [playlistID, trackID]
            )
            try db.execute(
                sql: """
                    WITH ranked AS (
                        SELECT id, ROW_NUMBER() OVER (ORDER BY position, id) - 1 AS new_position
                        FROM playlist_items WHERE playlist_id = ?
                    )
                    UPDATE playlist_items SET position = (SELECT new_position FROM ranked WHERE ranked.id = playlist_items.id)
                    WHERE playlist_id = ?
                    """,
                arguments: [playlistID, playlistID]
            )
        }
    }

    public func movePlaylistItem(playlistID: Int64, from: Int, to: Int) throws {
        guard from != to else { return }
        try pool.write { db in
            guard let itemID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM playlist_items WHERE playlist_id = ? AND position = ?",
                arguments: [playlistID, from]
            ) else { return }
            let temporaryOffset = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), 0) + 2 FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            )) ?? 2
            try db.execute(sql: "UPDATE playlist_items SET position = -1 WHERE id = ?", arguments: [itemID])
            if from < to {
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position + ? WHERE playlist_id = ? AND position > ? AND position <= ?",
                    arguments: [temporaryOffset, playlistID, from, to]
                )
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position - ? - 1 WHERE playlist_id = ? AND position > ? AND position <= ?",
                    arguments: [temporaryOffset, playlistID, temporaryOffset + from, temporaryOffset + to]
                )
            } else {
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position + ? WHERE playlist_id = ? AND position >= ? AND position < ?",
                    arguments: [temporaryOffset, playlistID, to, from]
                )
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position - ? + 1 WHERE playlist_id = ? AND position >= ? AND position < ?",
                    arguments: [temporaryOffset, playlistID, temporaryOffset + to, temporaryOffset + from]
                )
            }
            try db.execute(sql: "UPDATE playlist_items SET position = ? WHERE id = ?", arguments: [to, itemID])
        }
    }

    public func shuffleCandidates(afterID: Int64, seed: Int64, limit: Int = 100) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let bucket = abs(seed % 997)
        return try pool.read { db in
            var rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1 AND id > ?
                      AND ((id * 1103515245 + ?) & 2147483647) % 997 = ?
                    ORDER BY id LIMIT ?
                    """,
                arguments: [afterID, seed, bucket, limit]
            )
            if rows.count < limit {
                let remainder = limit - rows.count
                let wrapped = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM tracks
                        WHERE is_available = 1 AND id <= ?
                          AND ((id * 1103515245 + ?) & 2147483647) % 997 = ?
                        ORDER BY id LIMIT ?
                        """,
                    arguments: [afterID, seed, bucket, remainder]
                )
                rows.append(contentsOf: wrapped)
            }
            return rows.map(Self.decodeTrack)
        }
    }

    public func randomTrack(
        rootIDs: [Int64],
        seed: Int64,
        excludingTrackID: Int64? = nil
    ) throws -> Track? {
        let uniqueRootIDs = Array(Set(rootIDs)).sorted()
        guard !uniqueRootIDs.isEmpty else { return nil }
        let placeholders = Array(repeating: "?", count: uniqueRootIDs.count).joined(separator: ",")
        return try pool.read { db in
            try Self.randomTrack(
                in: db,
                fromSQL: "tracks t",
                whereSQL: "t.is_available = 1 AND t.root_id IN (\(placeholders))",
                arguments: StatementArguments(uniqueRootIDs),
                seed: seed,
                excludingTrackID: excludingTrackID
            )
        }
    }

    public func randomCachedTrack(seed: Int64, excludingTrackID: Int64? = nil) throws -> Track? {
        try pool.read { db in
            try Self.randomTrack(
                in: db,
                fromSQL: "tracks t JOIN local_cache c ON c.track_id = t.id",
                whereSQL: "1 = 1",
                arguments: [],
                seed: seed,
                excludingTrackID: excludingTrackID
            )
        }
    }

    private static func randomTrack(
        in db: Database,
        fromSQL: String,
        whereSQL: String,
        arguments: StatementArguments,
        seed: Int64,
        excludingTrackID: Int64?
    ) throws -> Track? {
        guard let maxID = try Int64.fetchOne(
            db,
            sql: "SELECT MAX(t.id) FROM \(fromSQL) WHERE \(whereSQL)",
            arguments: arguments
        ) else { return nil }

        let upperBound = UInt64(maxID) &+ 1
        let targetID = upperBound == 0 ? 0 : Int64(UInt64(bitPattern: seed) % upperBound)
        var candidateWhere = whereSQL
        var candidateArguments = arguments
        if let excludingTrackID {
            candidateWhere += " AND t.id <> ?"
            candidateArguments += [excludingTrackID]
        }

        var afterArguments = candidateArguments
        afterArguments += [targetID]
        let after = try Row.fetchOne(
            db,
            sql: "SELECT t.* FROM \(fromSQL) WHERE \(candidateWhere) AND t.id >= ? ORDER BY t.id LIMIT 1",
            arguments: afterArguments
        )
        if let after { return Self.decodeTrack(after) }

        let wrapped = try Row.fetchOne(
            db,
            sql: "SELECT t.* FROM \(fromSQL) WHERE \(candidateWhere) ORDER BY t.id LIMIT 1",
            arguments: candidateArguments
        )
        if let wrapped { return Self.decodeTrack(wrapped) }

        // A one-track library should continue playing instead of becoming empty
        // merely because that track is also the current one.
        let fallback = try Row.fetchOne(
            db,
            sql: "SELECT t.* FROM \(fromSQL) WHERE \(whereSQL) ORDER BY t.id LIMIT 1",
            arguments: arguments
        )
        return fallback.map(Self.decodeTrack)
    }

    public func adjacentTrack(to id: Int64, direction: Int) throws -> Track? {
        try pool.read { db in
            let comparison = direction >= 0 ? ">" : "<"
            let ordering = direction >= 0 ? "ASC" : "DESC"
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE is_available = 1 AND id \(comparison) ? ORDER BY id \(ordering) LIMIT 1",
                arguments: [id]
            ) ?? Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE is_available = 1 ORDER BY id \(ordering) LIMIT 1"
            )
            return row.map(Self.decodeTrack)
        }
    }

    public func adjacentTrack(
        in context: TrackPlaybackContext,
        from current: Track,
        direction: Int,
        wraps: Bool = false
    ) throws -> Track? {
        let forward = direction >= 0
        let queryDirection: SortDirection
        if forward {
            queryDirection = context.direction
        } else {
            queryDirection = context.direction == .ascending ? .descending : .ascending
        }
        let cursor = Self.cursorPredicate(
            sort: context.sort,
            direction: queryDirection,
            cursor: current
        )

        return try pool.read { db in
            var from = "tracks t"
            var predicates: [String] = []
            var arguments: StatementArguments = []

            switch context.scope {
            case let .library(query):
                Self.searchFilter(for: query)?.apply(from: &from, whereParts: &predicates, arguments: &arguments, tableAlias: "t")
            case let .recentlyAdded(query):
                Self.searchFilter(for: query)?.apply(from: &from, whereParts: &predicates, arguments: &arguments, tableAlias: "t")
            case let .history(query):
                predicates.append("t.last_played_at IS NOT NULL")
                Self.searchFilter(for: query)?.apply(from: &from, whereParts: &predicates, arguments: &arguments, tableAlias: "t")
            case let .album(name, artist):
                predicates += [
                    "t.is_available = 1",
                    "t.album = ? COLLATE NOCASE",
                    "COALESCE(NULLIF(t.album_artist, ''), t.artist) = ? COLLATE NOCASE"
                ]
                arguments += [name, artist]
            case let .artist(name):
                predicates += ["t.is_available = 1", "t.artist = ? COLLATE NOCASE"]
                arguments += [name]
            case let .genre(name):
                let genre = try Self.genrePredicate(db: db, column: "t.genre", canonicalGenre: name)
                predicates += ["t.is_available = 1", genre.sql]
                arguments += genre.arguments
            case .favorites:
                predicates.append("t.is_favorite = 1")
            case let .cache(query):
                from = "local_cache c JOIN tracks t ON t.id = c.track_id"
                Self.searchFilter(for: query)?.apply(from: &from, whereParts: &predicates, arguments: &arguments, tableAlias: "t")
            case let .playlist(id):
                from = "playlist_items i JOIN tracks t ON t.id = i.track_id"
                predicates.append("i.playlist_id = ?")
                arguments += [id]
            case let .metadataIssue(kind):
                guard kind != .suspectedVariations else { return nil }
                predicates.append(Self.metadataIssuePredicate(kind))
            case let .metadataValue(field, value):
                let column = switch field {
                case .title: "title"
                case .artist: "artist"
                case .album: "album"
                case .genre: "genre"
                case .comment: "comment"
                }
                predicates.append("t.\(column) = ?")
                arguments += [value]
            }

            let boundaryPredicates = predicates
            let boundaryArguments = arguments
            predicates.append(cursor.sql)
            arguments += cursor.arguments
            let whereSQL = " WHERE " + predicates.joined(separator: " AND ")
            var row = try Row.fetchOne(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(context.sort, direction: queryDirection)) LIMIT 1",
                arguments: arguments
            )
            if row == nil, wraps {
                let boundaryWhereSQL = boundaryPredicates.isEmpty
                    ? ""
                    : " WHERE " + boundaryPredicates.joined(separator: " AND ")
                row = try Row.fetchOne(
                    db,
                    sql: "SELECT t.* FROM \(from)\(boundaryWhereSQL) ORDER BY \(Self.orderSQL(context.sort, direction: queryDirection)) LIMIT 1",
                    arguments: boundaryArguments
                )
            }
            return row.map(Self.decodeTrack)
        }
    }

    public func trackID(relativeOrAbsolutePath path: String) throws -> Int64? {
        try pool.read { db in
            if let id = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tracks WHERE relative_path = ? LIMIT 1",
                arguments: [path]
            ) { return id }
            return try Int64.fetchOne(
                db,
                sql: """
                    SELECT t.id FROM tracks t JOIN scan_roots r ON r.id = t.root_id
                    WHERE r.last_known_path || '/' || t.relative_path = ? LIMIT 1
                    """,
                arguments: [path]
            )
        }
    }

    public func insertSyntheticTracks(count: Int, rootID: Int64 = 1) throws -> Int {
        guard count > 0 else { return 0 }
        var inserted = 0
        while inserted < count {
            let upperBound = min(inserted + Self.playlistCommitSize, count)
            try pool.write { db in
                for index in inserted..<upperBound {
                    let artist = "Artist \(index % 12_000)"
                    let album = "Album \(index % 48_000)"
                    let genre = "Genre \(index % 40)"
                    let identity = "synthetic:\(index)"
                    try db.execute(
                        sql: SQL.upsertTrack,
                        arguments: [
                            rootID, identity, nil, "Synthetic/\(index / 1_000)/track-\(index).mp3",
                            "track-\(index).mp3", "Synthetic Track \(index)", artist, album, artist,
                            genre, "", false, 1, (index % 20) + 1, Double(120 + index % 300), 4_000_000,
                            1_700_000_000 + Double(index), "mp3", 320_000, index % 3 == 0, true,
                            1_700_000_000 + Double(index), 0, ""
                        ]
                    )
                }
            }
            inserted = upperBound
        }
        return inserted
    }

    public func benchmarkSynthetic(count: Int) throws -> SyntheticBenchmarkResult {
        let insertStart = ContinuousClock.now
        let before = try trackCount()
        _ = try insertSyntheticTracks(count: count)
        let insertDuration = ContinuousClock.now - insertStart

        let searchStart = ContinuousClock.now
        _ = try pageTracks(query: "Synthetic Track 359", limit: 100)
        let searchDuration = ContinuousClock.now - searchStart

        let firstPage = try pageTracksAfter(sort: .artist, after: nil, limit: 200)
        let pageStart = ContinuousClock.now
        _ = try pageTracksAfter(
            sort: .artist, after: firstPage.tracks.last, logicalOffset: 200,
            limit: 200, knownTotal: firstPage.totalCount
        )
        let pageDuration = ContinuousClock.now - pageStart

        let deepOffsetStart = ContinuousClock.now
        _ = try pageTracks(sort: .artist, offset: max(0, count - 200), limit: 200)
        let deepOffsetDuration = ContinuousClock.now - deepOffsetStart
        let playlistStart = ContinuousClock.now
        let playlistID = try createPlaylist(name: "100k benchmark")
        let playlistCount = min(count, 100_000)
        _ = try addTracks(Int64(1)...Int64(playlistCount), toPlaylist: playlistID)
        let playlistDuration = ContinuousClock.now - playlistStart
        let playlistPageStart = ContinuousClock.now
        _ = try playlistTracks(playlistID: playlistID, offset: max(0, playlistCount - 200), limit: 200)
        let playlistPageDuration = ContinuousClock.now - playlistPageStart
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return SyntheticBenchmarkResult(
            requestedCount: count,
            insertedCount: try trackCount() - before,
            insertSeconds: Self.seconds(insertDuration),
            searchMilliseconds: Self.seconds(searchDuration) * 1_000,
            pageMilliseconds: Self.seconds(pageDuration) * 1_000,
            deepOffsetMilliseconds: Self.seconds(deepOffsetDuration) * 1_000,
            playlist100kSeconds: Self.seconds(playlistDuration),
            playlistPageMilliseconds: Self.seconds(playlistPageDuration) * 1_000,
            databaseBytes: bytes,
            generatedAt: Date()
        )
    }

    public func inTransactionForTesting(_ operation: @escaping @Sendable () throws -> Void) throws {
        try pool.write { _ in try operation() }
    }

    public func rollbackProbeForTesting() throws -> Bool {
        enum ProbeError: Error { case expected }
        let identity = "rollback-probe-\(UUID().uuidString)"
        do {
            try pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO tracks(
                            root_id, identity_key, relative_path, filename, title, file_size,
                            modified_at, format, added_at
                        ) VALUES (0, ?, 'probe.mp3', 'probe.mp3', 'Probe', 1, 0, 'mp3', 0)
                        """,
                    arguments: [identity]
                )
                throw ProbeError.expected
            }
        } catch ProbeError.expected {
            // Expected: GRDB must roll the transaction back.
        }
        return try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE identity_key = ?", arguments: [identity]) == 0
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// Resolves a canonical genre against the small set of distinct genre labels,
    /// then lets SQLite use its regular genre index for the track query. This keeps
    /// punctuation/language aliases together without running Swift normalization
    /// across every row in a large library.
    private static func genrePredicate(
        db: Database,
        column: String,
        canonicalGenre: String
    ) throws -> (sql: String, arguments: StatementArguments) {
        let canonical = GenreNormalizer.normalize(canonicalGenre)
        let rawGenres = try String.fetchAll(db, sql: """
            SELECT genre FROM tracks
            WHERE trim(genre) <> ''
            GROUP BY genre COLLATE NOCASE
            """)
        var aliases = rawGenres.filter { GenreNormalizer.normalize($0) == canonical }
        if aliases.isEmpty { aliases = [canonical] }

        let placeholders = Array(repeating: "?", count: aliases.count).joined(separator: ", ")
        var arguments: StatementArguments = []
        for alias in aliases { arguments += [alias] }
        return ("\(column) COLLATE NOCASE IN (\(placeholders))", arguments)
    }

    /// Genre cardinality is small compared with track cardinality, so merge raw
    /// labels in Swift after SQLite has reduced the library to one row per label.
    private static func canonicalGenreFacetPage(
        db: Database,
        query: String?,
        offset: Int,
        limit: Int
    ) throws -> FacetPage {
        let rows = try Row.fetchAll(db, sql: """
            SELECT genre AS name, COUNT(*) AS count
            FROM tracks
            WHERE is_available = 1 AND trim(genre) <> ''
            GROUP BY genre COLLATE NOCASE
            """)
        var counts: [String: Int] = [:]
        for row in rows {
            let rawName: String = row["name"]
            let count: Int = row["count"]
            let canonical = GenreNormalizer.normalize(rawName)
            guard !canonical.isEmpty else { continue }
            counts[canonical, default: 0] += count
        }

        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sorted = counts
            .filter { trimmedQuery.isEmpty || $0.key.localizedCaseInsensitiveContains(trimmedQuery) }
            .map { Facet(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        let safeOffset = min(max(0, offset), sorted.count)
        let end = min(safeOffset + limit, sorted.count)
        return FacetPage(
            facets: Array(sorted[safeOffset..<end]),
            offset: safeOffset,
            limit: limit,
            totalCount: sorted.count
        )
    }

    private static func orderSQL(_ sort: TrackSort, direction: SortDirection) -> String {
        let order = direction == .ascending ? "ASC" : "DESC"
        return switch sort {
        case .title: "t.title COLLATE NOCASE \(order), t.id \(order)"
        case .artist: "t.artist COLLATE NOCASE \(order), t.album COLLATE NOCASE \(order), t.disc_number \(order), t.track_number \(order), t.id \(order)"
        case .album: "t.album COLLATE NOCASE \(order), t.disc_number \(order), t.track_number \(order), t.id \(order)"
        case .genre: "t.genre COLLATE NOCASE \(order), t.title COLLATE NOCASE \(order), t.id \(order)"
        case .year: "t.year COLLATE NOCASE \(order), t.title COLLATE NOCASE \(order), t.id \(order)"
        case .discNumber: "COALESCE(t.disc_number, -1) \(order), COALESCE(t.track_number, -1) \(order), t.id \(order)"
        case .trackNumber: "COALESCE(t.track_number, -1) \(order), COALESCE(t.disc_number, -1) \(order), t.id \(order)"
        case .dateAdded: "t.added_at \(order), t.id \(order)"
        case .path: "t.relative_path COLLATE NOCASE \(order), t.id \(order)"
        case .duration: "t.duration \(order), t.id \(order)"
        case .format: "t.format COLLATE NOCASE \(order), t.title COLLATE NOCASE \(order), t.id \(order)"
        }
    }

    private static func metadataIssuePredicate(_ kind: MetadataIssueKind, field: MetadataField? = nil) -> String {
        let metadataText = switch field {
        case .title: "COALESCE(t.title, '')"
        case .artist: "COALESCE(t.artist, '')"
        case .album: "COALESCE(t.album, '')"
        case .genre: "COALESCE(t.genre, '')"
        case .comment: "COALESCE(t.comment, '')"
        case nil: "COALESCE(t.title, '') || ' ' || COALESCE(t.artist, '') || ' ' || COALESCE(t.album, '') || ' ' || COALESCE(t.album_artist, '') || ' ' || COALESCE(t.genre, '') || ' ' || COALESCE(t.comment, '') || ' ' || COALESCE(t.filename, '') || ' ' || COALESCE(t.relative_path, '')"
        }
        return switch kind {
        case .missingTitle: "trim(t.title) = ''"
        case .missingArtist: "trim(t.artist) = ''"
        case .missingAlbum: "trim(t.album) = ''"
        case .missingYear: "trim(t.year) = ''"
        case .commentInMP3: "lower(t.format) = 'mp3' AND trim(t.comment) != ''"
        case .urlInMP3Metadata:
            """
            lower(t.format) = 'mp3' AND (
                instr(lower(\(metadataText)), 'http://') > 0
                OR instr(lower(\(metadataText)), 'https://') > 0
                OR instr(lower(\(metadataText)), 'www.') > 0
                OR instr(lower(\(metadataText)), '://') > 0
                OR instr(lower(\(metadataText)), '.com/') > 0
                OR instr(lower(\(metadataText)), '.net/') > 0
                OR instr(lower(\(metadataText)), '.org/') > 0
                OR instr(lower(\(metadataText)), '.ru/') > 0
                OR instr(lower(\(metadataText)), '.io/') > 0
                OR lower(\(metadataText)) LIKE '%.com'
                OR lower(\(metadataText)) LIKE '%.net'
                OR lower(\(metadataText)) LIKE '%.org'
                OR lower(\(metadataText)) LIKE '%.com %'
                OR lower(\(metadataText)) LIKE '%.net %'
                OR lower(\(metadataText)) LIKE '%.org %'
            )
            """
        case .suspectedMojibake:
            """
            instr(\(metadataText), '�') > 0
            OR instr(\(metadataText), 'Ã') > 0
            OR instr(\(metadataText), 'Â') > 0
            OR instr(\(metadataText), 'â€') > 0
            OR instr(\(metadataText), 'ÔÌ') > 0
            OR instr(\(metadataText), '¼') > 0
            OR instr(\(metadataText), '縺') > 0
            OR instr(\(metadataText), '繧') > 0
            OR instr(\(metadataText), '譁') > 0
            """
        case .duplicateTracks:
            """
            EXISTS (
                SELECT 1 FROM tracks t2
                WHERE t2.is_available = 1 AND t2.id <> t.id
                  AND t2.title = t.title COLLATE NOCASE
                  AND t2.artist = t.artist COLLATE NOCASE
                  AND t2.album = t.album COLLATE NOCASE
            )
            """
        case .suspectedVariations: "0"
        case .corruptedOrEmpty: "t.duration <= 0 OR t.is_available = 0"
        }
    }

    private static let duplicateMetadataTracksCTE = """
        WITH duplicate_keys AS (
            SELECT title, artist, album
            FROM tracks
            WHERE is_available = 1
            GROUP BY title COLLATE NOCASE, artist COLLATE NOCASE, album COLLATE NOCASE
            HAVING COUNT(*) > 1
        )
        """

    private static let duplicateMetadataJoinSQL = """
        FROM tracks t
        JOIN duplicate_keys d
          ON t.title = d.title COLLATE NOCASE
         AND t.artist = d.artist COLLATE NOCASE
         AND t.album = d.album COLLATE NOCASE
        WHERE t.is_available = 1
        """

    private static let duplicateMetadataCountSQL = """
        SELECT COALESCE(SUM(track_count), 0)
        FROM (
            SELECT COUNT(*) AS track_count
            FROM tracks
            WHERE is_available = 1
            GROUP BY title COLLATE NOCASE, artist COLLATE NOCASE, album COLLATE NOCASE
            HAVING COUNT(*) > 1
        )
        """

    private static func metadataColumn(_ field: MetadataField) -> String {
        switch field {
        case .title: "title"
        case .artist: "artist"
        case .album: "album"
        case .genre: "genre"
        case .comment: "comment"
        }
    }

    public struct SearchFilter: Sendable {
        public enum MatchKind: Sendable {
            case fts(pattern: String)
            case regex(pattern: String)
        }
        public let kind: MatchKind

        public func apply(
            from: inout String,
            whereParts: inout [String],
            arguments: inout StatementArguments,
            tableAlias: String = "t"
        ) {
            switch kind {
            case .fts(let pattern):
                from += " JOIN tracks_fts f ON f.rowid = \(tableAlias).id"
                whereParts.append("tracks_fts MATCH ?")
                arguments += [pattern]
            case .regex(let pattern):
                whereParts.append("(\(tableAlias).title REGEXP ? OR \(tableAlias).artist REGEXP ? OR \(tableAlias).album REGEXP ? OR \(tableAlias).genre REGEXP ? OR \(tableAlias).filename REGEXP ?)")
                arguments += [pattern, pattern, pattern, pattern, pattern]
            }
        }
    }

    public static func searchFilter(for query: String, defaultField: MetadataField? = nil) -> SearchFilter? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") && trimmed.hasSuffix("/") && trimmed.count >= 2 {
            let pattern = String(trimmed.dropFirst().dropLast())
            if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) != nil {
                return SearchFilter(kind: .regex(pattern: pattern))
            }
        } else if trimmed.lowercased().hasPrefix("regex:") {
            let pattern = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) != nil {
                return SearchFilter(kind: .regex(pattern: pattern))
            }
        } else if trimmed.lowercased().hasPrefix("r:") {
            let pattern = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) != nil {
                return SearchFilter(kind: .regex(pattern: pattern))
            }
        }

        guard let fts = parseFTSQuery(trimmed, defaultField: defaultField) else { return nil }
        return SearchFilter(kind: .fts(pattern: fts))
    }

    private static func parseFTSQuery(_ query: String, defaultField: MetadataField? = nil) -> String? {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for char in query {
            if char == "\"" || char == "“" || char == "”" {
                inQuotes.toggle()
                current.append("\"")
            } else if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            if inQuotes { current.append("\"") }
            tokens.append(current)
        }

        guard !tokens.isEmpty else { return nil }

        let defaultPrefix: String = switch defaultField {
        case .title: "title:"
        case .artist: "artist:"
        case .album: "album:"
        case .genre: "genre:"
        case .comment: "comment:"
        case .none: ""
        }

        // 単純な複数単語（クォートなし、演算子なし）の場合、フレーズ検索または同一フィールドANDを優先
        let hasOperators = tokens.contains { t in
            let u = t.uppercased()
            return u == "OR" || u == "AND" || u == "NOT" || t == "|" || t == "&" || t.hasPrefix("-") || t.contains(":")
        }

        if !hasOperators && tokens.count > 1 && !inQuotes {
            // 例: "kiss me" -> title: ("kiss" "me"*) OR album: ("kiss" "me"*) OR artist: ("kiss" "me"*) OR ("kiss" AND "me"*)
            let terms = tokens.map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            let exactPhrase = terms.map { "\"\($0)\"" }.joined(separator: " ")
            let andTerms = terms.map { "\"\($0)\"" }.joined(separator: " AND ")
            if !defaultPrefix.isEmpty {
                return "(\(defaultPrefix)\"\(terms.joined(separator: " "))\" OR (\(defaultPrefix)(\(exactPhrase))) OR (\(defaultPrefix)(\(andTerms))))"
            }
            return "(\"\(terms.joined(separator: " "))\" OR (title: \(exactPhrase)) OR (album: \(exactPhrase)) OR (artist: \(exactPhrase)) OR (\(andTerms)))"
        }

        var clauses: [String] = []
        var nextOp: String? = nil

        for (index, rawToken) in tokens.enumerated() {
            let upper = rawToken.uppercased()
            if upper == "OR" || rawToken == "|" {
                nextOp = "OR"
                continue
            }
            if upper == "AND" || rawToken == "&" {
                nextOp = "AND"
                continue
            }
            if upper == "NOT" {
                nextOp = "NOT"
                continue
            }

            var isNot = false
            var token = rawToken
            if token.hasPrefix("-") && token.count > 1 {
                isNot = true
                token = String(token.dropFirst())
            }

            var columnPrefix = defaultPrefix
            let lower = token.lowercased()
            if lower.hasPrefix("artist:") || lower.hasPrefix("a:") {
                let split = token.split(separator: ":", maxSplits: 1)
                if split.count == 2 {
                    columnPrefix = "artist:"
                    token = String(split[1])
                }
            } else if lower.hasPrefix("album:") || lower.hasPrefix("al:") {
                let split = token.split(separator: ":", maxSplits: 1)
                if split.count == 2 {
                    columnPrefix = "album:"
                    token = String(split[1])
                }
            } else if lower.hasPrefix("title:") || lower.hasPrefix("t:") {
                let split = token.split(separator: ":", maxSplits: 1)
                if split.count == 2 {
                    columnPrefix = "title:"
                    token = String(split[1])
                }
            } else if lower.hasPrefix("genre:") || lower.hasPrefix("g:") {
                let split = token.split(separator: ":", maxSplits: 1)
                if split.count == 2 {
                    columnPrefix = "genre:"
                    token = String(split[1])
                }
            }

            guard !token.isEmpty else { continue }

            let clause: String
            if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
                let inner = token.dropFirst().dropLast().replacingOccurrences(of: "\"", with: "\"\"")
                clause = columnPrefix.isEmpty ? "\"\(inner)\"" : "\(columnPrefix)\"\(inner)\""
            } else {
                let clean = token.replacingOccurrences(of: "\"", with: "\"\"")
                let isLastToken = (index == tokens.count - 1)
                let usePrefix = isLastToken && clean.count >= 3
                let termPattern = usePrefix ? "\"\(clean)\"*" : "\"\(clean)\""
                clause = columnPrefix.isEmpty ? termPattern : "\(columnPrefix)\(termPattern)"
            }

            if clauses.isEmpty {
                if isNot || nextOp == "NOT" {
                    clauses.append("NOT \(clause)")
                } else {
                    clauses.append(clause)
                }
            } else {
                let op = nextOp ?? (isNot ? "NOT" : "AND")
                clauses.append("\(op) \(clause)")
            }
            nextOp = nil
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " ")
    }

    private static func ftsPattern(_ query: String) -> String? {
        guard let filter = searchFilter(for: query) else { return nil }
        if case .fts(let pattern) = filter.kind { return pattern }
        return nil
    }

    private static func cursorPredicate(sort: TrackSort, direction: SortDirection, cursor: Track) -> (sql: String, arguments: StatementArguments) {
        let comparison = direction == .ascending ? ">" : "<"
        switch sort {
        case .title:
            return (
                "(t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ?)",
                [cursor.title, cursor.id]
            )
        case .artist:
            return (
                """
                (t.artist COLLATE NOCASE, t.album COLLATE NOCASE, COALESCE(t.disc_number, -1),
                 COALESCE(t.track_number, -1), t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?, ?, ?)
                """,
                [cursor.artist, cursor.album, cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .album:
            return (
                """
                (t.album COLLATE NOCASE, COALESCE(t.disc_number, -1), COALESCE(t.track_number, -1), t.id)
                \(comparison) (? COLLATE NOCASE, ?, ?, ?)
                """,
                [cursor.album, cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .genre:
            return (
                "(t.genre COLLATE NOCASE, t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?)",
                [cursor.genre, cursor.title, cursor.id]
            )
        case .year:
            return (
                "(t.year COLLATE NOCASE, t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?)",
                [cursor.year, cursor.title, cursor.id]
            )
        case .discNumber:
            return (
                "(COALESCE(t.disc_number, -1), COALESCE(t.track_number, -1), t.id) \(comparison) (?, ?, ?)",
                [cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .trackNumber:
            return (
                "(COALESCE(t.track_number, -1), COALESCE(t.disc_number, -1), t.id) \(comparison) (?, ?, ?)",
                [cursor.trackNumber ?? -1, cursor.discNumber ?? -1, cursor.id]
            )
        case .dateAdded:
            return ("(t.added_at, t.id) \(comparison) (?, ?)", [cursor.addedAt.timeIntervalSince1970, cursor.id])
        case .path:
            return (
                "(t.relative_path COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ?)",
                [cursor.relativePath, cursor.id]
            )
        case .duration:
            return ("(t.duration, t.id) \(comparison) (?, ?)", [cursor.duration, cursor.id])
        case .format:
            return (
                "(t.format COLLATE NOCASE, t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?)",
                [cursor.format, cursor.title, cursor.id]
            )
        }
    }

    private static func decodeTrack(_ row: Row) -> Track {
        Track(
            id: row["id"], rootID: row["root_id"], relativePath: row["relative_path"],
            filename: row["filename"], title: row["title"], artist: row["artist"],
            album: row["album"], albumArtist: row["album_artist"], genre: row["genre"],
            year: row.hasColumn("year") ? (row["year"] ?? "") : "",
            isCompilation: row.hasColumn("is_compilation") ? row["is_compilation"] : false,
            discNumber: row["disc_number"], trackNumber: row["track_number"],
            duration: row["duration"], fileSize: row["file_size"],
            modifiedAt: Date(timeIntervalSince1970: row["modified_at"]), format: row["format"],
            bitrate: row["bitrate"], hasArtwork: row["has_artwork"], isAvailable: row["is_available"],
            addedAt: Date(timeIntervalSince1970: row["added_at"]),
            isFavorite: row.hasColumn("is_favorite") ? row["is_favorite"] : false,
            comment: row.hasColumn("comment") ? (row["comment"] ?? "") : ""
        )
    }

    private static func decodeMusicBrainzAutoFillAttempt(_ row: Row) -> MusicBrainzAutoFillAttempt? {
        guard let status = MusicBrainzAutoFillStatus(rawValue: row["status"]) else { return nil }
        let retryTimestamp: Double? = row["retry_after"]
        return MusicBrainzAutoFillAttempt(
            albumKey: row["album_key"],
            fingerprint: row["fingerprint"],
            artist: row["artist"],
            album: row["album"],
            status: status,
            attemptCount: row["attempt_count"],
            retryAfter: retryTimestamp.map(Date.init(timeIntervalSince1970:)),
            lastError: row["last_error"],
            attemptedAt: Date(timeIntervalSince1970: row["attempted_at"])
        )
    }

    private static func decodeActivityEvent(_ row: Row) -> LibraryActivityEvent {
        let json: String = row["changes_json"]
        let changes = (try? JSONDecoder().decode(
            [LibraryActivityChange].self, from: Data(json.utf8)
        )) ?? []
        return LibraryActivityEvent(
            id: row["id"],
            kind: LibraryActivityKind(rawValue: row["kind"]) ?? .fileModified,
            trackID: row["track_id"],
            filename: row["filename"],
            title: row["title"],
            artist: row["artist"],
            album: row["album"],
            relativePath: row["relative_path"],
            absolutePath: row["absolute_path"],
            changes: changes,
            occurredAt: Date(timeIntervalSince1970: row["occurred_at"])
        )
    }

    private static func upsertTrackAndLog(
        db: Database, item: TrackImport, sessionID: Int64
    ) throws -> Int {
        let track = item.track
        try db.execute(sql: """
            DELETE FROM tracks 
            WHERE root_id = ? AND relative_path = ? AND identity_key <> ?
            """, arguments: [track.rootID, track.relativePath, item.identityKey])

        let previous = try Row.fetchOne(
            db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [item.identityKey]
        )
        try db.execute(
            sql: SQL.upsertTrack,
            arguments: [
                track.rootID, item.identityKey, item.fileResourceID, track.relativePath, track.filename,
                track.title, track.artist, track.album, track.albumArtist, GenreNormalizer.normalize(track.genre), track.year, track.isCompilation,
                track.discNumber, track.trackNumber, track.duration, track.fileSize,
                track.modifiedAt.timeIntervalSince1970, track.format, track.bitrate,
                track.hasArtwork, track.isAvailable, track.addedAt.timeIntervalSince1970, sessionID,
                track.comment
            ]
        )
        let changed = db.changesCount
        guard let updated = try Row.fetchOne(
            db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [item.identityKey]
        ) else { return changed }
        if previous == nil {
            try insertActivity(db: db, kind: .added, trackRow: updated, changes: [])
        } else {
            let changes = activityChanges(from: previous, to: updated)
            if !changes.isEmpty {
                try insertActivity(db: db, kind: .fileModified, trackRow: updated, changes: changes)
            } else if let previous, previous["is_available"] as Bool == false {
                try insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
            }
        }
        return changed
    }

    private static func activityChanges(from previous: Row?, to updated: Row) -> [LibraryActivityChange] {
        guard let previous else { return [] }
        var changes: [LibraryActivityChange] = []
        func append(_ field: String, _ oldValue: String, _ newValue: String) {
            guard oldValue != newValue else { return }
            changes.append(.init(field: field, oldValue: oldValue, newValue: newValue))
        }
        for field in ["title", "artist", "album", "album_artist", "genre", "relative_path", "filename", "format"] {
            append(field, previous[field] as String, updated[field] as String)
        }
        for field in ["disc_number", "track_number", "bitrate"] {
            let old: Int? = previous[field]
            let new: Int? = updated[field]
            append(field, old.map(String.init) ?? "", new.map(String.init) ?? "")
        }
        let oldSize: Int64 = previous["file_size"]
        let newSize: Int64 = updated["file_size"]
        append("file_size", String(oldSize), String(newSize))
        let oldModified: Double = previous["modified_at"]
        let newModified: Double = updated["modified_at"]
        append("modified_at", String(oldModified), String(newModified))
        let oldArtwork: Bool = previous["has_artwork"]
        let newArtwork: Bool = updated["has_artwork"]
        append("has_artwork", String(oldArtwork), String(newArtwork))
        let oldCompilation: Bool = previous.hasColumn("is_compilation") ? previous["is_compilation"] : false
        let newCompilation: Bool = updated.hasColumn("is_compilation") ? updated["is_compilation"] : false
        append("is_compilation", String(oldCompilation), String(newCompilation))
        return changes
    }

    private static func insertActivity(
        db: Database, kind: LibraryActivityKind, trackRow: Row,
        changes: [LibraryActivityChange], absolutePathOverride: String? = nil
    ) throws {
        let rootID: Int64 = trackRow["root_id"]
        let relativePath: String = trackRow["relative_path"]
        let rootPath = try String.fetchOne(
            db, sql: "SELECT last_known_path FROM scan_roots WHERE id = ?", arguments: [rootID]
        ) ?? ""
        let absolutePath = absolutePathOverride ?? (rootPath.isEmpty
            ? relativePath
            : URL(fileURLWithPath: rootPath, isDirectory: true).appending(path: relativePath).path)
        let data = try JSONEncoder().encode(changes)
        let changesJSON = String(decoding: data, as: UTF8.self)
        try db.execute(
            sql: """
                INSERT INTO library_activity_log(
                    kind, track_id, root_id, relative_path, absolute_path, filename,
                    title, artist, album, changes_json, occurred_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                kind.rawValue, trackRow["id"] as Int64, rootID, relativePath, absolutePath,
                trackRow["filename"] as String, trackRow["title"] as String,
                trackRow["artist"] as String, trackRow["album"] as String,
                changesJSON, Date().timeIntervalSince1970
            ]
        )
    }

    public func pruneActivityLog(maximumCount: Int = 5_000, batchSize: Int = 1_000) throws {
        try pool.write { db in
            try Self.pruneActivityLog(db: db, maximumCount: maximumCount, batchSize: batchSize)
        }
    }

    private static func pruneActivityLog(db: Database, maximumCount: Int = 5_000, batchSize: Int = 1_000) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM library_activity_log") ?? 0
        guard count >= maximumCount + batchSize else { return }
        let pruneCount = count - maximumCount
        try db.execute(
            sql: """
                DELETE FROM library_activity_log
                WHERE id IN (
                    SELECT id FROM library_activity_log
                    ORDER BY occurred_at ASC, id ASC
                    LIMIT ?
                )
                """,
            arguments: [pruneCount]
        )
    }

    private static func refreshDimensions(db: Database, imports: [TrackImport]) throws {
        for item in imports {
            let track = item.track
            if !track.artist.isEmpty {
                try db.execute(sql: "INSERT OR IGNORE INTO artists(name) VALUES (?)", arguments: [track.artist])
            }
            if !track.album.isEmpty {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO albums(name, album_artist) VALUES (?, ?)",
                    arguments: [track.album, track.albumArtist]
                )
            }
            let canonicalGenre = GenreNormalizer.normalize(track.genre)
            if !canonicalGenre.isEmpty {
                try db.execute(sql: "INSERT OR IGNORE INTO genres(name) VALUES (?)", arguments: [canonicalGenre])
            }
        }
    }
}

private enum SQL {
    static let upsertTrack = """
        INSERT INTO tracks(
            root_id, identity_key, file_resource_id, relative_path, filename, title, artist, album,
            album_artist, genre, year, is_compilation, disc_number, track_number, duration, file_size, modified_at, format,
            bitrate, has_artwork, is_available, added_at, last_seen_session_id, comment
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(identity_key) DO UPDATE SET
            root_id = excluded.root_id,
            file_resource_id = excluded.file_resource_id,
            relative_path = excluded.relative_path,
            filename = excluded.filename,
            title = excluded.title,
            artist = excluded.artist,
            album = excluded.album,
            album_artist = excluded.album_artist,
            genre = excluded.genre,
            year = excluded.year,
            is_compilation = excluded.is_compilation,
            disc_number = excluded.disc_number,
            track_number = excluded.track_number,
            duration = excluded.duration,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at,
            format = excluded.format,
            bitrate = excluded.bitrate,
            has_artwork = excluded.has_artwork,
            is_available = excluded.is_available,
            last_seen_session_id = excluded.last_seen_session_id,
            comment = excluded.comment
        """
}

private enum Schema {
    static let genreKnowledge = """
        CREATE TABLE genre_knowledge(
            raw_key TEXT PRIMARY KEY COLLATE NOCASE,
            raw_genre TEXT NOT NULL,
            canonical_name TEXT NOT NULL COLLATE NOCASE,
            summary_ja TEXT NOT NULL DEFAULT '',
            summary_en TEXT NOT NULL DEFAULT '',
            source_title TEXT NOT NULL,
            source_url TEXT NOT NULL,
            resolved_at REAL NOT NULL
        );
        CREATE INDEX genre_knowledge_canonical_idx
            ON genre_knowledge(canonical_name COLLATE NOCASE, resolved_at DESC);
        """

    static let musicBrainzAutoFillAttempts = """
        CREATE TABLE musicbrainz_autofill_attempts(
            album_key TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('completed', 'noMatch', 'transientFailure')),
            attempt_count INTEGER NOT NULL DEFAULT 1,
            retry_after REAL,
            last_error TEXT,
            attempted_at REAL NOT NULL
        );
        CREATE INDEX musicbrainz_autofill_status_retry_idx
            ON musicbrainz_autofill_attempts(status, retry_after);
        """

    static let pendingMetadataEdits = """
        CREATE TABLE pending_metadata_edits(
            id INTEGER PRIMARY KEY,
            track_id INTEGER NOT NULL UNIQUE REFERENCES tracks(id) ON DELETE CASCADE,
            edit_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX pending_metadata_edits_updated_idx ON pending_metadata_edits(updated_at ASC, id ASC);
        """

    static let compilationTag = """
        ALTER TABLE tracks ADD COLUMN is_compilation INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX tracks_compilation_idx ON tracks(is_compilation, album COLLATE NOCASE, id);
        """
    static let yearTag = """
        ALTER TABLE tracks ADD COLUMN year TEXT NOT NULL DEFAULT '';
        """
    static let commentTag = """
        ALTER TABLE tracks ADD COLUMN comment TEXT NOT NULL DEFAULT '';
        """
    static let libraryActivityLog = """
        CREATE TABLE library_activity_log(
            id INTEGER PRIMARY KEY,
            kind TEXT NOT NULL,
            track_id INTEGER,
            root_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL,
            absolute_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL DEFAULT '',
            album TEXT NOT NULL DEFAULT '',
            changes_json TEXT NOT NULL DEFAULT '[]',
            occurred_at REAL NOT NULL
        );
        CREATE INDEX activity_log_time_idx ON library_activity_log(occurred_at DESC, id DESC);
        CREATE INDEX activity_log_kind_time_idx ON library_activity_log(kind, occurred_at DESC, id DESC);
        CREATE INDEX activity_log_track_idx ON library_activity_log(track_id, id DESC);
        """

    static let metadataDiagnostics = """
        CREATE TABLE metadata_terms(
            id INTEGER PRIMARY KEY,
            field TEXT NOT NULL,
            value TEXT NOT NULL,
            normalized TEXT NOT NULL,
            prefix TEXT NOT NULL,
            char_count INTEGER NOT NULL,
            track_count INTEGER NOT NULL,
            UNIQUE(field, value)
        );
        CREATE INDEX metadata_terms_normalized_idx ON metadata_terms(field, normalized, id);
        CREATE INDEX metadata_terms_prefix_idx ON metadata_terms(field, prefix, char_count, id);

        CREATE TABLE metadata_variation_candidates(
            id INTEGER PRIMARY KEY,
            field TEXT NOT NULL,
            value_a TEXT NOT NULL,
            value_b TEXT NOT NULL,
            track_count_a INTEGER NOT NULL,
            track_count_b INTEGER NOT NULL,
            reason TEXT NOT NULL,
            edit_distance INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at REAL NOT NULL,
            UNIQUE(field, value_a, value_b, reason)
        );
        CREATE INDEX metadata_candidates_status_idx ON metadata_variation_candidates(status, reason, field, id);
        """
    static let trackEditingAndExclusions = """
        CREATE TABLE excluded_tracks(
            identity_key TEXT PRIMARY KEY,
            root_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL,
            removed_at REAL NOT NULL,
            file_was_trashed INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX excluded_tracks_root_path_idx ON excluded_tracks(root_id, relative_path);
        """

    static let libraryExperience = """
        ALTER TABLE tracks ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE tracks ADD COLUMN play_count INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE tracks ADD COLUMN last_played_at REAL;
        CREATE INDEX tracks_favorite_idx ON tracks(is_favorite, title COLLATE NOCASE, id);
        CREATE INDEX tracks_recent_idx ON tracks(last_played_at DESC, id DESC);

        CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE storage_destinations(
            id INTEGER PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, bookmark BLOB NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0, is_available INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL
        );
        CREATE TABLE pending_imports(
            id INTEGER PRIMARY KEY, local_path TEXT NOT NULL, filename TEXT NOT NULL,
            state TEXT NOT NULL, created_at REAL NOT NULL, error_message TEXT
        );
        CREATE INDEX pending_imports_state_idx ON pending_imports(state, created_at DESC);
        CREATE TABLE local_cache(
            track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            local_path TEXT NOT NULL, file_size INTEGER NOT NULL, cached_at REAL NOT NULL, last_accessed_at REAL NOT NULL
        );
        CREATE INDEX local_cache_lru_idx ON local_cache(last_accessed_at);
        CREATE TABLE lyrics(
            track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            provider TEXT NOT NULL, plain_lyrics TEXT NOT NULL, synced_lyrics TEXT, updated_at REAL NOT NULL
        );
        CREATE TABLE web_metadata(
            id INTEGER PRIMARY KEY, entity_type TEXT NOT NULL, lookup_key TEXT NOT NULL, provider TEXT NOT NULL,
            remote_id TEXT, image_url TEXT, local_image_path TEXT, wiki_url TEXT, detected_genre TEXT,
            status TEXT NOT NULL DEFAULT 'pending', updated_at REAL NOT NULL,
            UNIQUE(entity_type, lookup_key, provider)
        );
        CREATE TABLE library_differences(
            id INTEGER PRIMARY KEY, root_id INTEGER NOT NULL, relative_path TEXT NOT NULL,
            kind TEXT NOT NULL, checked_at REAL NOT NULL, UNIQUE(root_id, relative_path, kind)
        );
        CREATE INDEX library_differences_root_kind_idx ON library_differences(root_id, kind, id);
        """

    static let playQueue = """
        CREATE TABLE play_queue(
            id INTEGER PRIMARY KEY,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL UNIQUE,
            added_at REAL NOT NULL
        );
        CREATE INDEX play_queue_order_idx ON play_queue(position, id);
        """

    static let pinnedOfflineCache = """
        ALTER TABLE local_cache ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX local_cache_pinned_lru_idx ON local_cache(is_pinned, last_accessed_at DESC, track_id);
        """

    static let initial = """
        CREATE TABLE schema_migrations(
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );

        CREATE TABLE scan_roots(
            id INTEGER PRIMARY KEY,
            display_name TEXT NOT NULL,
            bookmark BLOB NOT NULL,
            volume_uuid TEXT,
            last_known_path TEXT NOT NULL UNIQUE,
            is_available INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );

        CREATE TABLE scan_sessions(
            id INTEGER PRIMARY KEY,
            root_id INTEGER NOT NULL REFERENCES scan_roots(id) ON DELETE CASCADE,
            state TEXT NOT NULL,
            started_at REAL NOT NULL,
            finished_at REAL,
            resume_cursor TEXT,
            discovered INTEGER NOT NULL DEFAULT 0,
            processed INTEGER NOT NULL DEFAULT 0,
            changed_count INTEGER NOT NULL DEFAULT 0,
            skipped INTEGER NOT NULL DEFAULT 0,
            error_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE artists(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE
        );
        CREATE TABLE albums(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE,
            album_artist TEXT NOT NULL DEFAULT '' COLLATE NOCASE,
            UNIQUE(name, album_artist)
        );
        CREATE TABLE genres(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE
        );

        CREATE TABLE tracks(
            id INTEGER PRIMARY KEY,
            root_id INTEGER NOT NULL,
            identity_key TEXT NOT NULL UNIQUE,
            file_resource_id TEXT,
            relative_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL DEFAULT '',
            album TEXT NOT NULL DEFAULT '',
            album_artist TEXT NOT NULL DEFAULT '',
            genre TEXT NOT NULL DEFAULT '',
            disc_number INTEGER,
            track_number INTEGER,
            duration REAL NOT NULL DEFAULT 0,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            format TEXT NOT NULL,
            bitrate INTEGER,
            has_artwork INTEGER NOT NULL DEFAULT 0,
            is_available INTEGER NOT NULL DEFAULT 1,
            added_at REAL NOT NULL,
            last_seen_session_id INTEGER,
            UNIQUE(root_id, relative_path)
        );
        CREATE INDEX tracks_title_idx ON tracks(title COLLATE NOCASE, id);
        CREATE INDEX tracks_artist_idx ON tracks(artist COLLATE NOCASE, album COLLATE NOCASE, id);
        CREATE INDEX tracks_album_idx ON tracks(album COLLATE NOCASE, disc_number, track_number, id);
        CREATE INDEX tracks_added_idx ON tracks(added_at DESC, id DESC);
        CREATE INDEX tracks_path_idx ON tracks(relative_path COLLATE NOCASE, id);
        CREATE INDEX tracks_root_seen_idx ON tracks(root_id, last_seen_session_id);
        CREATE INDEX tracks_available_id_idx ON tracks(is_available, id);

        CREATE VIRTUAL TABLE tracks_fts USING fts5(
            title, artist, album, genre, filename,
            content='tracks', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER tracks_ai AFTER INSERT ON tracks BEGIN
            INSERT INTO tracks_fts(rowid, title, artist, album, genre, filename)
            VALUES (new.id, new.title, new.artist, new.album, new.genre, new.filename);
        END;
        CREATE TRIGGER tracks_ad AFTER DELETE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, genre, filename)
            VALUES ('delete', old.id, old.title, old.artist, old.album, old.genre, old.filename);
        END;
        CREATE TRIGGER tracks_au AFTER UPDATE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, genre, filename)
            VALUES ('delete', old.id, old.title, old.artist, old.album, old.genre, old.filename);
            INSERT INTO tracks_fts(rowid, title, artist, album, genre, filename)
            VALUES (new.id, new.title, new.artist, new.album, new.genre, new.filename);
        END;

        CREATE TABLE playlists(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE playlist_items(
            id INTEGER PRIMARY KEY,
            playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            created_at REAL NOT NULL,
            UNIQUE(playlist_id, track_id),
            UNIQUE(playlist_id, position)
        );
        CREATE INDEX playlist_items_order_idx ON playlist_items(playlist_id, position);

        CREATE TABLE scan_errors(
            id INTEGER PRIMARY KEY,
            session_id INTEGER NOT NULL REFERENCES scan_sessions(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX scan_errors_session_idx ON scan_errors(session_id, id);
        """
}
