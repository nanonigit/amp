import Foundation
import Testing
@testable import MassiveMusicCore

@Suite(.serialized)
struct LibraryDatabaseTests {
    @Test func genreNormalizerCanonicalizesLanguagesCaseAndSeparators() {
        let aliases: [String: String] = [
            "jazz": "Jazz",
            "JAZZ": "Jazz",
            "ジャズ": "Jazz",
            "Smooth-Jazz": "Smooth Jazz",
            "smooth・jazz": "Smooth Jazz",
            "スムース・ジャズ": "Smooth Jazz",
            "スムースジャズ": "Smooth Jazz",
            "ambient-rock": "Ambient Rock",
            "ambient・rock": "Ambient Rock",
            "ambient/rock": "Ambient Rock",
            "J POP": "J-Pop",
            "j-pop": "J-Pop",
            "ソウル／R&B": "Soul / R&B",
            "soul-r&b": "Soul / R&B",
            "ヴィジュアル系ロック": "Visual Kei Rock",
            "ストーナー・メタル": "Stoner Metal",
            "スポークンワード／コメディ": "Spoken Word / Comedy",
            "スラッジメタル": "Sludge Metal",
            "ダーク・アンビエント": "Dark Ambient",
            "沖縄民謡": "Okinawan Folk Music",
            "現代クラシック": "Contemporary Classical",
            "渋谷系": "Shibuya-Kei",
            "日本語ヒップホップ": "Japanese Hip Hop"
        ]

        for (raw, expected) in aliases {
            #expect(GenreNormalizer.normalize(raw) == expected)
        }
    }

    @Test func unknownJapaneseGenreIsNotSilentlyDeleted() {
        #expect(GenreNormalizer.normalize("未知ジャンル") == "未知ジャンル")
    }

    @Test func genreKnowledgePersistsCanonicalEnglishDescriptionAndSource() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let knowledge = GenreKnowledge(
            rawGenre: "沖縄民謡",
            canonicalName: "Okinawan Folk Music",
            summaryJapanese: "沖縄諸島で育った伝統的な民俗音楽です。",
            summaryEnglish: "Traditional folk music developed in the Okinawa Islands.",
            sourceTitle: "Music of Okinawa",
            sourceURL: URL(string: "https://en.wikipedia.org/wiki/Music_of_Okinawa")!,
            resolvedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try context.database.saveGenreKnowledge(knowledge)

        #expect(try context.database.genreKnowledge(forRawGenre: "沖縄民謡") == knowledge)
        #expect(try context.database.genreKnowledge(forCanonicalName: "okinawan folk music") == knowledge)
        #expect(try context.database.allGenreKnowledge() == [knowledge])
    }

    @Test func genreKnowledgeUpsertRefreshesAnExistingRawAlias() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let sourceURL = URL(string: "https://en.wikipedia.org/wiki/Shibuya-kei")!
        try context.database.saveGenreKnowledge(GenreKnowledge(
            rawGenre: "渋谷系",
            canonicalName: "Shibuya-Kei",
            summaryJapanese: "旧説明",
            summaryEnglish: "Old summary",
            sourceTitle: "Shibuya-kei",
            sourceURL: sourceURL,
            resolvedAt: Date(timeIntervalSince1970: 10)
        ))
        let refreshed = GenreKnowledge(
            rawGenre: "渋谷系",
            canonicalName: "Shibuya-Kei",
            summaryJapanese: "更新された説明",
            summaryEnglish: "Updated summary",
            sourceTitle: "Shibuya-kei",
            sourceURL: sourceURL,
            resolvedAt: Date(timeIntervalSince1970: 20)
        )

        try context.database.saveGenreKnowledge(refreshed)

        #expect(try context.database.genreKnowledge(forRawGenre: "渋谷系") == refreshed)
        #expect(try context.database.allGenreKnowledge().count == 1)
    }

    @Test func genreAutomationRequiresEnglishLabelsAndShowsProvenanceAndCompletion() throws {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let classifier = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/OpenAIGenreClassifier.swift"), encoding: .utf8)
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"), encoding: .utf8)
        let view = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"), encoding: .utf8)

        #expect(classifier.components(separatedBy: "Return the genre field in English Title Case.").count == 3)
        #expect(model.contains("genreNormalizationLastUnresolved"))
        #expect(model.contains("wikipediaGenreResolver.resolve"))
        #expect(model.contains("canonicalGenreForRegistration(suggestion.genre)"))
        #expect(model.contains("genre: canonicalGenre"))
        #expect(view.contains("model.genreNormalizationStatusText"))
        #expect(view.contains("knowledge.sourceURL"))
    }

    @Test func genreFacetsAndDetailsMergeCanonicalAliases() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "jazz-en", title: "English", artist: "Blue", album: "One", genre: "jazz", filename: "en.mp3"),
            context.importedTrack(identity: "jazz-ja", title: "Japanese", artist: "Blue", album: "Two", genre: "ジャズ", filename: "ja.mp3"),
            context.importedTrack(identity: "jazz-case", title: "Upper", artist: "Red", album: "Three", genre: "JAZZ", filename: "upper.mp3"),
            context.importedTrack(identity: "rock", title: "Rock", artist: "Amp", album: "Four", genre: "Rock", filename: "rock.mp3")
        ], sessionID: 1)

        let page = try context.database.facetPage(section: .genres, limit: 10)
        #expect(page.totalCount == 2)
        #expect(page.facets.first(where: { $0.name == "Jazz" })?.count == 3)
        #expect(try context.database.librarySidebarCounts().genres == 2)
        #expect(try context.database.pageTracksForGenre(genre: "Jazz").totalCount == 3)
        #expect(try context.database.pageArtists(genreFilter: "Jazz").totalCount == 2)
        #expect(try context.database.pageAlbums(genreFilter: "Jazz").totalCount == 3)
    }

    @Test func storageTopologyOnlyUsesASeparateCacheForExternalMainStorage() {
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: nil))
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: "/Users/naoki/Music/Vibe"))
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: "/"))
        #expect(StorageTopology.usesSeparateLocalCache(primaryPath: "/Volumes/Transcend/Music/Music"))
        #expect(StorageTopology.usesSeparateLocalCache(primaryPath: "/Volumes/External HDD"))
    }

    @Test func recentlyAddedLibraryIsPagedNewestFirst() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let rootID = try context.database.addScanRoot(
            displayName: "Test", bookmark: Data(), volumeUUID: nil, path: context.directory.path
        )
        let sessionID = try context.database.createScanSession(rootID: rootID)
        let imports = [
            context.importedTrack(identity: "old", title: "Old", filename: "old.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 100)),
            context.importedTrack(identity: "new", title: "New", filename: "new.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 300)),
            context.importedTrack(identity: "middle", title: "Middle", filename: "middle.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 200))
        ]
        _ = try context.database.commitScanBatch(imports: imports, unchangedIdentityKeys: [], sessionID: sessionID)

        let first = try context.database.pageTracksAfter(
            sort: .dateAdded, direction: .descending, after: nil, limit: 2
        )
        let second = try context.database.pageTracksAfter(
            sort: .dateAdded, direction: .descending, after: first.tracks.last,
            logicalOffset: 2, limit: 2, knownTotal: first.totalCount
        )

        #expect(first.totalCount == 3)
        #expect(first.tracks.map(\.title) == ["New", "Middle"])
        #expect(second.tracks.map(\.title) == ["Old"])
        #expect(second.offset == 2)
    }

    @Test func sidebarCountsIncludeEachBrowsableLibraryCategory() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "one", title: "One", artist: "Artist A", album: "Shared", genre: "Rock", filename: "one.mp3"),
            context.importedTrack(identity: "two", title: "Two", artist: "Artist A", album: "Shared", genre: "Rock", filename: "two.mp3"),
            context.importedTrack(identity: "three", title: "Three", artist: "Artist B", album: "Other", genre: "Jazz", filename: "three.mp3")
        ], sessionID: 1)
        try context.database.recordCachedTrack(trackID: 1, path: "/tmp/sidebar-count.mp3", fileSize: 1)

        let counts = try context.database.librarySidebarCounts()

        #expect(counts.tracks == 3)
        #expect(counts.albums == 2)
        #expect(counts.artists == 2)
        #expect(counts.genres == 2)
        #expect(counts.folders == 1)
        #expect(counts.cached == 1)
        #expect(counts.cachedBytes == 1)
    }

    @Test func sidebarCacheMetricsIncludeTotalStorageBytes() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.insertSyntheticTracks(count: 3)
        try context.database.recordCachedTrack(trackID: 1, path: "/tmp/cache-one.mp3", fileSize: 12_345)
        try context.database.recordCachedTrack(trackID: 3, path: "/tmp/cache-three.mp3", fileSize: 67_890)

        let counts = try context.database.librarySidebarCounts()

        #expect(counts.cached == 2)
        #expect(counts.cachedBytes == 80_235)
    }

    @Test func automaticGenreCanReuseTaggedTrackFromSameAlbumAndArtist() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(
                identity: "tagged", title: "One", artist: "Artist",
                album: "Shared Album", albumArtist: "Artist", genre: "Funk", filename: "one.mp3"
            ),
            context.importedTrack(
                identity: "missing", title: "Two", artist: "Artist",
                album: "Shared Album", albumArtist: "Artist", filename: "two.mp3"
            ),
            context.importedTrack(
                identity: "other", title: "Three", artist: "Artist",
                album: "Other Album", albumArtist: "Artist", genre: "Rock", filename: "three.mp3"
            )
        ], sessionID: 1)

        let missing = try #require(try context.database.tracksMissingGenre(afterID: 0, limit: 10).first)
        #expect(try context.database.consensusGenreForAlbum(track: missing) == "Funk")
    }

    @Test func albumArtworkUsesTheFirstEmbeddedCoverBeforeRemoteLookup() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(
                identity: "plain", title: "Plain", artist: "Track Artist",
                album: "Shared Album", albumArtist: "Album Artist", trackNumber: 1
            ),
            context.importedTrack(
                identity: "covered", title: "Covered", artist: "Track Artist",
                album: "Shared Album", albumArtist: "Album Artist", trackNumber: 2,
                hasArtwork: true
            )
        ], sessionID: 1)

        let artworkTrack = try #require(try context.database.representativeArtworkTrack(
            album: "Shared Album", artist: "Album Artist"
        ))
        #expect(artworkTrack.title == "Covered")

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let services = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        #expect(services.contains("representativeArtworkTrack(album: album, artist: artist)"))
        #expect(services.contains("let embedded = await embeddedArtworkURL(for: track)"))
    }

    @Test func recentLibraryAndStorageConnectionStateAreExplicitInTheUI() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let view = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(model.contains("case .recentlyAdded: text(\"最近追加した曲\", \"Recently Added\")"))
        #expect(model.contains("requestedSection == .recentlyAdded"))
        #expect(model.contains("primaryStorageIsConnected"))
        #expect(view.contains("接続中"))
        #expect(view.contains("未接続"))
        #expect(view.contains("Color.green"))
        #expect(view.contains("Color.orange"))
        #expect(view.contains("var iconColor: Color = Color(nsColor: .labelColor)"))
        #expect(view.contains("model.text(\"メイン保管先：接続中\", \"Main Storage: Connected\")"))
        #expect(view.contains("model.text(\"メイン保管先：未接続\", \"Main Storage: Disconnected\")"))
        #expect(view.contains(".foregroundStyle(model.primaryStorageIsConnected ? Color.green : Color.orange)"))
    }

    @Test func disconnectedImportsUseTheCacheAndReconnectCopiesWithoutRemovingIt() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let services = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(services.contains("func copyKeptLocalImport"))
        #expect(services.contains("fileManager.copyItem(at: source, to: target)"))
        #expect(model.contains("state: .keptLocal, localPath: cacheURL.path"))
        #expect(model.contains("storage.copyKeptLocalImport(item, to: primary)"))
    }

    @Test func existingContainerLibraryWinsOverANewEmptyUnsandboxedDatabase() {
        let current = URL(filePath: "/Users/test/Library/Application Support/MassiveMusic/MassiveMusic.sqlite")
        let container = URL(filePath: "/Users/test/Library/Containers/com.local.MassiveMusic/Data/Library/Application Support/MassiveMusic/MassiveMusic.sqlite")

        #expect(LibraryDatabase.preferredApplicationSupportDatabase(
            defaultURL: current, containerURL: container, containerDatabaseExists: true
        ) == container)
        #expect(LibraryDatabase.preferredApplicationSupportDatabase(
            defaultURL: current, containerURL: container, containerDatabaseExists: false
        ) == current)
    }

    @Test func existingScanRootBecomesPrimaryStorageBeforeCreatingALocalDefault() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("if let existingRoot = try database.scanRoots().first"))
        #expect(source.contains("path: existingRoot.lastKnownPath"))
        #expect(source.contains("bookmark: existingRoot.bookmark"))
    }

    @Test func automaticMetadataCleanupWaitsForEverySourceDrive() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("private func allScanRootsAreConnected() -> Bool"))
        #expect(source.contains("guard allScanRootsAreConnected() else { return }"))
    }

    @Test func librarySidebarStaysExpandedAndOnlyShowsCacheForSeparateStorage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(!source.contains("Section(isExpanded: .constant(true))"))
        #expect(source.contains("ForEach(model.visibleLibrarySections)"))
        #expect(source.components(separatedBy: ".menuIndicator(.hidden)").count - 1 >= 4)
    }

    @Test func librarySidebarCanBeDragReorderedAndPersistsItsOrder() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains(".sidebarReorderDraggable(section.rawValue, enabled: isReorderingLibrary)"))
        #expect(content.contains(".dropDestination(for: String.self)"))
        #expect(content.contains("model.moveLibrarySection(source, before: section)"))
        #expect(content.contains("model.moveLibrarySection(section, by: -1)"))
        #expect(content.contains("model.moveLibrarySection(section, by: 1)"))
        #expect(content.contains("model.text(\"並び替える\", \"Reorder Items\")"))
        #expect(model.contains("sidebar.libraryOrder"))
        #expect(model.contains("librarySectionOrder = order"))
    }

    @Test func librarySidebarUsesRequestedDefaultsOnlyWhenPreferencesAreAbsent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(model.contains(".cache") && model.contains(".artists") && model.contains(".albums") && model.contains(".tracks") && model.contains(".genres") && model.contains(".favorites"))
        #expect(model.contains("[.recentlyAdded, .upNext, .folders]"))
        #expect(model.contains("if let storedLibraryOrder"))
        #expect(model.contains("if let storedLibraryVisibility"))
    }

    @Test func librarySearchKeepsStableFocusAndWidthWhileLoading() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(content.contains("@FocusState private var isLibrarySearchFocused: Bool"))
        #expect(content.contains("LibrarySearchField(model: model, isFocused: $isLibrarySearchFocused)"))
        #expect(content.contains("@FocusState.Binding var isFocused: Bool"))
        #expect(content.contains(".focused($isFocused)"))
        let searchStart = try #require(content.range(of: "private struct LibrarySearchField"))
        let searchEnd = try #require(content.range(of: "private struct TrackSortHeader", range: searchStart.upperBound..<content.endIndex))
        let searchField = String(content[searchStart.lowerBound..<searchEnd.lowerBound])
        #expect(searchField.contains(".frame(minWidth: 140, idealWidth: 200, maxWidth: 260)"))
        #expect(searchField.contains(".opacity(model.isSearchInProgress ? 1 : 0)"))
        #expect(!searchField.contains("Text(model.text(\"検索中…\", \"Searching…\"))"))
    }

    @Test func libraryHeaderKeepsPersistentVisibilityControlsWhileToolsStaySimple() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("ForEach(model.orderedLibrarySections)"))
        #expect(content.contains("model.toggleLibrarySectionVisibility(section)"))
        #expect(content.contains("model.showAllLibrarySections"))
        #expect(content.contains("model.text(\"表示項目\", \"Visible Items\")"))
        #expect(content.contains("Text(model.text(\"ツール\", \"Tools\"))"))
        #expect(content.contains("model.sectionTitle(.settings)") || content.contains("title: model.text(\"設定と管理\", \"Settings & Management\")"))
        #expect(!content.contains("model.text(\"管理項目を整理\", \"Organize management items\")"))
        #expect(model.contains("sidebar.libraryHidden"))
        #expect(model.contains("@Published private(set) var hiddenLibrarySections"))
    }

    @Test func trackColumnsCanBeDragReorderedAndPersistTheirOrder() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("@AppStorage(\"columns.order\")"))
        #expect(source.contains("ForEach(orderedVisibleTrackColumns)"))
        #expect(source.contains(".draggable(column.rawValue)"))
        #expect(source.contains("moveTrackColumn(source, before: column)"))
    }

    @Test func sidebarSeparatesNavigationPlaylistCommandsAndSettingsManagement() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let app = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))
        let sidebarStart = try #require(source.range(of: "    private var sidebar: some View"))
        let sidebarEnd = try #require(source.range(of: "    private var libraryContent: some View", range: sidebarStart.upperBound..<source.endIndex))
        let sidebar = String(source[sidebarStart.lowerBound..<sidebarEnd.lowerBound])
        let playlists = try #require(sidebar.range(of: "model.text(\"プレイリスト\", \"Playlists\")"))
        let tools = try #require(sidebar.range(of: "model.text(\"ツール\", \"Tools\")"))

        #expect(playlists.lowerBound < tools.lowerBound)
        #expect(!sidebar.contains("action: model.chooseAndScanFolder"))
        #expect(!sidebar.contains("action: model.importNewTracks"))
        #expect(!sidebar.contains("model.revealLocalCache"))
        #expect(!sidebar.contains("model.chooseStorageDestination"))
        #expect(!sidebar.contains("isMiniPlayer = true"))
        #expect(!sidebar.contains("showInspector.toggle()"))
        #expect(sidebar.contains("action: model.importPlaylist"))
        #expect(sidebar.contains("model.sectionTitle(.settings)") || sidebar.contains("title: model.text(\"設定と管理\", \"Settings & Management\")"))
        #expect(source.contains("Button(model.text(\"フォルダを追加…\", \"Add Folder…\"), action: model.chooseAndScanFolder)"))
        #expect(source.contains("Button(model.text(\"曲を取り込む…\", \"Import Songs…\"), action: model.importNewTracks)"))
        #expect(!source.contains(".toolbar { toolbar }"))
        #expect(!source.contains("private var toolbar: some ToolbarContent"))
        #expect(app.contains(".windowStyle(.hiddenTitleBar)"))
    }

    @Test func playlistRowsRenameInlineAndEmptyPlaylistStateDoesNotFlickerWhileReloading() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("@FocusState private var focusedPlaylistEditorID: Int64?"))
        #expect(content.contains("TextField(model.text(\"プレイリスト名\", \"Playlist Name\"), text: $playlistNameDraft)"))
        #expect(content.contains(".onTapGesture(count: 2) { beginEditingPlaylist(playlist) }"))
        #expect(content.contains(".onSubmit { commitPlaylistRename(playlist.id) }"))
        #expect(content.contains(".onExitCommand(perform: cancelPlaylistRename)"))
        let emptyOverlay = content[content.range(of: ".overlay {\n            if model.section == .playlists,")!.lowerBound..<content.range(of: "@ViewBuilder private func trackColumnCell")!.lowerBound]
        #expect(emptyOverlay.contains("model.text(\"プレイリストに曲がありません\", \"No Songs in This Playlist\")"))
        #expect(emptyOverlay.range(of: "if model.isLoading")!.lowerBound > emptyOverlay.range(of: "model.section == .playlists,")!.lowerBound)
    }

    @Test func idleInspectorShowsDiscoveryLinksWithoutLyricsFailure() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let inspectorStart = try #require(source.range(of: "private struct NowPlayingInspector: View"))
        let inspectorEnd = try #require(source.range(of: "private struct CurrentTrackInfoEditorView: View", range: inspectorStart.upperBound..<source.endIndex))
        let inspector = String(source[inspectorStart.lowerBound..<inspectorEnd.lowerBound])

        #expect(inspector.contains("if player.currentTrack == nil"))
        #expect(inspector.contains("idleDiscovery"))
        #expect(inspector.contains("再生停止中"))
    }

    @Test func inspectorChordTabSearchesChordifyForTheCurrentTrack() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let inspectorStart = try #require(source.range(of: "private struct NowPlayingInspector: View"))
        let inspectorEnd = try #require(source.range(of: "private struct CurrentTrackInfoEditorView: View", range: inspectorStart.upperBound..<source.endIndex))
        let inspector = String(source[inspectorStart.lowerBound..<inspectorEnd.lowerBound])

        #expect(inspector.contains("Text(model.text(\"コード\", \"Chords\")).tag(5)"))
        #expect(inspector.contains("private var chordifySearchURL: URL?"))
        #expect(inspector.contains("https://chordify.net/search/"))
        #expect(inspector.contains("browserURL = chordifySearchURL"))
        #expect(inspector.contains("if tab == 5 { tab = 0 }"))
    }

    @Test func inspectorTabSearchLetsTheUserChooseGuitarOrBassOnYouTube() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let inspectorStart = try #require(source.range(of: "private struct NowPlayingInspector: View"))
        let inspectorEnd = try #require(source.range(of: "private struct CurrentTrackInfoEditorView: View", range: inspectorStart.upperBound..<source.endIndex))
        let inspector = String(source[inspectorStart.lowerBound..<inspectorEnd.lowerBound])

        #expect(inspector.contains("Text(\"TAB\").tag(4)"))
        #expect(inspector.contains("private var youtubeTabSearchURL: URL?"))
        #expect(inspector.contains("URLComponents(string: \"https://www.youtube.com/results\")"))
        #expect(inspector.contains("[track.title, track.artist, \"tab\", tabSearchInstrument]"))
        #expect(inspector.contains("Text(\"guitar\").tag(\"guitar\")"))
        #expect(inspector.contains("Text(\"bass\").tag(\"bass\")"))
        #expect(inspector.contains("browserURL = youtubeTabSearchURL"))
    }

    @Test func trackSelectionDoesNotWaitForDoubleClickRecognition() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains(".simultaneousGesture(\n                                    TapGesture(count: 1)"))
        #expect(!source.contains("                                .onTapGesture {\n                                    isTrackTableFocused = true\n                                    handleTrackSelection(track, at: index)"))
    }

    @Test func artistSummaryRestoresItsScrollPositionAfterClosingArtistDetail() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("@State private var artistScrollPosition: String?"))
        #expect(source.contains("@State private var artistReturnScrollPosition: String?"))
        #expect(source.components(separatedBy: ".scrollPosition(id: $artistScrollPosition, anchor: .top)").count - 1 >= 2)
        #expect(source.components(separatedBy: "openArtistPreservingScrollPosition(artist)").count - 1 >= 2)
        #expect(source.contains("artistReturnScrollPosition = artistScrollPosition ?? artist.id"))
        #expect(source.contains("closeDetailRestoringScrollPosition"))
        #expect(source.contains("ScrollView(.vertical)"))
        #expect(source.contains("LazyVStack(spacing: 0)"))
        #expect(source.contains(".scrollTargetLayout()"))
        #expect(source.contains(".onChange(of: model.isLoading)"))
        #expect(source.contains("restorePendingArtistScrollPositionIfNeeded()"))
        #expect(source.contains("guard !model.isLoading,"))
        #expect(source.contains("artistScrollPosition = nil\n        Task { @MainActor in"))
        #expect(source.contains("artistReturnScrollPosition = nil"))
    }

    @Test func embeddedBrowserStopsMediaWhenReturningToInformation() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/InternalBrowserView.swift"))

        #expect(source.contains("static func dismantleNSView"))
        #expect(source.contains("querySelectorAll('video, audio')"))
        #expect(source.contains("media.pause()"))
        #expect(source.contains("view.stopLoading()"))
        #expect(source.contains("view.loadHTMLString(\"\", baseURL: nil)"))
    }

    @Test func embeddedBrowserProvidesBackAndForwardHistoryControls() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/InternalBrowserView.swift"))

        #expect(source.contains("Image(systemName: \"chevron.backward\")"))
        #expect(source.contains("Image(systemName: \"chevron.forward\")"))
        #expect(source.contains("webView?.goBack()"))
        #expect(source.contains("webView?.goForward()"))
        #expect(source.contains("canGoBack = webView.canGoBack"))
        #expect(source.contains("canGoForward = webView.canGoForward"))
        #expect(source.contains(".disabled(!navigation.canGoBack)"))
        #expect(source.contains(".disabled(!navigation.canGoForward)"))
    }

    @Test func embeddedBrowserFitsWidePagesToTheInspectorWidth() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/InternalBrowserView.swift"))

        #expect(source.contains("GeometryReader"))
        #expect(source.contains("availableWidth: proxy.size.width"))
        #expect(source.contains("document.documentElement?.scrollWidth"))
        #expect(source.contains("webView.pageZoom"))
        #expect(source.contains("fitPage(in: view, availableWidth: availableWidth)"))
        #expect(source.contains("max(0.6, min(1, fittedZoom))"))
    }

    @Test func googleAuthenticationLeavesTheEmbeddedBrowserForTheSystemBrowser() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/InternalBrowserView.swift"))

        #expect(source.contains("navigation.openInDefaultBrowser(fallback: url)"))
        #expect(source.contains("shouldOpenGoogleAuthenticationExternally"))
        #expect(source.contains("NSWorkspace.shared.open(destination)"))
        #expect(source.contains("host == \"accounts.google.com\""))
        #expect(source.contains("!shouldOpenGoogleAuthenticationExternally(url)"))
    }

    @Test func libraryTablesUseSubtleColumnDividersAndConsistentTextColor() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let albumStart = try #require(source.range(of: "private func albumColumnCell"))
        let albumEnd = try #require(source.range(of: "private var albumSummaryGrid: some View", range: albumStart.upperBound..<source.endIndex))
        let albumTable = String(source[albumStart.lowerBound..<albumEnd.lowerBound])

        #expect(source.contains("private struct TableColumnDividerModifier: ViewModifier"))
        #expect(source.components(separatedBy: ".tableColumnDivider()").count - 1 >= 6)
        #expect(!albumTable.contains(".buttonStyle(.link)"))
        #expect(albumTable.contains(".foregroundStyle(.primary)"))
        #expect(source.contains("case .cache: return model.cachedTrackCount.formatted()"))
        #expect(source.contains("case .tracks: return model.libraryTrackCount.formatted()"))
    }

    @Test func missingGenreScanOnlyReturnsAvailableUnclassifiedTracks() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "missing", title: "Missing", artist: "Artist", album: "Album", genre: "", filename: "missing.mp3"),
            context.importedTrack(identity: "unknown", title: "Unknown", artist: "Artist", album: "Album", genre: "Unknown", filename: "unknown.mp3"),
            context.importedTrack(identity: "known", title: "Known", artist: "Artist", album: "Album", genre: "Rock", filename: "known.mp3")
        ], sessionID: 1)

        let tracks = try context.database.tracksMissingGenre(afterID: 0, limit: 10)

        #expect(tracks.map(\.title) == ["Missing", "Unknown"])
        #expect(try context.database.missingGenreTrackCount() == 2)
    }

    @Test func genreScreenStartsHighConfidenceHybridScanAndShowsRegistrationCount() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("model.startAutomaticGenreScan()"))
        #expect(content.contains("ジャンル検索を開始"))
        #expect(content.contains("automaticGenreRegisteredCount"))
        #expect(model.contains("guard suggestion.confidence >= 0.80"))
        #expect(model.contains("tracksMissingGenre(afterID:"))
        #expect(model.contains("automaticGenreRegisteredCount"))

        let scanStart = try #require(model.range(of: "func startAutomaticGenreScan()"))
        let scanEnd = try #require(model.range(of: "func cancelAutomaticGenreScan()", range: scanStart.upperBound..<model.endIndex))
        let scan = String(model[scanStart.lowerBound..<scanEnd.lowerBound])
        #expect(scan.contains("genreClassifier.classify("))
        #expect(scan.contains("geminiGenreClassifier.classify("))
        #expect(!scan.contains("LocalGenreClassifier()"))
        #expect(scan.contains("automaticGenreScanProcessedCount += 1"))
        #expect(scan.contains("automaticGenreScanFailedCount"))
        #expect(scan.contains("automaticGenreScanBelowThresholdCount"))
        #expect(scan.components(separatedBy: "automaticGenreScanBelowThresholdCount += 1").count - 1 == 1)
        #expect(scan.contains("consecutiveProviderFailures >= 3"))
        #expect(scan.contains("automaticGenreRetrySecondsRemaining = 10"))
        #expect(scan.contains("try await Task.sleep(for: .seconds(1))"))
        #expect(!scan.contains("shouldStop"))
        #expect(content.contains("model.isScanningAutomaticGenres"))
        #expect(content.contains("sidebarAutomaticGenreProgress"))
        #expect(content.contains("automaticGenreRetrySecondsRemaining"))
        #expect(model.contains("recordAutomaticGenreRegistration(canonicalGenre)"))
        #expect(scan.contains("consensusGenreForAlbum(track: track)"))
        #expect(scan.contains("musicMetadata.genreSuggestion("))
        #expect(scan.range(of: "consensusGenreForAlbum(track: track)")!.lowerBound < scan.range(of: "genreClassifier.classify(")!.lowerBound)
        #expect(content.contains("ライブラリ内一致→ローカル判定→MusicBrainz→外部AI"))
        #expect(content.contains("automaticGenreMusicBrainzRegisteredCount"))
        #expect(model.contains("enum GenreDescriptionCatalog"))
        #expect(content.contains("model.genreShortDescription"))
        #expect(content.contains("model.genreDetailDescription"))
    }

    @Test func displaySettingsOfferSixPersistentPreviewThemes() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let app = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))

        for theme in ["codexDark", "graphiteDark", "midnightDark", "paperLight", "warmLight", "mistLight"] {
            #expect(model.contains("case \(theme)"))
        }
        #expect(model.contains("struct AppearancePalette"))
        #expect(model.contains("legacyAppearance"))
        #expect(content.contains("AppearanceThemePicker"))
        #expect(content.contains("model.appearance.palette.sidebar"))
        #expect(content.contains("model.appearance.palette.inspector"))
        #expect(content.contains("model.savePresentationSettings()"))
        #expect(model.contains("case .codexDark: text(\"ダーク\", \"Dark\")"))
        #expect(app.contains("NSApplication.shared.appearance = appearance"))
        #expect(app.contains("window.appearance = appearance"))
        #expect(app.contains("struct WindowAppearanceSynchronizer"))
        #expect(content.contains("WindowAppearanceSynchronizer(mode: model.appearance)"))
    }

    @Test func playlistCustomizationPersistsWithoutCustomizableManagementActions() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(model.contains("sidebar.playlistOrder"))
        #expect(model.contains("func movePlaylist(_ sourceID: Int64, before destinationID: Int64)"))
        #expect(model.contains("func movePlaylist(_ id: Int64, by offset: Int)"))
        #expect(!content.contains("@AppStorage(\"sidebar.managementOrder\")"))
        #expect(!content.contains("@AppStorage(\"sidebar.managementHidden\")"))
        #expect(!content.contains("toggleManagementItemVisibility"))
        #expect(!content.contains("ManagementSidebarItem"))
        #expect(content.contains(".sidebarReorderDraggable(\"playlist-order:\\(playlist.id)\", enabled: isReorderingPlaylists)"))
        #expect(content.contains("if enabled"))
        #expect(!content.contains("management:"))
    }

    @Test func sidebarNavigationLabelsUseOneExplicitFontSize() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let labelStart = try #require(content.range(of: "private struct SidebarNavigationLabel: View"))
        let labelEnd = try #require(content.range(of: "\nprivate struct CacheTrackLimitControl", range: labelStart.upperBound..<content.endIndex))
        let label = content[labelStart.lowerBound..<labelEnd.lowerBound]

        #expect(label.contains(".font(.body)"))
    }

    @Test func backgroundProgressLivesInCompactSidebarFooter() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let sidebarStart = try #require(source.range(of: "private var sidebar: some View"))
        let libraryStart = try #require(source.range(of: "private var libraryContent: some View"))
        let sidebar = source[sidebarStart.lowerBound..<libraryStart.lowerBound]
        let libraryEnd = try #require(source.range(of: "private var headerTitle: String"))
        let library = source[libraryStart.lowerBound..<libraryEnd.lowerBound]

        #expect(sidebar.contains("sidebarBackgroundStatus"))
        #expect(sidebar.contains("if model.isBulkAutoFilling"))
        #expect(sidebar.contains("if model.isID3Migrating"))
        #expect(sidebar.contains("if model.isScanningAutomaticGenres"))
        #expect(sidebar.contains("sidebarAutomaticGenreProgress"))
        #expect(!library.contains("if model.isBulkAutoFilling"))
        #expect(!library.contains("if model.isID3Migrating"))
        #expect(source.contains("private var sidebarBackgroundStatus: some View"))
        #expect(source.contains("private func sidebarProgressStatus"))
    }

    @Test func musicBrainzSidebarProgressNamesAlbumTrackOrderAnalysis() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(model.contains("アルバム曲順を解析中"))
        #expect(model.contains("Analyzing album track order"))
    }

    @Test func inspectorDividerUsesStableGlobalDragCoordinates() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(content.contains("DragGesture(minimumDistance: 1, coordinateSpace: .global)") || content.contains("DragGesture(minimumDistance: 0, coordinateSpace: .global)"))
        #expect(content.contains("value.startLocation.x - value.location.x"))
        #expect(!content.contains(".animation(.easeOut(duration: 0.12), value: inspectorDragStartWidth != nil)"))
    }

    @Test func navigationRefreshesCannotApplyAfterCancellationAndViewsResetToTop() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(model.contains("@Published private(set) var pagePresentationID"))
        #expect(model.contains("pagePresentationID = UUID()"))
        #expect(model.components(separatedBy: "try Task.checkCancellation()\n                    apply(").count - 1 >= 8)
        #expect(content.contains(".id(model.pagePresentationID)"))
    }

    @Test func automaticGenreRegistrationIsOptInAndRequiresEightyPercentConfidence() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("$model.autoRegisterHighConfidenceGenres"))
        #expect(content.contains("80%以上"))
        #expect(model.contains("guard autoRegisterHighConfidenceGenres"))
        #expect(model.contains("guard suggestion.confidence >= 0.80"))
        #expect(model.contains("genre.autoRegisterHighConfidence"))
    }

    @Test func oneSettingsDestinationContainsStorageAndDifferenceTabs() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("model.sectionTitle(.settings)") || source.contains("title: model.text(\"設定と管理\", \"Settings & Management\")"))
        #expect(source.contains("settingsTab = .display"))
        #expect(source.contains("settingsTabButton(tab: .storage") || source.contains(".tag(SettingsTab.storage)"))
        #expect(source.contains("settingsTabButton(tab: .differences") || source.contains(".tag(SettingsTab.differences)"))
        #expect(!source.contains("model.text(\"SSDとの差分\", \"Storage Differences\")"))
    }

    @Test func metadataWidthNormalizationChangesOnlyRequestedWidthVariants() {
        #expect(
            MetadataTextNormalizer.normalizedWidths("ﾗｳﾞ ｶﾞｯﾂ ＡＢＣ１２３！")
                == "ラヴ ガッツ ABC123!"
        )
        #expect(MetadataTextNormalizer.normalizedWidths("s a y ｍｙ name") == "s a y my name")
        #expect(MetadataTextNormalizer.normalizedWidths("Roman Ⅳ ① café") == "Roman Ⅳ ① café")
    }

    @Test func metadataWidthNormalizationIsOptionalAndResumable() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("文字幅を自動で正規化"))
        #expect(content.contains("model.saveMetadataNormalizationSettings()"))
        #expect(model.contains("metadata.normalizeCharacterWidths"))
        #expect(model.contains("metadata.widthNormalizationCursor"))
        #expect(model.contains("tracksForWidthNormalization(afterID:"))
    }

    @Test func sidebarNavigationRowsUseFullWidthRectangularHitTargets() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct SidebarNavigationLabel: View"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.components(separatedBy: "SidebarNavigationLabel(").count - 1 >= 5)
    }

    @Test func playerControlsLiveInsideInspectorAndCenterUsesFullHeight() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let bodyStart = try #require(source.range(of: "    var body: some View {"))
        let bodyEnd = try #require(source.range(of: "        .onChange(of: player.currentTrack)", range: bodyStart.upperBound..<source.endIndex))
        let rootLayout = String(source[bodyStart.lowerBound..<bodyEnd.lowerBound])

        #expect(source.contains("private struct PlayerArtwork: View"))
        #expect(source.components(separatedBy: "PlayerArtwork(").count - 1 >= 2)
        #expect(rootLayout.contains("NavigationSplitView"))
        #expect(rootLayout.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(rootLayout.contains(".padding(.top, -max(0, geometry.safeAreaInsets.top - 16))"))
        #expect(!rootLayout.contains("PlayerBar(player: player, model: model)"))
        #expect(source.contains("InspectorPlayerControls(player: player, model: model, isMiniPlayer: $isMiniPlayer)"))
        #expect(source.contains("private struct InspectorPlayerControls: View"))
        let inspectorStart = try #require(source.range(of: "private struct NowPlayingInspector: View"))
        let playerControls = try #require(source.range(of: "InspectorPlayerControls(player: player, model: model, isMiniPlayer: $isMiniPlayer)", range: inspectorStart.upperBound..<source.endIndex))
        let inspectorContent = try #require(source.range(of: "Group {", range: playerControls.upperBound..<source.endIndex))
        #expect(playerControls.lowerBound < inspectorContent.lowerBound)
        #expect(source.contains(".font(.system(size: isCompact ? 27 : 34))"))
        #expect(source.contains("Color.accentColor.opacity(0.18)"))
        let controlsStart = try #require(source.range(of: "private struct InspectorPlayerControls: View"))
        let controlsSource = String(source[controlsStart.lowerBound...])
        let controlsBody = try #require(controlsSource.range(of: "VStack(spacing: 9)"))
        let volumePlacement = try #require(controlsSource.range(of: "volumeButton", range: controlsBody.upperBound..<controlsSource.endIndex))
        let transportRow = try #require(controlsSource.range(of: "HStack(spacing: 8)", range: controlsBody.upperBound..<controlsSource.endIndex))
        #expect(volumePlacement.lowerBound < transportRow.lowerBound)
        #expect(controlsSource.contains("Text(\"\\(Int((player.volume * 100).rounded()))%\")"))
        let volumePopover = try #require(controlsSource.range(of: ".popover(isPresented: $isVolumePopoverPresented"))
        let volumeSlider = try #require(controlsSource.range(of: "Slider(value: $player.volume", range: volumePopover.upperBound..<controlsSource.endIndex))
        #expect(volumePopover.lowerBound < volumeSlider.lowerBound)
        #expect(controlsSource.contains("private var volumeSymbol: String"))
        #expect(controlsSource.contains("private var miniPlayerButton: some View"))
        #expect(controlsSource.contains("Button { isMiniPlayer.toggle() }"))
        #expect(controlsSource.contains("systemImage: isCompact ? \"arrow.up.left.and.arrow.down.right\" : \"pip\""))
        #expect(controlsSource.contains(".labelStyle(.iconOnly)"))
        #expect(controlsSource.contains(".frame(width: 30, height: 28)"))
        #expect(!controlsSource.contains(".padding(.trailing, 46)"))
        #expect(source.contains(".padding(.top, showInspector ? 66 : 12)"))
        #expect(source.contains("private var inspectorToggleButton: some View"))
        #expect(source.contains("Image(systemName: \"sidebar.right\")"))
        #expect(source.contains("model.text(\"右ペインを閉じる\", \"Hide Right Pane\")"))
    }

    @Test func inspectorArtworkLivesBesideCompactPlayerInsteadOfTakingDetailSpace() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let controlsStart = try #require(source.range(of: "private struct InspectorPlayerControls: View"))
        let controlsEnd = try #require(source.range(of: "struct MiniPlayerView: View", range: controlsStart.upperBound..<source.endIndex))
        let controlsSource = String(source[controlsStart.lowerBound..<controlsEnd.lowerBound])
        let informationStart = try #require(source.range(of: "@ViewBuilder private var playerInformation: some View"))
        let informationEnd = try #require(source.range(of: "private var chordifySearchURL", range: informationStart.upperBound..<source.endIndex))
        let informationSource = String(source[informationStart.lowerBound..<informationEnd.lowerBound])

        #expect(controlsSource.contains("PlayerArtwork("))
        #expect(controlsSource.contains("artworkURL: model.enrichedInfo?.artworkURL"))
        #expect(controlsSource.contains("size: isCompact ? 44 : 72"))
        #expect(controlsSource.contains("HStack(alignment: .top, spacing: 12)"))
        #expect(!informationSource.contains("PlayerArtwork("))
        #expect(!informationSource.contains("size: 210"))
        #expect(!informationSource.contains("Text(player.currentTrack?.title"))
        #expect(!informationSource.contains("Text(player.currentTrack?.artist"))
    }

    @Test func inspectorPlayerExposesOneTrackAndAlbumOrPlaylistRepeat() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(content.contains("model.text(\"1曲リピート\", \"Repeat One\")"))
        #expect(content.contains("model.text(\"アルバム／プレイリストをリピート\", \"Repeat Album/Playlist\")"))
        #expect(content.contains("private var repeatButton: some View"))
        #expect(content.contains("repeatModeSymbol"))
        #expect(playback.contains("let shouldWrap = repeatMode == .all"))
        #expect(playback.contains("wraps: shouldWrap"))
    }

    @Test func practiceTabProvidesPitchPreservingSpeedsAndIndependentSemitoneShift() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(content.contains("Text(model.text(\"練習\", \"Practice\")).tag(3)"))
        #expect(content.contains("PlaybackController.supportedSpeeds"))
        #expect(content.contains("player.setPitchSemitones(-1)"))
        #expect(content.contains("player.setPitchSemitones(1)"))
        #expect(content.contains("player.setSectionLoopStart"))
        #expect(content.contains("player.setSectionLoopEnd"))
        #expect(content.contains("player.toggleSectionLoop()"))
        #expect(playback.contains("[0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00]"))
        #expect(playback.contains("item.audioTimePitchAlgorithm = .spectral"))
        #expect(playback.contains("private let timePitch = AVAudioUnitTimePitch()"))
        #expect(playback.contains("timePitch.pitch = Float(pitchSemitones * 100)"))
        #expect(playback.contains("timePitch.rate = Float(playbackSpeed)"))
        #expect(!playback.contains("if pitchSemitones != 0 { playbackSpeed = 1 }"))
        let pitchSetter = playback[playback.range(of: "func setPitchSemitones")!.lowerBound..<playback.range(of: "var canSetSectionLoopEnd")!.lowerBound]
        #expect(!pitchSetter.contains("playbackSpeed = 1"))
        #expect(!pitchSetter.contains("UserDefaults.standard.set(1.0, forKey: \"playback.practice.speed\")"))
        let speedSetter = playback[playback.range(of: "func setPlaybackSpeed")!.lowerBound..<playback.range(of: "func setPitchSemitones")!.lowerBound]
        #expect(!speedSetter.contains("playbackSpeed = speed\n        pitchSemitones = 0"))
        #expect(speedSetter.contains("if pitchSemitones == 0"))
        #expect(speedSetter.contains("try startPitchPlayback(at: position, shouldPlay: wasPlaying)"))
        #expect(playback.contains("func restartSectionLoopIfNeeded(at seconds: Double) -> Bool"))
        #expect(playback.contains("handlePlaybackReachedEnd()"))
        #expect(playback.contains("clearSectionLoop()"))
        #expect(content.contains("PlaybackController.sectionLoopSlotCount"))
        #expect(content.contains("player.selectSectionLoopSlot($0)"))
        #expect(playback.contains("static let sectionLoopSlotCount = 3"))
        #expect(playback.contains("playback.practice.sectionLoops.v1"))
        #expect(playback.contains("JSONEncoder().encode(allLoops)"))
        #expect(playback.contains("restoreSectionLoopPreset(for: track"))
    }

    @Test func miniPlayerUsesCurrentTrackArtworkAndRefreshesItWhenTheTrackChanges() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let sharedStart = try #require(source.range(of: "private struct UnifiedPlayerControls: View"))
        let miniPlayerSource = String(source[sharedStart.lowerBound...])

        #expect(miniPlayerSource.contains("PlayerArtwork("))
        #expect(miniPlayerSource.contains("artworkURL: model.enrichedInfo?.artworkURL"))
        #expect(miniPlayerSource.contains(".onChange(of: player.currentTrack)"))
        #expect(miniPlayerSource.contains("model.enrich(track)"))
        #expect(!miniPlayerSource.contains("NSApplication.shared.applicationIconImage"))
    }

    @Test func miniPlayerUsesCompactHierarchyWithoutExcessVerticalPadding() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let app = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))
        let controlsStart = try #require(content.range(of: "private struct UnifiedPlayerControls: View"))
        let miniPlayerSource = String(content[controlsStart.lowerBound...])

        #expect(miniPlayerSource.contains("size: isCompact ? 44 : 72"))
        #expect(miniPlayerSource.contains("timeLabel(player.elapsed)"))
        #expect(miniPlayerSource.contains("timeLabel(player.duration)"))
        #expect(miniPlayerSource.contains(".frame(width: 390, height: 132)"))
        #expect(app.contains("NSSize(width: 390, height: 132)"))
        #expect(miniPlayerSource.contains("isCompact ? 12 : 14"))
    }

    @Test func miniPlayerDisablesNativeWindowResizingUntilExpanded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))

        #expect(source.contains("window.styleMask.remove(.resizable)"))
        #expect(source.contains("window.styleMask.insert(.resizable)"))
        #expect(source.contains("MiniPlayerWindowSizeLock(size: NSSize(width: 390, height: 132))"))
        #expect(source.contains("NSWindow.didResizeNotification"))
        #expect(source.contains("window.contentMinSize = size"))
        #expect(source.contains("window.contentMaxSize = size"))
        #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = false"))
        #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = true"))
    }

    @Test func miniPlayerRestoresTheExactExpandedWindowFrameCapturedBeforeSwitching() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))

        #expect(source.contains("@State private var expandedFrame: NSRect?"))
        #expect(source.contains("private var miniPlayerBinding: Binding<Bool>"))
        #expect(source.contains("expandedFrame = window.frame"))
        #expect(source.contains("isMiniPlayer = mini"))
        let capture = try #require(source.range(of: "expandedFrame = window.frame"))
        let switchMode = try #require(source.range(of: "isMiniPlayer = mini", range: capture.upperBound..<source.endIndex))
        #expect(capture.lowerBound < switchMode.lowerBound)
        #expect(source.contains("window.setFrame(restoredFrame, display: true, animate: false)"))
        #expect(!source.contains("@State private var expandedSize"))
    }

    @Test func inspectorAndMiniPlayerShareOneControlSurfaceWithAdjacentPlaybackModes() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let sharedStart = try #require(source.range(of: "private struct UnifiedPlayerControls: View"))
        let sharedSource = String(source[sharedStart.lowerBound...])

        #expect(source.components(separatedBy: "UnifiedPlayerControls(").count - 1 == 2)
        #expect(sharedSource.contains("HStack(spacing: 2)"))
        let shuffle = try #require(sharedSource.range(of: "shuffleButton"))
        let repeatMode = try #require(sharedSource.range(of: "repeatButton", range: shuffle.upperBound..<sharedSource.endIndex))
        #expect(shuffle.lowerBound < repeatMode.lowerBound)
        #expect(sharedSource.contains("Image(systemName: \"shuffle\")"))
        #expect(sharedSource.contains("Image(systemName: repeatModeSymbol)"))
    }

    @Test func playerMenusHideDisclosureIndicatorsAndOfferWholeLibraryShuffle() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))
        let controlsStart = try #require(content.range(of: "private struct UnifiedPlayerControls: View"))
        let controls = String(content[controlsStart.lowerBound...])

        #expect(controls.contains("ライブラリ全体をランダム再生"))
        #expect(controls.contains("Shuffle Entire Library"))
        #expect(controls.contains("Button(action: player.startGlobalShuffle)"))
        #expect(controls.components(separatedBy: ".menuIndicator(.hidden)").count - 1 >= 2)
        #expect(playback.contains("func startGlobalShuffle()"))
        #expect(playback.contains("if isGlobalShuffleEnabled"))
        #expect(playback.contains("database.randomTrack("))
        #expect(playback.contains("rootIDs: connectedRootIDs"))
        #expect(playback.contains("database.randomCachedTrack("))
    }

    @Test func wholeLibraryRandomSelectorsStayBoundedToConnectedRootsOrCache() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.insertSyntheticTracks(count: 5)
        try context.database.recordCachedTrack(trackID: 4, path: "/tmp/random-cache.mp3", fileSize: 4_000)

        let rootTrack = try #require(try context.database.randomTrack(rootIDs: [1], seed: 42))
        let cachedTrack = try #require(try context.database.randomCachedTrack(seed: 42))

        #expect((1...5).contains(rootTrack.id))
        #expect(try context.database.randomTrack(rootIDs: [999], seed: 42) == nil)
        #expect(cachedTrack.id == 4)
    }

    @Test func cacheHeaderShowsCountAndFormattedStorageSize() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("formattedFileSize(model.cachedStorageBytes)"))
        #expect(content.contains("ByteCountFormatter.string"))
        #expect(model.contains("@Published private(set) var cachedStorageBytes: Int64 = 0"))
        #expect(model.contains("cachedStorageBytes = library.cachedBytes"))
    }

    @Test func normalWindowFramePersistsAcrossLaunchesWithoutSavingMiniPlayerSize() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))

        #expect(source.contains("playerWindowFrameStorageKey"))
        #expect(source.contains("NSStringFromRect"))
        #expect(source.contains("NSRectFromString"))
        #expect(source.contains("guard !isMiniPlayer"))
        #expect(source.contains("saveExpandedFrame(window.frame)"))
        #expect(source.contains("fit(window: window)"))
    }

    @Test func shuffleAdvancesOnlyOnceThroughTheRandomCandidatePath() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))
        let start = try #require(source.range(of: "private func loadAdjacent(direction: Int)"))
        let end = try #require(source.range(of: "private func didFinishTrack()", range: start.upperBound..<source.endIndex))
        let implementation = String(source[start.lowerBound..<end.lowerBound])

        #expect(implementation.contains("if direction > 0, shouldShuffle"))
        #expect(implementation.contains("shuffleCandidates("))
        #expect(implementation.components(separatedBy: "startPlayback(nextTrack)").count - 1 == 1)
    }

    @Test func metadataDiagnosticCardsUseCompactSpacing() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let start = try #require(source.range(of: "private var metadataDiagnosticsView: some View"))
        let end = try #require(source.range(of: "private var duplicateSelectionToolbar", range: start.upperBound..<source.endIndex))
        let diagnostics = String(source[start.lowerBound..<end.lowerBound])

        #expect(diagnostics.contains("HStack(spacing: 6)"))
        #expect(diagnostics.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(diagnostics.contains(".padding(.horizontal, 9)"))
        #expect(diagnostics.contains(".padding(.vertical, 7)"))
        #expect(diagnostics.contains(".padding(8)"))
    }

    @Test func registeredLyricsRemainEditableFromTheLyricsTab() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let start = try #require(source.range(of: "private var lyrics: some View"))
        let end = try #require(source.range(of: "private var discovery: some View", range: start.upperBound..<source.endIndex))
        let lyrics = String(source[start.lowerBound..<end.lowerBound])

        #expect(lyrics.contains("if player.currentTrack != nil"))
        #expect(!lyrics.contains("if model.enrichedInfo?.lyrics?.plainLyrics == nil, player.currentTrack != nil"))
        #expect(lyrics.contains("model.text(\"歌詞を編集…\", \"Edit Lyrics…\")"))
        #expect(source.contains("model.text(isEditingExistingLyrics ? \"歌詞を修正\" : \"歌詞を手動で登録\""))
    }

    @Test func lyricsAutoScrollUsesStableLineIDsForSyncedAndPlainLyrics() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("model.enrichedInfo?.lyrics?.syncedLyrics"))
        #expect(source.contains("private var activeLyricLineIndex: Int"))
        #expect(source.contains("proxy.scrollTo(index, anchor: .center)"))
        #expect(source.contains("player.elapsed / player.duration"))
        #expect(source.contains("parseSyncedLyricLine"))
    }

    @Test func practiceTabAutomaticallyDetectsAndPersistsBPMOnDemand() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))
        let detector = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/BPMDetector.swift"))

        #expect(content.contains("player.requestCurrentTrackBPM()"))
        #expect(content.contains("Image(systemName: \"metronome\")"))
        #expect(playback.contains("@Published private(set) var currentBPM: Double?"))
        #expect(playback.contains("playback.practice.detectedBPM.v1"))
        #expect(detector.contains("embeddedID3BPM"))
        #expect(detector.contains("estimateAudioBPM"))
        #expect(detector.contains("maximumFrames = AVAudioFramePosition(format.sampleRate * 180)"))
    }

    @Test func trackContextMenuShowsPlaylistChoicesWithoutANestedSubmenu() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let menuStart = try #require(source.range(of: "    private func trackContextMenu"))
        let menuEnd = try #require(source.range(
            of: "\n    @ViewBuilder private var albumSummaryList",
            range: menuStart.upperBound..<source.endIndex
        ))
        let menu = String(source[menuStart.lowerBound..<menuEnd.lowerBound])

        #expect(menu.contains("Section(model.text(\"プレイリストに追加\", \"Add to Playlist\"))"))
        #expect(menu.contains("ForEach(model.playlists)"))
        #expect(menu.contains("model.createPlaylist()"))
        #expect(!menu.contains("Menu(model.text(\"プレイリストに追加\", \"Add to Playlist\"))"))
    }

    @Test func playlistsAreAvailableBeforeTheFirstContextMenuOpens() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("playlists = orderedPlaylists((try? database.playlists()) ?? [])"))
    }

    @Test func cachedLibraryKeepsControlsAndTrackTableInsideItsVisibleBounds() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private var cacheHeaderControls: some View"))
        #expect(source.contains("private var nonCacheHeaderControls: some View"))
        #expect(source.contains("private var headerControls: some View"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("LibrarySearchField(model: model, isFocused: $isLibrarySearchFocused)"))
        #expect(source.contains("LibrarySearchField(model: model, isFocused: $isLibrarySearchFocused, isFlexible: true)"))
        #expect(source.contains(".id(trackTableContextID)"))
        #expect(source.contains("private var trackTableContextID: String"))
    }

    @Test func metadataAutomationCheckboxesAreTheOnlyStartStopControls() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let settingsStart = try #require(content.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(content.range(
            of: "\nprivate struct SettingsPage",
            range: settingsStart.upperBound..<content.endIndex
        ))
        let settings = String(content[settingsStart.lowerBound..<settingsEnd.lowerBound])

        #expect(!settings.contains("ジャンル検索を開始"))
        #expect(!settings.contains("ジャンル検索を停止"))
        #expect(!settings.contains("リリース年を自動検索・登録"))
        #expect(!settings.contains("リリース年検索を停止"))
        #expect(!settings.contains("ジャンルをマージ・再整理"))
        #expect(settings.contains("model.automaticGenreAutomationStatus"))
        #expect(settings.contains("model.albumYearAutomationStatus"))
        #expect(model.contains("else if !autoRegisterHighConfidenceGenres {\n                cancelAutomaticGenreScan()"))
        #expect(model.contains("guard autoRegisterHighConfidenceGenres else { return }"))
    }

    @Test func sharedPlayerKeepsEveryControlInANarrowLayout() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playerStart = try #require(source.range(of: "private struct UnifiedPlayerControls: View"))
        let playerEnd = try #require(source.range(of: "\nstruct MiniPlayerView", range: playerStart.upperBound..<source.endIndex))
        let player = String(source[playerStart.lowerBound..<playerEnd.lowerBound])

        #expect(player.contains("ViewThatFits(in: .horizontal)"))
        #expect(player.contains("regularPlayerLayout"))
        #expect(player.contains("narrowPlayerLayout"))
        #expect(player.contains("shuffleButton"))
        #expect(player.contains("repeatButton"))
        #expect(player.contains("miniPlayerButton"))
        #expect(player.contains("volumeButton"))
    }

    @Test func externalArticleTranslationCanBeDisabledFromDisplaySettings() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let browser = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/InternalBrowserView.swift"))

        #expect(content.contains("isOn: $model.autoTranslateExternalArticles"))
        #expect(content.contains("private var browserAutoTranslateBinding: Binding<Bool>"))
        #expect(content.contains("autoTranslate: browserAutoTranslateBinding"))
        #expect(model.contains("app.autoTranslateExternalArticles"))
        #expect(browser.contains("guard autoTranslate else { return false }"))
        #expect(browser.contains("Button(action: { autoTranslate.toggle() })"))
        #expect(browser.contains("reloadCurrentPage"))
        #expect(browser.contains("originalArticleURL"))
    }

    @Test func eitherMetadataVariationSpellingCanBeChosenSafely() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("この表記に統一"))
        #expect(content.contains("variationStandardizationRequest"))
        #expect(content.contains("model.standardizeVariation(candidate, choosing: chosenValue)"))
        #expect(model.contains("func standardizeVariation(_ candidate: MetadataVariationCandidate, choosing chosenValue: String)"))
        #expect(model.contains("ExactMetadataFilter(field: candidate.field, value: sourceValue)"))
        #expect(model.contains("updateMetadata(for: tracks, changes: changes)"))
    }

    @Test func appUsesOnlyProtectedDatabaseKeysAndNeverAccessesKeychain() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keyStoreSource = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/OpenAIGenreClassifier.swift"))
        let modelSource = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let initializerStart = try #require(modelSource.range(of: "    init(database:"))
        let initializerEnd = try #require(modelSource.range(of: "\n    var canGoPrevious:", range: initializerStart.upperBound..<modelSource.endIndex))
        let initializer = String(modelSource[initializerStart.lowerBound..<initializerEnd.lowerBound])

        #expect(keyStoreSource.contains("struct ProviderAPIKeyStore"))
        #expect(keyStoreSource.contains("try database.setting(forKey: dbKey)"))
        #expect(keyStoreSource.contains("try database.setSetting(value, forKey: dbKey)"))
        #expect(!keyStoreSource.contains("import Security"))
        #expect(!keyStoreSource.contains("SecItem"))
        #expect(!keyStoreSource.contains("kSec"))
        #expect(!keyStoreSource.contains("Keychain"))
        #expect(!modelSource.contains("Keychain"))
        #expect(initializer.contains("restoreAIProviderConfigurationWithoutReadingKeys()"))
        #expect(!initializer.contains("refreshAIProviderStates"))
        #expect(modelSource.contains("try database.setSetting(\"true\", forKey: \"openai.keyConfigured\")"))
        #expect(modelSource.contains("try database.setSetting(\"true\", forKey: \"gemini.keyConfigured\")"))
        #expect(modelSource.contains("refreshAIProviderStates(validateRemotely: true)"))
    }

    @Test func localAdHocBuildCanLoadItsEmbeddedCoreFramework() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlements = try String(contentsOf: repository.appending(path: "Config/MassiveMusic.entitlements"))

        #expect(entitlements.contains("com.apple.security.cs.disable-library-validation"))
        #expect(entitlements.contains("<true/>"))
    }

    @Test func openingSettingsDoesNotImplicitlyAuthenticateAIProviders() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let settingsStart = try #require(source.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(source.range(of: "\nprivate struct HoverTrackingView", range: settingsStart.upperBound..<source.endIndex))
        let settings = String(source[settingsStart.lowerBound..<settingsEnd.lowerBound])
        let appearStart = try #require(settings.range(of: "        .onAppear {"))
        let appearEnd = try #require(settings.range(of: "\n        }", range: appearStart.upperBound..<settings.endIndex))
        let onAppear = String(settings[appearStart.lowerBound..<appearEnd.upperBound])

        #expect(!onAppear.contains("validateAIProviders"))
        #expect(settings.contains("Button(model.text(\"接続を再確認\", \"Test Connections\"), action: model.validateAIProviders)"))
    }

    @Test func songsDefaultToTitleAscendingAndEverySettingsTabUsesTopAlignedLayout() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let settingsStart = try #require(content.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(content.range(of: "\nprivate struct SettingsPage", range: settingsStart.upperBound..<content.endIndex))
        let settings = String(content[settingsStart.lowerBound..<settingsEnd.lowerBound])

        #expect(model.contains("@Published var sort: TrackSort = .title"))
        #expect(model.contains("if newSection == .tracks, exactFilter == nil {\n            sort = .title\n            sortDirection = .ascending\n        }"))
        #expect(!settings.contains("            Form {"))
        #expect(settings.contains("SettingsPage"))
    }

    @Test func selectedTracksCanBeDraggedOntoAPlaylist() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(content.contains(".draggable(trackDragPayload(for: track))"))
        #expect(content.contains("let trackIDs = values.flatMap(parseTrackDragPayload)"))
        #expect(content.contains("model.addTrackIDsToPlaylist(trackIDs, playlistID: playlist.id)"))
        #expect(model.contains("func addTrackIDsToPlaylist(_ ids: [Int64], playlistID: Int64)"))
    }

    @Test func trackArtistAndAlbumNavigationUseTheEntireCellAsHitTarget() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct TrackNavigationCell: View"))
        #expect(source.contains(".frame(width: width, height: 32, alignment: .leading)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.components(separatedBy: "TrackNavigationCell(").count - 1 >= 2)
    }

    @Test func doubleClickStartsAStreamingSequenceFromTheVisibleTrackList() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(content.contains("player.playFromList(track, context: context)"))
        #expect(playback.contains("func playFromList(_ track: Track, context: TrackPlaybackContext)"))
        #expect(playback.contains("database.adjacentTrack("))
        #expect(playback.contains("wraps: shouldWrap"))
    }

    @Test func backFromArtistOrRenamedAlbumRestoresThePreviousIndexAndPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let closeStart = try #require(model.range(of: "    func closeDetail()"))
        let closeEnd = try #require(model.range(of: "\n    func genreDetailTitle", range: closeStart.upperBound..<model.endIndex))
        let closeDetail = String(model[closeStart.lowerBound..<closeEnd.lowerBound])

        #expect(model.contains("private struct BrowseReturnState"))
        #expect(model.contains("private var browseReturnStack: [BrowseReturnState]"))
        #expect(model.contains("selectedIndexToken: selectedIndexToken"))
        #expect(closeDetail.contains("restoreBrowseReturnState"))
        #expect(closeDetail.contains("loadCurrentPage(reset: false)"))
        #expect(model.contains("let originalAlbumIdentity = AlbumSummary("))
        #expect(model.contains("try await updateMetadataAsync(for: track, edit: edit, closeRenamedAlbumDetail: true)"))
        #expect(model.contains("if closeRenamedAlbumDetail,"))
        #expect(model.contains("selectedAlbum.id == originalAlbumIdentity"))
        #expect(model.contains("selectedAlbum.id != editedAlbumIdentity"))
        #expect(model.contains("closeDetail()"))
        #expect(content.contains("model.selectedIndexToken = token"))
        #expect(!content.contains("@State private var selectedIndexToken"))
    }

    @Test func backNavigationRestoresMetadataDiagnosticsTabPageAndScrollPosition() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let variationSearchStart = try #require(model.range(of: "    func searchVariationValue"))
        let variationSearchEnd = try #require(model.range(of: "\n    func selectPlaylist", range: variationSearchStart.upperBound..<model.endIndex))
        let variationSearch = String(model[variationSearchStart.lowerBound..<variationSearchEnd.lowerBound])

        #expect(model.contains("let diagnosticKind: MetadataIssueKind"))
        #expect(model.contains("let variationFieldFilter: MetadataField?"))
        #expect(model.contains("let metadataIssueFieldFilter: MetadataField?"))
        #expect(model.contains("let exactMetadataFilter: ExactMetadataFilter?"))
        #expect(model.contains("let trackScrollPosition: Int64?"))
        #expect(model.contains("let variationScrollPosition: Int64?"))
        #expect(model.contains("@Published var trackScrollPosition: Int64?"))
        #expect(model.contains("@Published var variationScrollPosition: Int64?"))
        #expect(variationSearch.contains("captureBrowseReturnState()"))
        #expect(!variationSearch.contains("changeSection(.tracks"))
        #expect(model.contains("var isInDetail: Bool {"))
        #expect(model.contains("|| !browseReturnStack.isEmpty"))
        #expect(content.contains("restoreTrackScrollIfNeeded(using: trackScrollProxy)"))
        #expect(content.contains(".scrollPosition(id: $model.variationScrollPosition, anchor: .top)"))
        #expect(model.contains("needsBrowseScrollRestoration = state.trackScrollPosition != nil"))
        #expect(content.contains("restorePendingBrowseScrollPositionIfNeeded()"))
    }

    @Test func backgroundMetadataUpdatesNeverCloseTheOpenAlbumDetail() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let bulkStart = try #require(model.range(of: "    private func runBulkAutoFill() async"))
        let bulkEnd = try #require(model.range(of: "\n    func saveMetadataNormalizationSettings()", range: bulkStart.upperBound..<model.endIndex))
        let bulkAutoFill = String(model[bulkStart.lowerBound..<bulkEnd.lowerBound])

        #expect(bulkAutoFill.contains("updateMetadataAsync(for: localTrack, edit: edit)"))
        #expect(!bulkAutoFill.contains("closeRenamedAlbumDetail: true"))
    }

    @Test func musicBrainzAutoFillAttemptsPersistAndRespectRetryPolicy() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let now = Date(timeIntervalSince1970: 2_000)

        try context.database.recordMusicBrainzAutoFillAttempt(
            albumKey: "artist|album",
            fingerprint: "fingerprint-v1",
            artist: "Artist",
            album: "Album",
            status: .noMatch,
            retryAfter: nil,
            lastError: nil,
            attemptedAt: now
        )

        let noMatch = try #require(
            try context.database.musicBrainzAutoFillAttempt(albumKey: "artist|album")
        )
        #expect(noMatch.status == .noMatch)
        #expect(noMatch.attemptCount == 1)
        #expect(!MusicBrainzAutoFillPolicy.shouldAnalyze(
            previous: noMatch,
            fingerprint: "fingerprint-v1",
            now: now.addingTimeInterval(60)
        ))
        #expect(MusicBrainzAutoFillPolicy.shouldAnalyze(
            previous: noMatch,
            fingerprint: "fingerprint-v2",
            now: now.addingTimeInterval(60)
        ))

        let completed = MusicBrainzAutoFillAttempt(
            albumKey: "completed",
            fingerprint: "fingerprint-v1",
            artist: "Artist",
            album: "Completed Album",
            status: .completed,
            attemptCount: 1,
            retryAfter: nil,
            lastError: nil,
            attemptedAt: now
        )
        #expect(MusicBrainzAutoFillPolicy.shouldAnalyze(
            previous: completed,
            fingerprint: "fingerprint-v1",
            now: now.addingTimeInterval(60)
        ))

        try context.database.recordMusicBrainzAutoFillAttempt(
            albumKey: "artist|album",
            fingerprint: "fingerprint-v1",
            artist: "Artist",
            album: "Album",
            status: .transientFailure,
            retryAfter: now.addingTimeInterval(3_600),
            lastError: "HTTP 503",
            attemptedAt: now.addingTimeInterval(120)
        )

        let transient = try #require(
            try context.database.musicBrainzAutoFillAttempt(albumKey: "artist|album")
        )
        #expect(transient.attemptCount == 2)
        #expect(!MusicBrainzAutoFillPolicy.shouldAnalyze(
            previous: transient,
            fingerprint: "fingerprint-v1",
            now: now.addingTimeInterval(3_599)
        ))
        #expect(MusicBrainzAutoFillPolicy.shouldAnalyze(
            previous: transient,
            fingerprint: "fingerprint-v1",
            now: now.addingTimeInterval(3_601)
        ))
        #expect(MusicBrainzAutoFillPolicy.retryDelay(attemptCount: 1) == 3_600)
        #expect(MusicBrainzAutoFillPolicy.retryDelay(attemptCount: 5) == 57_600)
        #expect(MusicBrainzAutoFillPolicy.retryDelay(attemptCount: 50) == 57_600)
    }

    @Test func musicBrainzAutoFillSummaryAndManualRetriesAreSeparatedByStatus() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let attemptedAt = Date(timeIntervalSince1970: 3_000)

        for (key, status) in [
            ("complete", MusicBrainzAutoFillStatus.completed),
            ("missing", .noMatch),
            ("network", .transientFailure)
        ] {
            try context.database.recordMusicBrainzAutoFillAttempt(
                albumKey: key,
                fingerprint: "fingerprint",
                artist: "Artist",
                album: key,
                status: status,
                retryAfter: status == .transientFailure ? attemptedAt.addingTimeInterval(600) : nil,
                lastError: status == .transientFailure ? "offline" : nil,
                attemptedAt: attemptedAt
            )
        }

        #expect(try context.database.musicBrainzAutoFillSummary() == MusicBrainzAutoFillSummary(
            completed: 1,
            noMatch: 1,
            transientFailure: 1
        ))

        try context.database.clearMusicBrainzAutoFillAttempts(status: .noMatch)
        #expect(try context.database.musicBrainzAutoFillAttempt(albumKey: "missing") == nil)
        #expect(try context.database.musicBrainzAutoFillAttempt(albumKey: "network")?.status == .transientFailure)

        try context.database.clearMusicBrainzAutoFillAttempts(status: .transientFailure)
        #expect(try context.database.musicBrainzAutoFillAttempt(albumKey: "network") == nil)
        #expect(try context.database.musicBrainzAutoFillAttempt(albumKey: "complete")?.status == .completed)
    }

    @Test func musicBrainzSettingsExposeResultsAndExplicitRetryActions() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(model.contains("musicBrainzAutoFillSummary"))
        #expect(model.contains("retryMusicBrainzNoMatches"))
        #expect(model.contains("retryMusicBrainzFailures"))
        #expect(content.contains("一致なしを再解析"))
        #expect(content.contains("通信失敗を再試行"))
    }

    @Test func musicBrainzCandidatesPreferMatchingOfficialAlbumAndParseNumbers() throws {
        let track = Track(
            rootID: 1, relativePath: "Beatles/Come Together.mp3", filename: "Come Together.mp3",
            title: "Come Together", artist: "The Beatles", album: "Abbey Road",
            duration: 259, fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        let json = #"""
        {
          "recordings": [{
            "id": "recording-1", "title": "Come Together", "score": 100, "length": 259000,
            "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
            "releases": [
              {
                "id": "bootleg", "title": "27 No. 1 Singles", "status": "Bootleg", "date": "2001",
                "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
                "media": [{"position": 1, "format": "DVD", "track-count": 27, "track-offset": 24,
                  "track": [{"number": "25", "length": 259000}]}]
              },
              {
                "id": "abbey-road", "title": "Abbey Road", "status": "Official", "date": "1969-09-26",
                "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
                "media": [{"position": 1, "format": "CD", "track-count": 17, "track-offset": 0,
                  "track": [{"number": "1", "length": 259000}]}]
              }
            ]
          }]
        }
        """#.data(using: .utf8)!

        let candidates = try MusicBrainzMetadataMatcher.candidates(from: json, matching: track)
        let best = try #require(candidates.first)
        #expect(best.releaseID == "abbey-road")
        #expect(best.album == "Abbey Road")
        #expect(best.albumArtist == "The Beatles")
        #expect(best.discNumber == 1)
        #expect(best.trackNumber == 1)
        #expect(best.mediumTrackCount == 17)
        #expect(best.matchScore > (candidates.last?.matchScore ?? 0))

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        #expect(content.contains("曲名・アーティスト・アルバム名は変更せず"))
        #expect(content.contains("model.autoFillMusicBrainzTrackNumbers"))
        #expect(!content.contains("edit.album = candidate.album"))
    }

    @Test func bundledGenreClassifierWorksWithoutNetworkOrAPIKey() {
        let classifier = LocalGenreClassifier()
        let jazz = Track(
            rootID: 1, relativePath: "Jazz/Bebop/session.mp3", filename: "session.mp3",
            title: "Night Session", artist: "Charlie Parker", album: "Bebop Masters",
            fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        let unknown = Track(
            rootID: 1, relativePath: "misc/song.mp3", filename: "song.mp3",
            title: "Untitled", fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        #expect(classifier.classify(track: jazz).genre == "Jazz")
        #expect(classifier.classify(track: jazz).confidence >= 0.5)
        #expect(classifier.classify(track: unknown).genre == "Other")
        #expect(classifier.classify(track: unknown).confidence < 0.5)
    }

    @Test func paginationKeepsRelativeJumpsAroundFivePageWindow() {
        let entries = PageNavigation.entries(currentPage: 501, pageCount: 1_852)
        #expect(entries.map(\.label) == [
            "-100", "-10",
            "496", "497", "498", "499", "500", "501", "502", "503", "504", "505", "506",
            "+10", "+100", "+1000",
        ])
        #expect(entries.map(\.target) == [
            401, 491,
            496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506,
            511, 601, 1_501,
        ])
    }

    @Test func paginationClampsRelativeJumpsAtFirstAndLastPage() {
        let first = PageNavigation.entries(currentPage: 1, pageCount: 100)
        #expect(first.allSatisfy { $0.kind != .backward })
        #expect(first.map(\.label) == ["1", "2", "3", "4", "5", "6", "+10"])
        let last = PageNavigation.entries(currentPage: 100, pageCount: 100)
        #expect(last.allSatisfy { $0.kind != .forward })
        #expect(last.map(\.label) == ["-10", "95", "96", "97", "98", "99", "100"])
    }

    @Test func migrationEnablesExpectedSchemaAndWAL() throws {
        let context = try TestContext()
        #expect(try context.database.schemaVersion() == 14)
        #expect(try context.database.journalMode().lowercased() == "wal")
    }

    @Test func compilationTagRoundTripsThroughDatabaseAndBatchChanges() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "compilation", title: "Song", isCompilation: true)
        ], sessionID: 1)
        let stored = try #require(try context.database.track(id: 1))
        #expect(stored.isCompilation)

        let changes = BatchMetadataChanges(isCompilation: false)
        let edit = changes.applying(to: stored)
        try context.database.updateTrackMetadata(
            id: stored.id, edit: edit, fileSize: stored.fileSize, modifiedAt: .now
        )
        #expect(try context.database.track(id: 1)?.isCompilation == false)
    }

    @Test func compactBatchEditorAndResizableSummaryColumnsAreWired() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let start = try #require(content.range(of: "private struct BatchTrackMetadataEditor"))
        let end = try #require(content.range(of: "private struct LibrarySettingsView", range: start.upperBound..<content.endIndex))
        let editor = String(content[start.lowerBound..<end.lowerBound])

        #expect(editor.contains("GroupBox(model.text(\"基本情報\""))
        #expect(editor.contains("Button(model.text(\"保存\", \"Save\")"))
        #expect(editor.contains("model.updateMetadata(for: tracks, changes:"))
        #expect(!editor.contains(".toggleStyle(.checkbox)"))
        #expect(!editor.contains("チェックした項目だけ"))
        #expect(!editor.contains("batchField(model.text(\"タイトル\""))
        #expect(!editor.contains("model.text(\"トラック番号\""))
        #expect(!editor.contains("一覧順に連番"))
        #expect(!editor.contains("changesTrackNumber:"))
        #expect(!editor.contains("LabeledContent(title)"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewAlbumWidth"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewArtistWidth"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewSongsWidth"))
        #expect(model.contains("guard section == requestedSection, selectedAlbum == nil, selectedArtist?.name == artist.name"))
    }

    @Test func appliedAIGenreRefreshesTheCurrentTrackEditorAndPlayer() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let editorStart = try #require(content.range(of: "private struct CurrentTrackInfoEditorView"))
        let editorEnd = try #require(content.range(of: "private struct TrackMetadataEditor", range: editorStart.upperBound..<content.endIndex))
        let editor = String(content[editorStart.lowerBound..<editorEnd.lowerBound])

        #expect(model.contains("@Published private(set) var lastMetadataEditedTrack: Track?"))
        #expect(model.contains("lastMetadataEditedTrack = track.applying(edit)"))
        #expect(editor.contains(".onChange(of: model.lastMetadataEditedTrack)"))
        #expect(editor.contains("loadTrackData(from: updatedTrack)"))
        #expect(editor.contains("player.updateCurrentTrack("))
    }

    @Test func nestedAlbumNavigationRejectsLateArtistAndSearchUpdates() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let openAlbumStart = try #require(model.range(of: "    func openAlbum(_ album: AlbumSummary)"))
        let openAlbumEnd = try #require(model.range(of: "    func openAlbumFromPlayer(for track: Track)", range: openAlbumStart.upperBound..<model.endIndex))
        let openAlbum = String(model[openAlbumStart.lowerBound..<openAlbumEnd.lowerBound])

        #expect(openAlbum.contains("cancelPendingSearchNavigation()"))
        #expect(model.contains("guard section == requestedSection, selectedAlbum == nil, selectedArtist?.name == artist.name else { return }"))
        #expect(model.contains("private func cancelPendingSearchNavigation()"))
    }

    @Test func activityLogRecordsFileAndMetadataChangesWithPagingAndFiltering() throws {
        let context = try TestContext()
        let original = context.importedTrack(identity: "logged", title: "Original", filename: "logged.mp3")
        let changed = context.importedTrack(identity: "logged", title: "Changed by Scan", filename: "logged.mp3")
        _ = try context.database.upsertTracks([original], sessionID: 1)
        _ = try context.database.upsertTracks([changed], sessionID: 2)

        let fetchedTrack = try context.database.track(id: 1)
        let track = try #require(fetchedTrack)
        var edit = TrackMetadataEdit(track: track)
        edit.artist = "Edited Artist"
        try context.database.updateTrackMetadata(
            id: track.id, edit: edit, fileSize: track.fileSize, modifiedAt: .now
        )
        _ = try context.database.markMissingTracks(rootID: 1, sessionID: 3)
        #expect(try context.database.removeTrackFromLibrary(id: 1, fileWasTrashed: false))

        let first = try context.database.activityLogPage(offset: 0, limit: 2)
        let second = try context.database.activityLogPage(offset: 2, limit: 10)
        let metadata = try context.database.activityLogPage(kinds: [.metadataChanged])
        let search = try context.database.activityLogPage(query: "logged.mp3")

        #expect(first.totalCount == 5)
        #expect(first.events.count == 2)
        #expect(second.events.count == 3)
        #expect(Set(first.events.map(\.kind) + second.events.map(\.kind)) == Set([
            .added, .fileModified, .metadataChanged, .unavailable, .removedFromLibrary
        ]))
        #expect(metadata.events.count == 1)
        #expect(metadata.events.first?.changes.contains(where: { $0.field == "artist" }) == true)
        #expect(search.totalCount == 5)
        #expect(first.events.first?.relativePath == "Folder/logged.mp3")
    }

    @Test func activityLogRecordsCacheAndMainStorageAdditionsWithoutCollapsingDistinctEvents() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "storage-log", title: "Storage Log", filename: "storage-log.mp3")
        ], sessionID: 1)

        try context.database.recordTrackActivity(
            trackID: 1, kind: .addedToCache, absolutePath: "/tmp/cache/storage-log.mp3"
        )
        try context.database.recordTrackActivity(
            trackID: 1, kind: .addedToMainStorage, absolutePath: "/Music/storage-log.mp3"
        )
        for index in 0..<1_000 {
            try context.database.recordTrackActivity(
                trackID: 1, kind: .addedToCache, absolutePath: "/tmp/cache/\(index).mp3"
            )
        }

        let firstPage = try context.database.activityLogPage(offset: 0, limit: 100)
        let lastPage = try context.database.activityLogPage(offset: 900, limit: 100)
        #expect(firstPage.totalCount == 1_003)
        #expect(firstPage.events.count == 100)
        #expect(lastPage.events.count == 100)
        #expect(firstPage.events.first?.kind == .addedToCache)
        #expect(firstPage.events.first?.absolutePath == "/tmp/cache/999.mp3")
        #expect(try context.database.trackID(rootID: 1, relativePath: "Folder/storage-log.mp3") == 1)
        #expect(try context.database.trackID(rootID: 2, relativePath: "Folder/storage-log.mp3") == nil)
    }

    @Test func activityLogUsesOneHundredRowPagesAndImportProgressAlwaysResets() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModel = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(viewModel.contains("let activityPageSize = 100"))
        #expect(viewModel.contains("section == .activityLog ? activityPageSize : pageSize"))
        #expect(viewModel.contains("defer { importProgress = .idle }"))
        #expect(viewModel.contains("for (index, sourceURL) in stageURLs.enumerated()"))
    }

    @Test func favoritesAreDynamicAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 3)
        #expect(try context.database.toggleFavorite(trackID: 2))
        let page = try context.database.pageFavoriteTracks()
        #expect(page.totalCount == 1)
        #expect(page.tracks.first?.id == 2)
        #expect(page.tracks.first?.isFavorite == true)
    }

    @Test func multipleTracksCanBeFavoritedInOneDatabaseWriteAndFromTheSelectionMenu() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "favorite-one", title: "One", filename: "one.mp3"),
            context.importedTrack(identity: "favorite-two", title: "Two", filename: "two.mp3"),
            context.importedTrack(identity: "favorite-three", title: "Three", filename: "three.mp3")
        ], sessionID: 1)
        let tracks = try context.database.pageTracks(limit: 10).tracks

        try context.database.setFavorites(trackIDs: tracks.prefix(2).map(\.id), isFavorite: true)
        #expect(try context.database.favoriteTrackCount() == 2)
        try context.database.setFavorites(trackIDs: tracks.map(\.id), isFavorite: false)
        #expect(try context.database.favoriteTrackCount() == 0)

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        #expect(content.contains("model.setFavorites(selectedTracksOnPage, isFavorite: true)"))
        #expect(content.contains("model.addSelectionToPlaylist(playlist.id)"))
        #expect(model.contains("func setFavorites(_ tracks: [Track], isFavorite: Bool)"))
    }

    @Test func favoriteOfflineCacheCanBePinnedOutsideRecentLimit() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 2)
        try context.database.recordCachedTrack(trackID: 1, path: "/tmp/recent.mp3", fileSize: 1)
        try context.database.recordCachedTrack(trackID: 2, path: "/tmp/favorite.mp3", fileSize: 1, pinned: true)

        #expect(try context.database.isCachedTrackPinned(trackID: 2))
        #expect(try context.database.cachedTracksBeyondLimit(0).map(\.0) == [1])

        try context.database.setCachedTrackPinned(trackID: 2, pinned: false)
        #expect(try !context.database.isCachedTrackPinned(trackID: 2))
        #expect(Set(try context.database.cachedTracksBeyondLimit(0).map(\.0)) == Set([1, 2]))
    }

    @Test func favoriteAndPlaylistTracksAreNeverAutomaticallyEvictedFromCache() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 4)
        for trackID in 1...4 {
            try context.database.recordCachedTrack(
                trackID: Int64(trackID), path: "/tmp/protected-\(trackID).mp3", fileSize: 1,
                pinned: trackID == 4
            )
        }
        try context.database.setFavorite(trackID: 2, isFavorite: true)
        let playlistID = try context.database.createPlaylist(name: "Protected")
        _ = try context.database.addTracks([3], toPlaylist: playlistID)

        #expect(try context.database.cachedTracksBeyondLimit(0).map(\.0) == [1])

        try context.database.setFavorite(trackID: 2, isFavorite: false)
        try context.database.removeTrack(3, fromPlaylist: playlistID)
        #expect(Set(try context.database.cachedTracksBeyondLimit(0).map(\.0)) == Set([1, 2, 3]))
    }

    @Test func favoriteAndPlaylistTracksArePagedForAutomaticCaching() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 5)
        try context.database.setFavorite(trackID: 2, isFavorite: true)
        let playlistID = try context.database.createPlaylist(name: "Practice")
        _ = try context.database.addTracks([4, 5], toPlaylist: playlistID)

        let firstPage = try context.database.protectedTracksForCaching(afterID: 0, limit: 2)
        let secondPage = try context.database.protectedTracksForCaching(
            afterID: try #require(firstPage.last?.id),
            limit: 2
        )

        #expect(firstPage.map(\.id) == [2, 4])
        #expect(secondPage.map(\.id) == [5])

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        #expect(model.contains("syncProtectedTracksToCacheIfNeeded()"))
        #expect(model.contains("offlineCache.cacheForFavorite(track)"))
        #expect(model.contains("protectedCacheIsReconciled = false"))
    }

    @Test func cachedSongsArePagedAndExposeCurrentPageCacheStatus() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 4)
        try context.database.recordCachedTrack(trackID: 2, path: "/tmp/two.mp3", fileSize: 2_000)
        try context.database.recordCachedTrack(trackID: 4, path: "/tmp/four.mp3", fileSize: 4_000, pinned: true)

        let firstPage = try context.database.pageCachedTracks(
            sort: .title, direction: .ascending, offset: 0, limit: 1
        )
        let secondPage = try context.database.pageCachedTracks(
            sort: .title, direction: .ascending, offset: 1, limit: 1
        )

        #expect(firstPage.totalCount == 2)
        #expect(firstPage.tracks.count == 1)
        #expect(secondPage.totalCount == 2)
        #expect(secondPage.tracks.count == 1)
        #expect(Set(firstPage.tracks.map(\.id) + secondPage.tracks.map(\.id)) == Set([2, 4]))
        #expect(try context.database.cachedTrackIDs(in: [1, 2, 3, 4]) == Set([2, 4]))
        #expect(try context.database.cachedTrackIDs(in: []) == [])
    }

    @Test func settingsImportsAndLyricsRoundTrip() throws {
        let context = try TestContext()
        try context.database.setSetting("24", forKey: "cache.trackLimit")
        #expect(try context.database.setting(forKey: "cache.trackLimit") == "24")
        let importID = try context.database.addPendingImport(localPath: "/tmp/song.mp3", filename: "song.mp3")
        #expect(try context.database.pendingImports().first?.id == importID)
        _ = try context.database.insertSyntheticTracks(count: 1)
        try context.database.saveLyrics(trackID: 1, provider: "test", plain: "hello", synced: nil)
        #expect(try context.database.cachedLyrics(trackID: 1)?.plainLyrics == "hello")
    }

    @Test func duplicateIdentityUpdatesWithoutAddingAnotherTrack() throws {
        let context = try TestContext()
        let original = context.importedTrack(identity: "same", title: "Original")
        let updated = context.importedTrack(identity: "same", title: "Updated")

        _ = try context.database.upsertTracks([original], sessionID: 1)
        _ = try context.database.upsertTracks([updated], sessionID: 2)

        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.pageTracks().tracks.first?.title == "Updated")
    }

    @Test func removedTrackStaysExcludedFromFutureScans() throws {
        let context = try TestContext()
        let item = context.importedTrack(identity: "excluded", title: "Removed")
        _ = try context.database.upsertTracks([item], sessionID: 1)
        #expect(try context.database.removeTrackFromLibrary(id: 1, fileWasTrashed: false))
        #expect(try context.database.trackCount() == 0)
        #expect(try context.database.isExcluded(identityKey: "excluded"))

        _ = try context.database.upsertTracks([item], sessionID: 2)
        #expect(try context.database.trackCount() == 0)
    }

    @Test func metadataEditUpdatesFTSAtomically() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "editable", title: "Old Title")], sessionID: 1
        )
        let fetched = try context.database.track(id: 1)
        let track = try #require(fetched)
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Northern Rewrite"
        edit.artist = "Edited Artist"
        edit.artworkData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try context.database.updateTrackMetadata(
            id: track.id, edit: edit, fileSize: track.fileSize, modifiedAt: track.modifiedAt
        )
        #expect(try context.database.pageTracks(query: "Northern").totalCount == 1)
        #expect(try context.database.pageTracks(query: "Old").totalCount == 0)
        #expect(try context.database.track(id: track.id)?.hasArtwork == true)
    }

    @Test func leadingTitleSpaceCleanupCandidatesAreKeysetPaged() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "half", title: " Half", filename: "half.mp3"),
            context.importedTrack(identity: "clean", title: "Clean", filename: "clean.mp3"),
            context.importedTrack(identity: "full", title: "　Full", filename: "full.m4a", format: "m4a")
        ], sessionID: 1)

        let first = try context.database.tracksWithLeadingTitleSpaces(afterID: 0, limit: 1)
        let second = try context.database.tracksWithLeadingTitleSpaces(afterID: try #require(first.first?.id), limit: 1)

        #expect(first.map(\.title) == [" Half"])
        #expect(second.map(\.title) == ["　Full"])
        #expect(try context.database.tracksWithLeadingTitleSpaces(afterID: try #require(second.first?.id), limit: 1).isEmpty)
    }

    @Test func fullTextSearchFindsMetadataAndFilename() throws {
        let context = try TestContext()
        let importItem = context.importedTrack(
            identity: "fts", title: "Northern Lights", artist: "Aurora Unit",
            album: "Night Drive", filename: "special-mix.mp3"
        )
        _ = try context.database.upsertTracks([importItem], sessionID: 1)

        #expect(try context.database.pageTracks(query: "Aurora").totalCount == 1)
        #expect(try context.database.pageTracks(query: "special").totalCount == 1)
        #expect(try context.database.pageTracks(query: "missing").totalCount == 0)
    }

    @Test func playlistStoresTrackIDsInStableOrderAndCanReorder() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 5)
        let all = try context.database.pageTracks(limit: 5).tracks
        let playlistID = try context.database.createPlaylist(name: "Order")
        _ = try context.database.addTracks(all.map(\.id), toPlaylist: playlistID)

        try context.database.movePlaylistItem(playlistID: playlistID, from: 0, to: 3)
        let reordered = try context.database.playlistTracks(playlistID: playlistID, offset: 0, limit: 5)

        #expect(reordered.tracks.count == 5)
        #expect(reordered.tracks[3].id == all[0].id)
    }

    @Test func persistentPlayQueueKeepsOrderPagesAndDequeuesOneItem() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 4)
        #expect(try context.database.enqueueNext(trackID: 3))
        #expect(try context.database.enqueueNext(trackID: 1))
        #expect(try context.database.enqueueNext(trackID: 3))

        let firstPage = try context.database.playQueuePage(limit: 2)
        #expect(firstPage.totalCount == 3)
        #expect(firstPage.tracks.map(\.id) == [3, 1])
        #expect(try context.database.dequeueNext()?.id == 3)
        #expect(try context.database.playQueuePage().tracks.map(\.id) == [1, 3])

        try context.database.removeFromPlayQueue(trackID: 3)
        #expect(try context.database.playQueuePage().tracks.map(\.id) == [1])
        try context.database.clearPlayQueue()
        #expect(try context.database.playQueuePage().totalCount == 0)
    }

    @Test func largePlaylistIsChunkedAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 10_500)
        let playlistID = try context.database.createPlaylist(name: "Large")
        let added = try context.database.addTracks(Int64(1)...Int64(10_500), toPlaylist: playlistID)

        let page = try context.database.playlistTracks(playlistID: playlistID, offset: 10_000, limit: 200)
        #expect(added == 10_500)
        #expect(page.tracks.count == 200)
        #expect(page.totalCount == 10_500)
    }

    @Test func shuffleCandidatesAreBoundedAndDoNotMaterializeLibrary() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 8_000)
        let candidates = try context.database.shuffleCandidates(afterID: 0, seed: 42, limit: 25)

        #expect(candidates.count <= 25)
        #expect(Set(candidates.map(\.id)).count == candidates.count)
    }

    @Test func keysetPagingReturnsNextPageWithoutOverlap() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let first = try context.database.pageTracksAfter(sort: .artist, after: nil, limit: 200)
        let second = try context.database.pageTracksAfter(
            sort: .artist, after: first.tracks.last, logicalOffset: 200, limit: 200,
            knownTotal: first.totalCount
        )

        #expect(first.tracks.count == 200)
        #expect(second.tracks.count == 200)
        #expect(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
    }

    @Test func playbackSequenceFollowsVisibleAlbumOrderInBothDirections() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "one", title: "One", artist: "Band", album: "Record", filename: "one.mp3", trackNumber: 1),
            context.importedTrack(identity: "two", title: "Two", artist: "Band", album: "Record", filename: "two.mp3", trackNumber: 2),
            context.importedTrack(identity: "three", title: "Three", artist: "Band", album: "Record", filename: "three.mp3", trackNumber: 3),
            context.importedTrack(identity: "other", title: "Other", artist: "Band", album: "Other Record", filename: "other.mp3", trackNumber: 3)
        ], sessionID: 1)
        let album = AlbumSummary(name: "Record", artist: "Band", trackCount: 3)
        let ordered = try context.database.pageTracksForAlbum(album: album, sort: .trackNumber).tracks
        let sequence = TrackPlaybackContext(
            scope: .album(name: album.name, artist: album.artist),
            sort: .trackNumber,
            direction: .ascending
        )

        let next = try context.database.adjacentTrack(in: sequence, from: ordered[1], direction: 1)
        let previous = try context.database.adjacentTrack(in: sequence, from: ordered[1], direction: -1)

        #expect(next?.title == "Three")
        #expect(previous?.title == "One")
    }

    @Test func repeatAllWrapsAnAlbumSequenceToItsFirstTrack() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "first", title: "First", artist: "Band", album: "Record", filename: "first.mp3", trackNumber: 1),
            context.importedTrack(identity: "last", title: "Last", artist: "Band", album: "Record", filename: "last.mp3", trackNumber: 2),
            context.importedTrack(identity: "other", title: "Other", artist: "Band", album: "Other", filename: "other.mp3", trackNumber: 1)
        ], sessionID: 1)
        let album = AlbumSummary(name: "Record", artist: "Band", trackCount: 2)
        let ordered = try context.database.pageTracksForAlbum(album: album, sort: .trackNumber).tracks
        let sequence = TrackPlaybackContext(
            scope: .album(name: album.name, artist: album.artist),
            sort: .trackNumber,
            direction: .ascending
        )

        let wrapped = try context.database.adjacentTrack(
            in: sequence,
            from: try #require(ordered.last),
            direction: 1,
            wraps: true
        )
        let stopped = try context.database.adjacentTrack(
            in: sequence,
            from: try #require(ordered.last),
            direction: 1
        )

        #expect(wrapped?.title == "First")
        #expect(stopped == nil)
    }

    @Test func playbackSequenceCrossesPageBoundaryWithoutBuildingAGiantQueue() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 405)
        let pageEnd = try context.database.pageTracks(sort: .title, offset: 199, limit: 1).tracks[0]
        let expected = try context.database.pageTracks(sort: .title, offset: 200, limit: 1).tracks[0]
        let sequence = TrackPlaybackContext(scope: .library(query: ""), sort: .title, direction: .ascending)

        let next = try context.database.adjacentTrack(in: sequence, from: pageEnd, direction: 1)

        #expect(next?.id == expected.id)
        #expect(try context.database.playQueuePage().totalCount == 0)
    }

    @Test func descendingKeysetSortIsStable() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let first = try context.database.pageTracksAfter(sort: .title, direction: .descending, after: nil, limit: 200)
        let second = try context.database.pageTracksAfter(
            sort: .title, direction: .descending, after: first.tracks.last,
            logicalOffset: 200, limit: 200, knownTotal: first.totalCount
        )
        #expect(first.tracks.count == 200)
        #expect(second.tracks.count == 200)
        #expect(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
        #expect(first.tracks.first!.title.localizedCaseInsensitiveCompare(first.tracks.last!.title) != .orderedAscending)
    }

    @Test func discAndTrackNumberSortsAreNumericAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "d2t1", title: "Disc Two", filename: "d2.mp3", discNumber: 2, trackNumber: 1),
            context.importedTrack(identity: "d1t10", title: "Track Ten", filename: "t10.mp3", discNumber: 1, trackNumber: 10),
            context.importedTrack(identity: "d1t2", title: "Track Two", filename: "t2.mp3", discNumber: 1, trackNumber: 2)
        ], sessionID: 1)

        let byDisc = try context.database.pageTracksAfter(sort: .discNumber, after: nil, limit: 10)
        let byTrack = try context.database.pageTracksAfter(sort: .trackNumber, after: nil, limit: 10)

        #expect(byDisc.tracks.map { [$0.discNumber, $0.trackNumber] } == [[1, 2], [1, 10], [2, 1]])
        #expect(byTrack.tracks.map(\.trackNumber) == [1, 2, 10])
    }

    @Test func albumAndArtistSummariesArePagedAndCounted() throws {
        let context = try TestContext()
        let imports = [
            context.importedTrack(identity: "one", title: "One", artist: "Artist A", album: "Album A", filename: "one.mp3"),
            context.importedTrack(identity: "two", title: "Two", artist: "Artist A", album: "Album A", filename: "two.mp3"),
            context.importedTrack(identity: "three", title: "Three", artist: "Artist A", album: "Album B", filename: "three.mp3")
        ]
        _ = try context.database.upsertTracks(imports, sessionID: 1)
        let artists = try context.database.pageArtists()
        let albums = try context.database.pageAlbums(artistFilter: "Artist A")
        #expect(artists.artists.first?.trackCount == 3)
        #expect(artists.artists.first?.albumCount == 2)
        #expect(albums.totalCount == 2)
        #expect(albums.albums.first(where: { $0.name == "Album A" })?.trackCount == 2)
        #expect(try context.database.albumTrackCount(album: "album a", artist: "artist a") == 2)
        let albumTracks = try context.database.pageTracksForAlbum(album: AlbumSummary(name: "Album A", artist: "Artist A", trackCount: 2))
        #expect(albumTracks.totalCount == 2)
    }

    @Test func releaseYearAndArtistGenreStayPagedSortableAndDeterministic() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "old-rock", title: "Old", artist: "Amp", genre: "Rock", year: "1971", filename: "old.mp3"),
            context.importedTrack(identity: "new-rock", title: "New", artist: "Amp", genre: "Rock", year: "2024", filename: "new.mp3"),
            context.importedTrack(identity: "jazz", title: "Blue", artist: "Amp", genre: "Jazz", year: "1999", filename: "blue.mp3"),
            context.importedTrack(identity: "none", title: "Unknown", artist: "Blank", genre: "", year: "", filename: "none.mp3")
        ], sessionID: 1)

        let byYear = try context.database.pageTracks(sort: .year, direction: .ascending, limit: 10)
        let artists = try context.database.pageArtists(sort: .genre, direction: .ascending)
        let amp = try #require(artists.artists.first(where: { $0.name == "Amp" }))

        #expect(byYear.tracks.map(\.year) == ["", "1971", "1999", "2024"])
        #expect(amp.genre == "Rock")
        #expect(try context.database.artistSummary(named: "amp")?.genre == "Rock")
    }

    @Test func libraryColumnsAndPlayerMetadataExposeRequestedNavigation() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let controlsStart = try #require(content.range(of: "private struct UnifiedPlayerControls: View"))
        let controls = String(content[controlsStart.lowerBound...])

        #expect(content.contains("@AppStorage(\"columns.year.visible\")"))
        #expect(content.contains("@AppStorage(\"columns.artistView.genre.visible\")"))
        #expect(content.contains("case .year:"))
        #expect(content.contains("artist.genre"))
        #expect(controls.contains("model.openAlbumFromPlayer(for: track)"))
        #expect(controls.contains("model.openArtistFromPlayer(named: track.artist)"))
        #expect(model.contains("func openAlbumFromPlayer(for track: Track)"))
        #expect(model.contains("func openArtistFromPlayer(named name: String)"))
        #expect(model.contains("section = .albums"))
        #expect(model.contains("section = .artists"))
    }

    @Test func playerAlbumNavigationPrefersAlbumArtistAndTrimsMetadata() {
        let track = Track(
            rootID: 1,
            relativePath: "song.mp3",
            filename: "song.mp3",
            title: "Song",
            artist: " Track Artist ",
            album: " Album ",
            albumArtist: " Album Artist ",
            fileSize: 1,
            modifiedAt: Date(),
            format: "MP3"
        )
        let fallback = Track(
            rootID: 1,
            relativePath: "fallback.mp3",
            filename: "fallback.mp3",
            title: "Fallback",
            artist: " Track Artist ",
            album: " Album ",
            albumArtist: "  ",
            fileSize: 1,
            modifiedAt: Date(),
            format: "MP3"
        )

        #expect(track.albumNavigationArtist == "Album Artist")
        #expect(fallback.albumNavigationArtist == "Track Artist")
    }

    @Test func metadataVariationLinkUsesExactFieldAndValue() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "exact", title: "One", album: "Same", filename: "one.mp3"),
            context.importedTrack(identity: "case", title: "Two", album: "same", filename: "two.mp3"),
            context.importedTrack(identity: "other", title: "Same", album: "Other", filename: "three.mp3")
        ], sessionID: 1)

        let page = try context.database.pageTracks(matching: ExactMetadataFilter(field: .album, value: "Same"))
        #expect(page.totalCount == 1)
        #expect(page.tracks.map(\.filename) == ["one.mp3"])

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        #expect(content.contains("searchVariationValue(candidate.valueA, field: candidate.field"))
        #expect(content.contains("searchVariationValue(candidate.valueB, field: candidate.field"))
        #expect(model.contains("captureBrowseReturnState()"))
        #expect(model.contains("section = .tracks"))
        #expect(model.contains("exactMetadataFilter = ExactMetadataFilter(field: field, value: value)"))
    }

    @Test func storageSummaryAggregatesBytesAndAbsoluteRootsWithoutLoadingTracks() throws {
        let context = try TestContext()
        let rootID = try context.database.addScanRoot(
            displayName: "Music", bookmark: Data(), volumeUUID: "test-volume", path: context.directory.path
        )
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "one", title: "One", artist: "Artist A", album: "Album A", filename: "one.mp3", rootID: rootID),
            context.importedTrack(identity: "two", title: "Two", artist: "Artist A", album: "Album A", filename: "two.mp3", rootID: rootID),
            context.importedTrack(identity: "three", title: "Three", artist: "Artist B", album: "Album B", filename: "three.mp3", rootID: rootID)
        ], sessionID: 1)

        let library = try context.database.libraryStorageSummary()
        let album = try context.database.libraryStorageSummary(
            albumFilter: AlbumSummary(name: "Album A", artist: "Artist A", trackCount: 2)
        )
        let artist = try context.database.libraryStorageSummary(artistFilter: "Artist A")

        #expect(library.totalBytes == 3_072)
        #expect(library.absoluteRootPaths == [context.directory.path])
        #expect(album.totalBytes == 2_048)
        #expect(artist.totalBytes == 2_048)
    }

    @Test func facetPagesReportExactTotalInsteadOfNextPageEstimate() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let page = try context.database.facetPage(section: .genres, offset: 10, limit: 5)
        #expect(page.facets.count == 5)
        #expect(page.offset == 10)
        #expect(page.totalCount == 40)
    }

    @Test func genreDetailPagesOnlyReturnMatchingAlbumsArtistsAndTracks() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "rock-1", title: "Rock One", artist: "Amp", album: "Loud", genre: "Rock", filename: "rock-1.mp3"),
            context.importedTrack(identity: "rock-2", title: "Rock Two", artist: "Amp", album: "Loud", genre: "Rock", filename: "rock-2.mp3"),
            context.importedTrack(identity: "rock-3", title: "Rock Three", artist: "Stone", album: "Granite", genre: "Rock", filename: "rock-3.mp3"),
            context.importedTrack(identity: "jazz-1", title: "Jazz One", artist: "Blue", album: "Night", genre: "Jazz", filename: "jazz-1.mp3")
        ], sessionID: 1)

        let albums = try context.database.pageAlbums(genreFilter: "rock")
        let artists = try context.database.pageArtists(genreFilter: "ROCK")
        let tracks = try context.database.pageTracksForGenre(genre: "Rock", limit: 2)

        #expect(albums.totalCount == 2)
        #expect(Set(albums.albums.map(\.name)) == ["Loud", "Granite"])
        #expect(artists.totalCount == 2)
        #expect(Set(artists.artists.map(\.name)) == ["Amp", "Stone"])
        #expect(tracks.totalCount == 3)
        #expect(tracks.tracks.count == 2)
        #expect(tracks.tracks.allSatisfy { $0.genre == "Rock" })
    }

    @Test func alphabeticalOffsetsJumpToLatinKanaAndNumericEntries() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "numeric", title: "0 Zero", artist: "1 Artist", album: "2 Album", filename: "0.mp3"),
            context.importedTrack(identity: "alpha", title: "Alpha", artist: "Alpha Artist", album: "Alpha Album", filename: "a.mp3"),
            context.importedTrack(identity: "beta", title: "Beta", artist: "Beta Artist", album: "Beta Album", filename: "b.mp3"),
            context.importedTrack(identity: "kana-a", title: "あさ", artist: "あお", album: "あさ", filename: "kana-a.mp3"),
            context.importedTrack(identity: "kana-ka", title: "かぜ", artist: "かお", album: "かぜ", filename: "kana-ka.mp3")
        ], sessionID: 1)

        let titleOffset = try context.database.offsetForTrackTitle(startingAt: "B")
        #expect(try context.database.pageTracks(sort: .title, offset: titleOffset, limit: 1).tracks.first?.title == "Beta")
        let kanaTitleOffset = try context.database.offsetForTrackTitle(startingAt: "か")
        #expect(try context.database.pageTracks(sort: .title, offset: kanaTitleOffset, limit: 1).tracks.first?.title == "かぜ")
        let artistOffset = try context.database.offsetForArtist(startingAt: "A")
        #expect(try context.database.pageArtists(offset: artistOffset, limit: 1).artists.first?.name == "Alpha Artist")
        let descendingArtistOffset = try context.database.offsetForArtist(startingAt: "B", direction: .descending)
        #expect(
            try context.database.pageArtists(
                sort: .name,
                direction: .descending,
                offset: descendingArtistOffset,
                limit: 1
            ).artists.first?.name == "Beta Artist"
        )
        let albumOffset = try context.database.offsetForAlbum(startingAt: "あ")
        #expect(try context.database.pageAlbums(offset: albumOffset, limit: 1).albums.first?.name == "あさ")
    }

    @Test func artistSearchAndAlphabeticalOrderIgnoreLeadingThe() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "alpha", title: "One", artist: "Alpha", filename: "a.mp3"),
            context.importedTrack(identity: "beatles", title: "Two", artist: "The Beatles", filename: "b.mp3"),
            context.importedTrack(identity: "clash", title: "Three", artist: "the Clash", filename: "c.mp3")
        ], sessionID: 1)

        let all = try context.database.pageArtists()
        #expect(all.artists.map(\.name) == ["Alpha", "The Beatles", "the Clash"])
        let withoutArticle = try context.database.pageArtists(search: "Beatles")
        #expect(withoutArticle.artists.map(\.name) == ["The Beatles"])
        let bOffset = try context.database.offsetForArtist(startingAt: "B")
        #expect(try context.database.pageArtists(offset: bOffset, limit: 1).artists.first?.name == "The Beatles")
    }

    @Test func unknownArtistIsLogicalPagedGroupWithoutChangingEmptyTag() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "unknown-1", title: "One", artist: "", album: "Album A", filename: "one.mp3"),
            context.importedTrack(identity: "unknown-2", title: "Two", artist: "", album: "", filename: "two.mp3"),
            context.importedTrack(identity: "known", title: "Three", artist: "Known", filename: "three.mp3")
        ], sessionID: 1)

        let artists = try context.database.pageArtists()
        let unknown = try #require(artists.artists.first(where: { $0.name.isEmpty }))
        let page = try context.database.pageTracksForArtist(artist: "", limit: 1)

        #expect(unknown.trackCount == 2)
        #expect(unknown.albumCount == 1)
        #expect(page.totalCount == 2)
        #expect(page.tracks.count == 1)
        #expect(page.tracks[0].artist.isEmpty)
    }

    @Test func metadataDiagnosticsCountAndPageMissingAndURLValues() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "missing", title: "", artist: "", album: "", filename: "missing.mp3"),
            context.importedTrack(identity: "url", title: "Tagged", genre: "http://example.invalid", filename: "url.mp3"),
            context.importedTrack(identity: "mojibake", title: "I ĐAÈA  ÔÌ¼", artist: "Artist", album: "Album", filename: "garbled.mp3"),
            context.importedTrack(identity: "clean", title: "Clean", filename: "clean.m4a", format: "m4a")
        ], sessionID: 1)

        let summaries = try context.database.metadataIssueSummaries()
        #expect(summaries.first(where: { $0.kind == .missingTitle })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingArtist })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingAlbum })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingYear })?.count == 4)
        #expect(summaries.first(where: { $0.kind == .urlInMP3Metadata })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .suspectedMojibake })?.count == 1)
        #expect(try context.database.pageMetadataIssues(kind: .missingYear).totalCount == 4)
        #expect(try context.database.pageMetadataIssues(kind: .urlInMP3Metadata).tracks.first?.filename == "url.mp3")
        #expect(try context.database.pageMetadataIssues(kind: .suspectedMojibake).tracks.first?.filename == "garbled.mp3")
    }

    @Test func metadataIssuePagesCanBeFilteredByTitleAlbumOrArtist() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "url-title", title: "https://example.invalid/title", artist: "Artist", album: "Album", filename: "url-title.mp3"),
            context.importedTrack(identity: "url-artist", title: "Song", artist: "www.example.invalid", album: "Album", filename: "url-artist.mp3"),
            context.importedTrack(identity: "url-album", title: "Song", artist: "Artist", album: "http://example.invalid/album", filename: "url-album.mp3"),
            context.importedTrack(identity: "mojibake-title", title: "Bad Ã Title", artist: "Artist", album: "Album", filename: "mojibake-title.mp3"),
            context.importedTrack(identity: "mojibake-artist", title: "Song", artist: "Bad Â Artist", album: "Album", filename: "mojibake-artist.mp3"),
            context.importedTrack(identity: "mojibake-album", title: "Song", artist: "Artist", album: "Bad 縺 Album", filename: "mojibake-album.mp3")
        ], sessionID: 1)

        let urlTitles = try context.database.pageMetadataIssues(kind: .urlInMP3Metadata, field: .title)
        let urlArtists = try context.database.pageMetadataIssues(kind: .urlInMP3Metadata, field: .artist)
        let urlAlbums = try context.database.pageMetadataIssues(kind: .urlInMP3Metadata, field: .album)
        let mojibakeTitles = try context.database.pageMetadataIssues(kind: .suspectedMojibake, field: .title)
        let mojibakeArtists = try context.database.pageMetadataIssues(kind: .suspectedMojibake, field: .artist)
        let mojibakeAlbums = try context.database.pageMetadataIssues(kind: .suspectedMojibake, field: .album)

        #expect(urlTitles.tracks.map(\.filename) == ["url-title.mp3"])
        #expect(urlArtists.tracks.map(\.filename) == ["url-artist.mp3"])
        #expect(urlAlbums.tracks.map(\.filename) == ["url-album.mp3"])
        #expect(mojibakeTitles.tracks.map(\.filename) == ["mojibake-title.mp3"])
        #expect(mojibakeArtists.tracks.map(\.filename) == ["mojibake-artist.mp3"])
        #expect(mojibakeAlbums.tracks.map(\.filename) == ["mojibake-album.mp3"])
        #expect(urlTitles.totalCount == 1)
        #expect(mojibakeAlbums.totalCount == 1)
    }

    @Test func duplicateMetadataDiagnosticsUseBoundedGroupAggregation() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "duplicate-1", title: "Same", artist: "Artist", album: "Album", filename: "one.mp3"),
            context.importedTrack(identity: "duplicate-2", title: "same", artist: "artist", album: "album", filename: "two.mp3"),
            context.importedTrack(identity: "unique", title: "Other", artist: "Artist", album: "Album", filename: "three.mp3")
        ], sessionID: 1)

        let summaries = try context.database.metadataIssueSummaries()
        let page = try context.database.pageMetadataIssues(kind: .duplicateTracks)

        #expect(summaries.first(where: { $0.kind == .duplicateTracks })?.count == 2)
        #expect(page.totalCount == 2)
        #expect(Set(page.tracks.map(\.filename)) == ["one.mp3", "two.mp3"])
    }

    @Test func metadataNavigationCancelsStaleSummaryAndPageLoads() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("pageLoadTask?.cancel()"))
        #expect(source.contains("metadataSummaryTask?.cancel()"))
        #expect(source.contains("catch is CancellationError"))
        #expect(source.contains("guard !Task.isCancelled else { return }"))
    }

    @Test func duplicateDiagnosticsProvideCheckboxesAndConfirmedBulkDeletion() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private var isDuplicateSelectionMode: Bool"))
        #expect(source.contains("private func duplicateSelectionCheckbox"))
        #expect(source.contains("model.selectedTrackIDs.formUnion(model.tracks.map(\\.id))"))
        #expect(source.contains("tracksPendingDeletion = selectedTracksOnPage"))
        #expect(source.contains("選択した\\(selectedTracksOnPage.count)曲を削除…"))
        #expect(source.contains("ライブラリからのみ削除"))
        #expect(source.contains("実ファイルをゴミ箱へ移動"))
    }

    @Test func commandASelectsOnlyTheFocusedVisibleTrackPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("@FocusState private var isTrackTableFocused: Bool"))
        #expect(source.contains("private func selectAllVisibleTracks()"))
        #expect(source.contains("model.selectedTrackIDs = Set(model.tracks.map(\\.id))"))
        #expect(source.contains(".focused($isTrackTableFocused)"))
        #expect(source.contains(".onKeyPress(\"a\", phases: .down)"))
        #expect(source.contains("keyPress.modifiers.contains(.command)"))
    }

    @Test func cacheRetentionLimitCanBeTypedAndStepped() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct CacheTrackLimitControl: View"))
        #expect(source.contains("TextField(\"\", value: $value, format: .number)"))
        #expect(source.contains("Stepper(value: $value, in: limits)"))
        #expect(source.components(separatedBy: "CacheTrackLimitControl(").count - 1 >= 2)
    }

    @Test func flacImportDoesNotBlockOnProcessWaitAndAddsPlaylistItemsIncrementally() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let services = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(!services.contains("process.waitUntilExit()"))
        #expect(services.contains("let terminationStatus = process.terminationStatus"))
        #expect(model.contains("try recordImportedTrack(trackID)"))
        #expect(model.contains("try self.database.addTracks([trackID], toPlaylist: playlistID)"))
    }

    @Test func recentDateUpNextAndAutomaticGenreUIAreWired() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let models = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusicCore/Models.swift"))

        #expect(content.contains("case .recentlyAdded: \"clock.fill\""))
        #expect(content.contains("columns.addedDate.visible"))
        #expect(content.contains("header(.dateAdded)"))
        #expect(content.contains("formatAddedDate(track.addedAt)"))
        #expect(models.contains("case upNext = \"次に再生\""))
        #expect(content.contains("UpNextLibraryView(model: model, player: player)"))
        #expect(!content.contains("Text(model.text(\"次に再生\", \"Up Next\")).tag(3)"))
        #expect(model.contains("func autoClassifyGenreIfNeeded(for track: Track)"))
    }

    @Test func metadataEditorSavesBeforeSequentialNavigation() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(
            contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"),
            encoding: .utf8
        )
        let model = try String(
            contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"),
            encoding: .utf8
        )

        #expect(content.contains("saveAndNavigate(by: -1)"))
        #expect(content.contains("saveAndNavigate(by: 1)"))
        #expect(content.contains("guard await saveCurrentTrack() else { return }"))
        #expect(content.contains("Text(positionLabel)"))
        #expect(content.contains("keyboardShortcut(\"]\", modifiers: .command)"))
        #expect(model.contains("func updateMetadataFromEditor"))
    }

    @Test func successfullyEditedTrackSnapshotUsesWrittenMetadata() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "sequential-editor", title: "Before")
        ], sessionID: 1)
        let fetchedTrack = try context.database.track(id: 1)
        let track = try #require(fetchedTrack)
        var edit = TrackMetadataEdit(track: track)
        edit.title = "After"
        edit.artist = "Edited Artist"
        edit.album = "Edited Album"
        edit.discNumber = 2
        edit.trackNumber = 7
        edit.isCompilation = true

        let updated = track.applying(edit)

        #expect(updated.id == track.id)
        #expect(updated.relativePath == track.relativePath)
        #expect(updated.title == "After")
        #expect(updated.artist == "Edited Artist")
        #expect(updated.album == "Edited Album")
        #expect(updated.discNumber == 2)
        #expect(updated.trackNumber == 7)
        #expect(updated.isCompilation)
    }

    @Test func genreSuggestionRegistersWithoutMountedSourceAndOnlyWritesExistingFiles() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(
                identity: "genre-offline", title: "Arrogant Boy",
                artist: "Deep Purple", album: "SPLAT!", filename: "missing.mp3"
            )
        ], sessionID: 1)
        let storedTrackID = try context.database.trackID(forIdentityKey: "genre-offline")
        let trackID = try #require(storedTrackID)

        try context.database.updateTrackGenre(id: trackID, genre: "Hard Rock")
        #expect(try context.database.track(id: trackID)?.genre == "Hard Rock")

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let services = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let content = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        #expect(model.contains("try self.database.updateTrackGenre(id: track.id, genre: canonicalGenre)"))
        #expect(model.contains("await trackFiles.sourceFileIsAvailable(for: track)"))
        #expect(model.contains("await trackFiles.isID3v22Tag(for: track)"))
        #expect(model.contains("purpose: .aiGenre(canonicalGenre)"))
        #expect(model.contains("updateMetadataAfterID3RepairConfirmation"))
        #expect(model.contains("where track.format.lowercased() == \"mp3\" && error.isRepairableID3Damage"))
        #expect(services.contains("func sourceFileIsAvailable(for track: Track) -> Bool"))
        #expect(services.contains("func updateMetadataAfterID3RepairConfirmation"))
        #expect(services.contains("AudioMetadataWriter.isID3v22Tag(at: sourceURL)"))
        #expect(content.contains("ライブラリへ登録"))
        #expect(content.contains("model.metadataRepairDialogTitle"))
    }

    @Test func metadataVariationAnalyzerFindsNormalizationAndLikelyTypo() async throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "a", title: "Song A", artist: "Prince", filename: "a.mp3"),
            context.importedTrack(identity: "b", title: "Song B", artist: "Ｐｒｉｎｃｅ", filename: "b.mp3"),
            context.importedTrack(identity: "c", title: "Song C", artist: "Prinve", filename: "c.mp3")
        ], sessionID: 1)

        #expect(MetadataNormalizer.key("Ｐｒｉｎｃｅ ") == MetadataNormalizer.key("Prince"))
        #expect(MetadataNormalizer.editDistance("prince", "prinve") == 1)
        try await MetadataDiagnosticsAnalyzer(database: context.database).analyze()
        let candidates = try context.database.pageMetadataVariations(limit: 20).candidates
        let artistPage = try context.database.pageMetadataVariations(field: .artist, limit: 20)
        let artistCount = try context.database.metadataVariationCount(field: .artist)

        #expect(candidates.contains(where: { $0.reason == .normalization }))
        #expect(candidates.contains(where: { $0.reason == .likelyTypo && $0.field == .artist }))
        #expect(!artistPage.candidates.isEmpty)
        #expect(artistPage.candidates.allSatisfy { $0.field == .artist })
        #expect(artistPage.totalCount == artistCount)
    }

    @Test func metadataEditRemovesResolvedVariationCandidateAndRefreshesCounts() async throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "canonical", title: "Song A", artist: "Prince", filename: "a.mp3"),
            context.importedTrack(identity: "variant", title: "Song B", artist: "Ｐｒｉｎｃｅ", filename: "b.mp3")
        ], sessionID: 1)
        try await MetadataDiagnosticsAnalyzer(database: context.database).analyze()
        #expect(try context.database.metadataVariationCount(field: .artist) == 1)

        let variantID = try #require(try context.database.trackID(forIdentityKey: "variant"))
        let variant = try #require(try context.database.track(id: variantID))
        var edit = TrackMetadataEdit(track: variant)
        edit.artist = "Prince"
        try context.database.updateTrackMetadata(
            id: variant.id, edit: edit, fileSize: variant.fileSize, modifiedAt: .now
        )

        #expect(try context.database.metadataVariationCount(field: .artist) == 0)
        #expect(try context.database.pageMetadataVariations(field: .artist).candidates.isEmpty)
    }

    @Test func variationReturnUsesANeighborWhenTheEditedCandidateDisappears() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(model.contains("let variationScrollFallbackIDs: [Int64]"))
        #expect(model.contains("func resolvedVariationScrollPositionForRestoration() -> Int64?"))
        #expect(content.contains("model.resolvedVariationScrollPositionForRestoration()"))
    }

    @Test func inspectorDividerStaysDraggableOverWideAlbumTrackTables() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(content.contains(".frame(width: contentWidth)"))
        #expect(content.contains(".clipped()"))
        #expect(content.contains(".highPriorityGesture("))
        #expect(content.contains(".zIndex(10)"))
    }

    @Test func variationCandidatesCanBeFilteredByTitleAlbumOrArtist() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("Picker(model.text(\"表示対象\", \"Show\")"))
        #expect(content.contains("Text(model.text(\"すべて\", \"All\")).tag(MetadataField?.none)"))
        #expect(content.contains("Text(model.text(\"曲名\", \"Title\")).tag(MetadataField?.some(.title))"))
        #expect(content.contains("Text(model.text(\"アルバム名\", \"Album\")).tag(MetadataField?.some(.album))"))
        #expect(content.contains("Text(model.text(\"アーティスト名\", \"Artist\")).tag(MetadataField?.some(.artist))"))
        #expect(model.contains("@Published var variationFieldFilter: MetadataField?"))
        #expect(model.contains("func setVariationFieldFilter(_ field: MetadataField?)"))
        #expect(model.contains("pageMetadataVariations("))
        #expect(model.contains("field: requestedVariationFieldFilter"))
    }

    @Test func urlAndMojibakeDiagnosticsExposeMetadataFieldTabs() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("[.urlInMP3Metadata, .suspectedMojibake].contains(model.diagnosticKind)"))
        #expect(content.contains("get: { model.metadataIssueFieldFilter }"))
        #expect(content.contains("set: { model.setMetadataIssueFieldFilter($0) }"))
        #expect(model.contains("@Published var metadataIssueFieldFilter: MetadataField?"))
        #expect(model.contains("func setMetadataIssueFieldFilter(_ field: MetadataField?)"))
        #expect(model.contains("let requestedFieldFilter = [.urlInMP3Metadata, .suspectedMojibake]"))
        #expect(model.contains("field: requestedFieldFilter"))
        #expect(model.contains("if requestedFieldFilter == nil"))
    }

    @Test func urlPatternDetectionIdentifiesTargetFields() throws {
        let sampleTrack = Track(
            id: 10,
            rootID: 1,
            relativePath: "test/01.mp3",
            filename: "01.mp3",
            title: "Song Title",
            artist: "Artist Name",
            album: "Album https://promo.example.com",
            genre: "Rock",
            fileSize: 1024,
            modifiedAt: Date(),
            format: "mp3",
            comment: "Downloaded from www.freemusic.org"
        )
        let locations = sampleTrack.urlMatchLocations(isJapanese: true)
        let fieldNames = Set(locations.map(\.fieldName))
        #expect(fieldNames.contains("アルバム"))
        #expect(fieldNames.contains("コメント"))
        #expect(!fieldNames.contains("曲名"))
        #expect(!fieldNames.contains("アーティスト"))
    }

    @Test func failedTransactionRollsBack() throws {
        let context = try TestContext()
        #expect(try context.database.rollbackProbeForTesting())
        #expect(try context.database.trackCount() == 0)
    }

    @Test func unavailableTracksAreMarkedWithoutDeletion() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "missing", title: "Missing", rootID: 7)],
            sessionID: 1
        )
        let marked = try context.database.markMissingTracks(rootID: 7, sessionID: 2)

        #expect(marked == 1)
        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.track(id: 1)?.isAvailable == false)
    }

    @Test func aSingleMissingSourceCanBeMarkedUnavailableWithoutDeletingIt() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "missing-file", title: "Missing File", rootID: 7)],
            sessionID: 1
        )

        try context.database.setTrackAvailability(id: 1, isAvailable: false)

        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.track(id: 1)?.isAvailable == false)
    }

    @Test func disconnectedOrMissingTracksAreWarnedBeforePlayback() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(model.contains("func isTrackPlayable(_ track: Track) -> Bool"))
        #expect(model.contains("unavailableRootIDs.contains(track.rootID)"))
        #expect(model.contains("missingVisibleTrackIDs.contains(track.id)"))
        #expect(model.contains("await refreshVisibleTrackAvailability()"))
        #expect(model.contains("let visibleTracks = tracks"))
        #expect(content.contains("let isPlayable = model.isTrackPlayable(track)"))
        #expect(content.contains("!player.unavailableTrackIDs.contains(track.id) || model.isCached(track)"))
        #expect(content.contains("externaldrive.badge.exclamationmark"))
        #expect(content.contains("foregroundStyle(Color.orange)"))
        #expect(playback.contains("database.setTrackAvailability(id: track.id, isAvailable: false)"))
        #expect(playback.contains("let sourceDisappeared = resolvedSourceURL.map"))
        #expect(playback.contains("元ファイルが見つからず、ローカルキャッシュもありません"))
    }

    @Test func interruptedSessionIsResumable() throws {
        let context = try TestContext()
        let rootID = try context.database.addScanRoot(
            displayName: "Test", bookmark: Data(), volumeUUID: "test-volume", path: context.directory.path
        )
        let sessionID = try context.database.createScanSession(rootID: rootID)
        try context.database.updateScanSession(
            id: sessionID, state: .paused, cursor: "folder/track-050.mp3",
            discovered: 50, processed: 50, changed: 50, skipped: 0, errors: 0
        )

        let resumable = try context.database.resumableSession(rootID: rootID)
        #expect(resumable?.id == sessionID)
        #expect(resumable?.cursor == "folder/track-050.mp3")
    }
}

private struct TestContext {
    let directory: URL
    let database: LibraryDatabase

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        database = try LibraryDatabase(url: directory.appending(path: "test.sqlite"))
    }

    func importedTrack(
        identity: String,
        title: String,
        artist: String = "Artist",
        album: String = "Album",
        albumArtist: String = "",
        genre: String = "",
        year: String = "",
        isCompilation: Bool = false,
        filename: String = "track.mp3",
        format: String = "mp3",
        rootID: Int64 = 1,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        hasArtwork: Bool = false,
        addedAt: Date = Date()
    ) -> TrackImport {
        TrackImport(
            identityKey: identity,
            fileResourceID: identity,
            track: Track(
                rootID: rootID,
                relativePath: "Folder/\(filename)",
                filename: filename,
                title: title,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                genre: genre,
                year: year,
                isCompilation: isCompilation,
                discNumber: discNumber,
                trackNumber: trackNumber,
                fileSize: 1_024,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                format: format,
                hasArtwork: hasArtwork,
                addedAt: addedAt
            )
        )
    }

    @Test func searchSupportsAndOrNotPhraseAndRegex() throws {
        let context = try TestContext()
        let t1 = context.importedTrack(identity: "1", title: "A Cold Kiss", artist: "Darkest Hour", album: "So Sedated, So Secure", filename: "01.mp3")
        let t2 = context.importedTrack(identity: "2", title: "A Kiss to Remember", artist: "My Dying Bride", album: "Like Gods of the Sun", filename: "02.mp3")
        let t3 = context.importedTrack(identity: "3", title: "Kiss Me Kiss Me", artist: "The Cure", album: "Kiss Me, Kiss Me, Kiss Me", filename: "03.mp3")
        let t4 = context.importedTrack(identity: "4", title: "Love Song", artist: "The Cure", album: "Disintegration", filename: "04.mp3")
        _ = try context.database.upsertTracks([t1, t2, t3, t4], sessionID: 1)

        // 1. AND search: "kiss" AND "cure"
        let andRes = try context.database.pageTracks(query: "kiss cure")
        #expect(andRes.totalCount == 1)
        #expect(andRes.tracks.first?.title == "Kiss Me Kiss Me")

        // 2. OR search: "remember" OR "disintegration"
        let orRes = try context.database.pageTracks(query: "remember OR disintegration")
        #expect(orRes.totalCount == 2)

        // 3. NOT / exclude search: "kiss -cure"
        let notRes = try context.database.pageTracks(query: "kiss -cure")
        #expect(notRes.totalCount == 2)
        #expect(!notRes.tracks.contains { $0.artist == "The Cure" })

        // 4. Exact phrase search: "kiss me"
        let phraseRes = try context.database.pageTracks(query: "\"kiss me\"")
        #expect(phraseRes.totalCount == 1)
        #expect(phraseRes.tracks.first?.artist == "The Cure")

        // 5. Regex search: /^A.*Kiss/
        let regexRes = try context.database.pageTracks(query: "/^A.*Kiss/")
        #expect(regexRes.totalCount == 2)
        #expect(regexRes.tracks.contains { $0.title == "A Cold Kiss" })
        #expect(regexRes.tracks.contains { $0.title == "A Kiss to Remember" })
    }

    @Test func cachedTracksInPlaylistsAndFavoritesAreProtectedFromEviction() throws {
        let context = try TestContext()
        let t1 = context.importedTrack(identity: "1", title: "Favorite Song", artist: "Artist A", album: "Album A", filename: "01.mp3")
        let t2 = context.importedTrack(identity: "2", title: "Playlist Song", artist: "Artist B", album: "Album B", filename: "02.mp3")
        let t3 = context.importedTrack(identity: "3", title: "Normal Cached 1", artist: "Artist C", album: "Album C", filename: "03.mp3")
        let t4 = context.importedTrack(identity: "4", title: "Normal Cached 2", artist: "Artist D", album: "Album D", filename: "04.mp3")
        _ = try context.database.upsertTracks([t1, t2, t3, t4], sessionID: 1)

        let tracks = try context.database.pageTracks(limit: 10).tracks
        let id1 = tracks[0].id
        let id2 = tracks[1].id
        let id3 = tracks[2].id
        let id4 = tracks[3].id

        // id1をお気に入りに設定
        try context.database.setFavorite(trackID: id1, isFavorite: true)

        // id2をプレイリストに追加
        let playlistID = try context.database.createPlaylist(name: "My Playlist")
        _ = try context.database.addTracks([id2], toPlaylist: playlistID)

        // 4曲すべてキャッシュに登録
        try context.database.recordCachedTrack(trackID: id1, path: "/cache/01.mp3", fileSize: 1000)
        try context.database.recordCachedTrack(trackID: id2, path: "/cache/02.mp3", fileSize: 1000)
        try context.database.recordCachedTrack(trackID: id3, path: "/cache/03.mp3", fileSize: 1000)
        try context.database.recordCachedTrack(trackID: id4, path: "/cache/04.mp3", fileSize: 1000)

        // limit = 2 の場合、保護されていない通常曲 (id3, id4) のうち古いものが削除対象になるが、
        // 保護曲 (id1, id2) は絶対に削除対象にならないことを確認
        let evictions = try context.database.cachedTracksBeyondLimit(2)
        let evictedIDs = evictions.map(\.0)
        #expect(!evictedIDs.contains(id1))
        #expect(!evictedIDs.contains(id2))
    }
}


