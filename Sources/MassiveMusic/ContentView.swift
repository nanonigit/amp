import MassiveMusicCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: Hashable {
    case display
    case storage
    case differences
    case offline
    case ai
}

private enum SummaryPresentation: String {
    case list
    case grid
}

private struct BatchMetadataEditRequest: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

private struct VariationStandardizationRequest: Identifiable {
    let candidate: MetadataVariationCandidate
    let chosenValue: String

    var id: String { "\(candidate.id):\(chosenValue)" }
    var sourceValue: String { chosenValue == candidate.valueA ? candidate.valueB : candidate.valueA }
    var affectedTrackCount: Int { chosenValue == candidate.valueA ? candidate.trackCountB : candidate.trackCountA }
}

private struct SidebarNavigationLabel: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil
    var trailingColor: Color = .secondary
    var iconColor: Color = Color(nsColor: .labelColor)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .foregroundStyle(trailingColor)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func sidebarReorderDraggable(_ payload: String, enabled: Bool) -> some View {
        if enabled {
            draggable(payload)
        } else {
            self
        }
    }
}

private struct CacheTrackLimitControl: View {
    @Binding var value: Int
    let label: String
    let unit: String
    let limits: ClosedRange<Int>
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 48)
                .controlSize(.small)
            Stepper(value: $value, in: limits) { EmptyView() }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, newValue in
            let clamped = min(limits.upperBound, max(limits.lowerBound, newValue))
            if clamped != newValue { value = clamped }
            else { onChange() }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    @Binding var isMiniPlayer: Bool
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .display
    @State private var showInspector = true
    @State private var browserURL: URL?
    @State private var trackBeingEdited: Track?
    @State private var trackPendingDeletion: Track?
    @State private var tracksPendingDeletion: [Track]? = nil
    @State private var batchMetadataEditRequest: BatchMetadataEditRequest?
    @State private var variationStandardizationRequest: VariationStandardizationRequest?
    @State private var selectionAnchorID: Int64?
    @State private var sidebarDropTarget: LibrarySection?
    @State private var isReorderingLibrary = false
    @State private var isReorderingPlaylists = false
    @State private var playlistDropTargetID: Int64?
    @State private var editingPlaylistID: Int64?
    @State private var playlistNameDraft = ""
    @State private var artistScrollPosition: String?
    @State private var artistReturnScrollPosition: String?
    @State private var showDeleteUnrepairableAlert = false
    @FocusState private var isTrackTableFocused: Bool
    @FocusState private var isLibrarySearchFocused: Bool
    @FocusState private var focusedPlaylistEditorID: Int64?
    @AppStorage("inspector.width") private var inspectorWidth = 310.0
    @AppStorage("columns.title.width") private var titleColumnWidth = 150.0
    @AppStorage("columns.artist.width") private var artistColumnWidth = 150.0
    @AppStorage("columns.album.width") private var albumColumnWidth = 180.0
    @AppStorage("columns.genre.width") private var genreColumnWidth = 110.0
    @AppStorage("columns.year.width") private var yearColumnWidth = 85.0
    @AppStorage("columns.discNumber.width") private var discNumberColumnWidth = 82.0
    @AppStorage("columns.trackNumber.width") private var trackNumberColumnWidth = 90.0
    @AppStorage("columns.duration.width") private var durationColumnWidth = 65.0
    @AppStorage("columns.addedDate.width") private var addedDateColumnWidth = 125.0
    @AppStorage("columns.order") private var trackColumnOrderStorage = ""
    @AppStorage("columns.title.visible") private var isTitleColumnVisible = true
    @AppStorage("columns.artist.visible") private var isArtistColumnVisible = true
    @AppStorage("columns.album.visible") private var isAlbumColumnVisible = true
    @AppStorage("columns.genre.visible") private var isGenreColumnVisible = true
    @AppStorage("columns.year.visible") private var isYearColumnVisible = true
    @AppStorage("columns.discNumber.visible") private var isDiscNumberColumnVisible = true
    @AppStorage("columns.trackNumber.visible") private var isTrackNumberColumnVisible = true
    @AppStorage("columns.duration.visible") private var isDurationColumnVisible = true
    @AppStorage("columns.format.visible") private var isFormatColumnVisible = true
    @AppStorage("columns.addedDate.visible") private var isAddedDateColumnVisible = true
    @AppStorage("columns.albumView.artist.visible") private var isAlbumViewArtistVisible = true
    @AppStorage("columns.albumView.year.visible") private var isAlbumViewYearVisible = true
    @AppStorage("columns.albumView.songs.visible") private var isAlbumViewSongsVisible = true
    @AppStorage("columns.artistView.albums.visible") private var isArtistViewAlbumsVisible = true
    @AppStorage("columns.artistView.songs.visible") private var isArtistViewSongsVisible = true
    @AppStorage("columns.artistView.genre.visible") private var isArtistViewGenreVisible = true
    @AppStorage("columns.albumView.album.width") private var albumViewAlbumWidth = 480.0
    @AppStorage("columns.albumView.artist.width") private var albumViewArtistWidth = 260.0
    @AppStorage("columns.albumView.year.width") private var albumViewYearWidth = 100.0
    @AppStorage("columns.albumView.songs.width") private var albumViewSongsWidth = 80.0
    @AppStorage("columns.artistView.artist.width") private var artistViewArtistWidth = 480.0
    @AppStorage("columns.artistView.genre.width") private var artistViewGenreWidth = 180.0
    @AppStorage("columns.artistView.albums.width") private var artistViewAlbumsWidth = 100.0
    @AppStorage("columns.artistView.songs.width") private var artistViewSongsWidth = 100.0
    @AppStorage("columns.artistView.order.v1") private var artistColumnOrderStorage = ""
    @AppStorage("columns.albumView.order.v1") private var albumColumnOrderStorage = ""
    @AppStorage("albums.presentation") private var albumPresentation = SummaryPresentation.list.rawValue
    @AppStorage("artists.presentation") private var artistPresentation = SummaryPresentation.list.rawValue

    var body: some View {
        let isDark = model.appearance.isDark
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
                .background(model.appearance.palette.sidebar)
                .environment(\.colorScheme, isDark ? .dark : .light)
        } detail: {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let currentInspectorWidth = showInspector ? inspectorWidth : 0
                let dividerWidth = showInspector ? 14.0 : 0.0
                let contentWidth = max(300, availableWidth - currentInspectorWidth - dividerWidth)

                HStack(spacing: 0) {
                    libraryContent
                        .frame(width: contentWidth)
                        .clipped()
                    if showInspector {
                        InspectorDivider(
                            inspectorWidth: $inspectorWidth,
                            helpText: model.text("ドラッグで幅を変更・ダブルクリックで元に戻す", "Drag to resize; double-click to reset"),
                            accessibilityText: model.text("再生情報パネルの幅を変更", "Resize Now Playing panel")
                        )
                        .frame(width: 14)
                        .zIndex(10)
                        
                        NowPlayingInspector(
                            model: model,
                            player: player,
                            isMiniPlayer: $isMiniPlayer,
                            browserURL: $browserURL,
                            openAISettings: {
                                settingsTab = .ai
                                model.changeSection(.settings)
                            }
                        )
                        .frame(width: inspectorWidth)
                        .clipped()
                        .transaction { $0.animation = nil }
                    }
                }
                .frame(width: availableWidth, height: geometry.size.height, alignment: .leading)
                .padding(.top, -max(0, geometry.safeAreaInsets.top - 16))
                .overlay(alignment: .topTrailing) {
                    inspectorToggleButton
                        .padding(.top, showInspector ? 66 : 12)
                        .padding(.trailing, 14)
                }
            }
            .environment(\.colorScheme, isDark ? .dark : .light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.appearance.palette.canvas)
        .background(WindowAppearanceSynchronizer(mode: model.appearance).frame(width: 0, height: 0))
        .tint(model.appearance.palette.accent)
        .toolbar(removing: .sidebarToggle)
        .environment(\.colorScheme, model.appearance.isDark ? .dark : .light)
        .preferredColorScheme(model.appearance.isDark ? .dark : .light)
        .onChange(of: player.currentTrack) { _, track in model.enrich(track) }
        .onChange(of: model.language) { _, _ in
            model.savePresentationSettings()
            model.enrich(player.currentTrack)
        }
        .onChange(of: model.appearance) { _, _ in model.savePresentationSettings() }
        .onChange(of: model.section) { oldSection, newSection in
            if oldSection != newSection {
                artistScrollPosition = nil
                artistReturnScrollPosition = nil
            }
        }
        .onChange(of: model.pagePresentationID) { _, _ in
            if model.section == .artists,
               model.selectedArtist == nil,
               artistReturnScrollPosition == nil {
                artistScrollPosition = nil
            }
        }
        .onChange(of: model.isLoading) { _, _ in
            restorePendingArtistScrollPositionIfNeeded()
            restorePendingBrowseScrollPositionIfNeeded()
        }
        .onChange(of: browserURL) { _, url in
            if url != nil {
                showInspector = true
                inspectorWidth = max(inspectorWidth, 480)
            }
        }
        .sheet(item: $trackBeingEdited) { track in
            TrackMetadataEditor(model: model, track: track, navigationTracks: model.tracks)
        }
        .sheet(item: $batchMetadataEditRequest, onDismiss: model.resetBatchMetadataProgress) { request in
            BatchTrackMetadataEditor(model: model, tracks: request.tracks)
        }
        .sheet(item: $model.shazamRecognitionResult) { result in
            ShazamResultSheet(model: model, result: result)
        }
        .confirmationDialog(
            model.text("表記を統一", "Standardize Spelling"),
            isPresented: Binding(
                get: { variationStandardizationRequest != nil },
                set: { if !$0 { variationStandardizationRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let request = variationStandardizationRequest {
                let candidate = request.candidate
                let chosenValue = request.chosenValue
                Button(model.text(
                    "\(request.affectedTrackCount.formatted())曲を「\(chosenValue)」へ統一",
                    "Standardize \(request.affectedTrackCount.formatted()) songs as ‘\(chosenValue)’"
                )) {
                    model.standardizeVariation(candidate, choosing: chosenValue)
                    variationStandardizationRequest = nil
                }
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) {
                variationStandardizationRequest = nil
            }
        } message: {
            if let request = variationStandardizationRequest {
                Text(model.text(
                    "\(metadataFieldTitle(request.candidate.field))が「\(request.sourceValue)」の\(request.affectedTrackCount.formatted())曲を「\(request.chosenValue)」へ変更します。音源タグにも安全な既存の書込処理で反映します。",
                    "Change the \(metadataFieldTitle(request.candidate.field).lowercased()) from ‘\(request.sourceValue)’ to ‘\(request.chosenValue)’ for \(request.affectedTrackCount.formatted()) songs. The existing safe writer will update the audio tags too."
                ))
            }
        }
        .confirmationDialog(
            model.text("曲を削除", "Delete Song"),
            isPresented: Binding(
                get: { trackPendingDeletion != nil || tracksPendingDeletion != nil },
                set: { if !$0 { trackPendingDeletion = nil; tracksPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tracks = tracksPendingDeletion {
                Button(model.text("ライブラリからのみ削除", "Remove from Library Only"), role: .destructive) {
                    model.removeTracksFromLibrary(tracks)
                    tracksPendingDeletion = nil
                }
                Button(model.text("実ファイルをゴミ箱へ移動", "Move Source Files to Trash"), role: .destructive) {
                    model.moveFilesToTrash(tracks)
                    tracksPendingDeletion = nil
                }
            } else if let track = trackPendingDeletion {
                Button(model.text("ライブラリからのみ削除", "Remove from Library Only"), role: .destructive) {
                    model.removeFromLibrary(track)
                    trackPendingDeletion = nil
                }
                Button(model.text("実ファイルをゴミ箱へ移動", "Move Source File to Trash"), role: .destructive) {
                    model.moveFileToTrash(track)
                    trackPendingDeletion = nil
                }
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) { trackPendingDeletion = nil; tracksPendingDeletion = nil }
        } message: {
            if let tracks = tracksPendingDeletion {
                Text(model.text(
                    "選択した\(tracks.count)曲をライブラリから削除しますか？\n「実ファイルをゴミ箱へ移動」を選ぶと、パソコンからファイルが削除されます。",
                    "Are you sure you want to delete the \(tracks.count) selected songs from the library?\nChoosing 'Move Source Files to Trash' will delete the files from your computer."
                ))
            } else if let track = trackPendingDeletion {
                Text(model.text(
                    "「\(track.title)」をライブラリから削除しますか？\n「実ファイルをゴミ箱へ移動」を選ぶと、パソコンからファイルが削除されます。",
                    "Are you sure you want to delete '\(track.title)' from the library?\nChoosing 'Move Source File to Trash' will delete the file from your computer."
                ))
            }
        }
        .confirmationDialog(
            model.metadataRepairDialogTitle,
            isPresented: Binding(
                get: { model.metadataRepairRequest != nil },
                set: { if !$0 { model.cancelMetadataRepair() } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.metadataRepairConfirmationTitle) {
                model.confirmMetadataRepair()
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) {
                model.cancelMetadataRepair()
            }
        } message: {
            Text(model.metadataRepairDialogMessage)
        }
        .alert(model.text("エラー", "Error"), isPresented: Binding(
            get: { model.errorMessage != nil || player.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                    player.dismissError()
                }
            }
        )) {
            Button("OK") {
                model.dismissError()
                player.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? player.errorMessage ?? "")
        }
    }

    private var inspectorToggleButton: some View {
        Button { showInspector.toggle() } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .help(showInspector
            ? model.text("右ペインを閉じる", "Hide Right Pane")
            : model.text("右ペインを表示", "Show Right Pane"))
        .accessibilityLabel(showInspector
            ? model.text("右ペインを閉じる", "Hide Right Pane")
            : model.text("右ペインを表示", "Show Right Pane"))
    }

    private var sidebar: some View {
        List {
            Section {
                ForEach(model.visibleLibrarySections) { section in
                    HStack(spacing: 4) {
                        Button {
                            model.changeSection(section)
                        } label: {
                            SidebarNavigationLabel(
                                title: model.sectionTitle(section),
                                systemImage: icon(for: section),
                                trailingText: sidebarCount(for: section)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(isReorderingLibrary)

                        if isReorderingLibrary {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .help(model.text("ドラッグして並べ替え", "Drag to reorder"))
                            Button {
                                model.moveLibrarySection(section, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(section == model.visibleLibrarySections.first)
                            .help(model.text("上へ移動", "Move Up"))
                            Button {
                                model.moveLibrarySection(section, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(section == model.visibleLibrarySections.last)
                            .help(model.text("下へ移動", "Move Down"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.section == section ? Color.accentColor : Color.primary)
                    .background {
                        if sidebarDropTarget == section {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.18))
                        }
                    }
                    .sidebarReorderDraggable(section.rawValue, enabled: isReorderingLibrary)
                    .dropDestination(for: String.self) { values, _ in
                        guard let rawValue = values.first,
                              let source = LibrarySection(rawValue: rawValue) else { return false }
                        model.moveLibrarySection(source, before: section)
                        return true
                    } isTargeted: { targeted in
                        sidebarDropTarget = targeted ? section : nil
                    }
                    .help(model.text("ドラッグして並べ替え", "Drag to reorder"))
                }
            } header: {
                HStack {
                    Text(model.text("ライブラリ", "Library"))
                    Spacer()
                    Menu {
                        Section(model.text("表示項目", "Visible Items")) {
                            ForEach(model.orderedLibrarySections) { section in
                                Button { model.toggleLibrarySectionVisibility(section) } label: {
                                    Label(
                                        model.sectionTitle(section),
                                        systemImage: model.hiddenLibrarySections.contains(section)
                                            ? "circle" : "checkmark.circle.fill"
                                    )
                                }
                            }
                            Divider()
                            Button(action: model.showAllLibrarySections) {
                                Label(model.text("すべて表示", "Show All"), systemImage: "eye")
                            }
                        }
                        Divider()
                        Button { isReorderingLibrary.toggle() } label: {
                            Label(
                                isReorderingLibrary ? model.text("並び替えを完了", "Finish Reordering") : model.text("並び替える", "Reorder Items"),
                                systemImage: isReorderingLibrary ? "checkmark" : "arrow.up.arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(model.text("ライブラリ項目を整理", "Organize Library items"))
                }
            }
            Section {
                ForEach(model.playlists) { playlist in
                    HStack(spacing: 4) {
                        if editingPlaylistID == playlist.id {
                            HStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .frame(width: 16)
                                TextField(model.text("プレイリスト名", "Playlist Name"), text: $playlistNameDraft)
                                    .textFieldStyle(.plain)
                                    .focused($focusedPlaylistEditorID, equals: playlist.id)
                                    .onSubmit { commitPlaylistRename(playlist.id) }
                                    .onExitCommand(perform: cancelPlaylistRename)
                                    .onChange(of: focusedPlaylistEditorID) { oldValue, newValue in
                                        if oldValue == playlist.id, newValue != playlist.id {
                                            commitPlaylistRename(playlist.id)
                                        }
                                    }
                                Spacer(minLength: 8)
                                Text(playlist.itemCount.formatted())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .fixedSize()
                            }
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Button {
                                guard (NSApp.currentEvent?.clickCount ?? 1) < 2 else { return }
                                model.selectPlaylist(playlist.id)
                            } label: {
                                SidebarNavigationLabel(
                                    title: playlist.name, systemImage: "music.note.list",
                                    trailingText: playlist.itemCount.formatted()
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .disabled(isReorderingPlaylists)
                            .onTapGesture(count: 2) { beginEditingPlaylist(playlist) }
                        }

                        if isReorderingPlaylists {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            Button {
                                model.movePlaylist(playlist.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(playlist.id == model.playlists.first?.id)
                            .help(model.text("上へ移動", "Move Up"))
                            Button {
                                model.movePlaylist(playlist.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(playlist.id == model.playlists.last?.id)
                            .help(model.text("下へ移動", "Move Down"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.selectedPlaylistID == playlist.id ? Color.accentColor : Color.primary)
                    .background {
                        if playlistDropTargetID == playlist.id {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.18))
                        }
                    }
                    .contextMenu {
                        Button(model.text("名前を変更…", "Rename…")) {
                            beginEditingPlaylist(playlist)
                        }
                        Button(model.text("削除", "Delete"), role: .destructive) {
                            model.deletePlaylist(id: playlist.id)
                        }
                    }
                    .sidebarReorderDraggable("playlist-order:\(playlist.id)", enabled: isReorderingPlaylists)
                    .dropDestination(for: String.self) { values, _ in
                        if isReorderingPlaylists,
                           let value = values.first,
                           value.hasPrefix("playlist-order:"),
                           let sourceID = Int64(value.dropFirst("playlist-order:".count)) {
                            model.movePlaylist(sourceID, before: playlist.id)
                            return true
                        }
                        let trackIDs = values.flatMap(parseTrackDragPayload)
                        guard !trackIDs.isEmpty else { return false }
                        model.addTrackIDsToPlaylist(trackIDs, playlistID: playlist.id)
                        return true
                    } isTargeted: { targeted in
                        playlistDropTargetID = targeted && isReorderingPlaylists ? playlist.id : nil
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !urls.isEmpty else { return false }
                        model.importURLs(urls, toPlaylist: playlist.id)
                        return true
                    }
                }
            } header: {
                HStack {
                    Text(model.text("プレイリスト", "Playlists"))
                    Spacer()
                    Button(action: model.createPlaylist) { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .help(model.text("プレイリストを作成", "Create Playlist"))
                    Menu {
                        Button(model.text("M3U/M3U8を読み込む", "Import M3U/M3U8"), action: model.importPlaylist)
                        Button(model.text("選択中をM3U8へ書き出す", "Export Selected as M3U8"), action: model.exportSelectedPlaylist)
                            .disabled(model.selectedPlaylistID == nil)
                        Divider()
                        Button { isReorderingPlaylists.toggle() } label: {
                            Label(
                                isReorderingPlaylists ? model.text("並び替えを完了", "Finish Reordering") : model.text("並び替える", "Reorder Items"),
                                systemImage: isReorderingPlaylists ? "checkmark" : "arrow.up.arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(model.text("プレイリストを整理", "Organize Playlists"))
                }
            }
            Section {
                Button {
                    settingsTab = .display
                    model.changeSection(.settings)
                } label: {
                    SidebarNavigationLabel(
                        title: model.sectionTitle(.settings),
                        systemImage: icon(for: .settings)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.section == .settings ? Color.accentColor : Color.primary)

                Button { model.changeSection(.diagnostics) } label: {
                    SidebarNavigationLabel(title: model.sectionTitle(.diagnostics), systemImage: icon(for: .diagnostics))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.section == .diagnostics ? Color.accentColor : Color.primary)

                Button { model.changeSection(.activityLog) } label: {
                    SidebarNavigationLabel(title: model.sectionTitle(.activityLog), systemImage: icon(for: .activityLog))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.section == .activityLog ? Color.accentColor : Color.primary)
            } header: {
                Text(model.text("ツール", "Tools"))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarBackgroundStatus
        }
        .scrollContentBackground(.hidden)
        .background(model.appearance.palette.sidebar)
    }

    @ViewBuilder
    private var sidebarBackgroundStatus: some View {
        if model.driveMessage != nil || model.isBulkAutoFilling || model.isID3Migrating || model.isScanningAutomaticGenres || model.isScanningAutomaticAlbumYears || model.isTrimmingWhitespace || model.isNormalizingGenres {
            VStack(spacing: 0) {
                if let message = model.driveMessage {
                    Label(message, systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.isBulkAutoFilling {
                    sidebarProgressStatus(model.bulkAutoFillProgress)
                }
                if model.isID3Migrating {
                    sidebarProgressStatus(model.id3MigrationProgress)
                }
                if model.isTrimmingWhitespace {
                    sidebarProgressStatus(model.whitespaceTrimmingProgress)
                }
                if model.isNormalizingGenres {
                    sidebarProgressStatus(model.genreNormalizationProgress)
                }
                if model.isScanningAutomaticGenres {
                    sidebarAutomaticGenreProgress
                }
                if model.isScanningAutomaticAlbumYears {
                    sidebarAutomaticAlbumYearProgress
                }
            }
            .font(.caption)
            .background(.bar)
        }
    }

    private func sidebarProgressStatus(_ message: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text(message)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebarAutomaticGenreProgress: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(model.automaticGenreRetrySecondsRemaining > 0
                    ? model.text(
                        "外部AIへ\(model.automaticGenreRetrySecondsRemaining)秒後に再接続",
                        "Reconnecting to external AI in \(model.automaticGenreRetrySecondsRemaining)s"
                    )
                    : model.text("ジャンル判定中", "Classifying genre"))
                    .fontWeight(.semibold)
                    .foregroundStyle(model.automaticGenreRetrySecondsRemaining > 0 ? Color.orange : Color.primary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            Text(model.automaticGenreScanCurrentTrack)
                .lineLimit(1)
                .truncationMode(.tail)
            if !model.automaticGenreScanCurrentSource.isEmpty {
                Text(model.text("判定元: \(model.automaticGenreScanCurrentSource)", "Source: \(model.automaticGenreScanCurrentSource)"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(model.text(
                "確認 \(model.automaticGenreScanProcessedCount.formatted())/\(model.automaticGenreScanTotalCount.formatted())・登録 \(model.automaticGenreRegisteredCount.formatted())・80%未満 \(model.automaticGenreScanBelowThresholdCount.formatted())・失敗 \(model.automaticGenreScanFailedCount.formatted())",
                "Checked \(model.automaticGenreScanProcessedCount.formatted())/\(model.automaticGenreScanTotalCount.formatted()) · Registered \(model.automaticGenreRegisteredCount.formatted()) · Below 80% \(model.automaticGenreScanBelowThresholdCount.formatted()) · Failed \(model.automaticGenreScanFailedCount.formatted())"
            ))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebarAutomaticAlbumYearProgress: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(model.text("リリース年を自動取得中", "Fetching release years"))
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            let current = model.automaticAlbumYearProcessedCount
            let total = model.automaticAlbumYearTotalCount
            let percent = total > 0 ? Int((Double(current) / Double(total) * 100).rounded()) : 0
            Text("\(current.formatted()) / \(total.formatted()) 曲 (\(percent)%)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if model.section == .settings {
                        LibrarySettingsView(model: model, selectedTab: $settingsTab)
                    } else if model.section == .activityLog {
                        activityLogView
                    } else if model.section == .upNext {
                        UpNextLibraryView(model: model, player: player)
                    } else if model.section == .diagnostics {
                        metadataDiagnosticsView
                    } else if model.selectedAlbum != nil || model.selectedArtist?.name.isEmpty == true {
                        trackTable
                    } else if model.selectedArtist != nil || model.section == .albums {
                        albumSummaryList
                    } else if model.selectedGenre != nil {
                        genreDetailContent
                    } else if model.section == .artists {
                        artistSummaryList
                    } else if model.section == .genres || model.section == .folders {
                        facetList
                    } else {
                        trackTable
                    }
                }
                .id(model.pagePresentationID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if model.supportsAlphabetIndex {
                    Divider()
                    alphabetIndexRail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if model.section != .upNext && model.section != .settings {
                Divider()
                pageControls
            }
            if [.running, .paused].contains(model.scanProgress.state) { scanStatus }
            if model.importProgress.state != .idle { importStatus }
        }
        .scrollContentBackground(.hidden)
        .background(model.appearance.palette.library)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            let activePlaylistID = model.section == .playlists ? model.selectedPlaylistID : nil
            model.importURLs(urls, toPlaylist: activePlaylistID)
            return true
        }
    }

    private var alphabetIndexRail: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 3) {
                Text(model.text("索引", "Index"))
                    .font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(alphabetIndexTokens, id: \.self) { token in
                    Button(token) {
                        model.selectedIndexToken = token
                        model.jumpToIndex(token)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .frame(width: 25, height: 23)
                    .background(model.selectedIndexToken == token ? Color.accentColor : Color.secondary.opacity(0.09), in: Capsule())
                    .foregroundStyle(model.selectedIndexToken == token ? Color.white : Color.primary)
                    .help(model.text("「\(token)」から始まる位置へ移動", "Jump to entries beginning at \(token)"))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 7)
        }
        .frame(width: 39)
        .background(.bar)
    }

    private var alphabetIndexTokens: [String] {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
            + ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ",
               "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と",
               "な", "に", "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ",
               "ま", "み", "む", "め", "も", "や", "ゆ", "よ", "ら", "り",
               "る", "れ", "ろ", "わ", "を", "ん"]
            + (0...9).map(String.init)
    }

    private var header: some View {
        HStack(spacing: 12) {
            detailHeaderArtwork
            headerIdentity
            Spacer(minLength: 4)
            if model.section != .upNext && model.section != .settings {
                ViewThatFits(in: .horizontal) {
                    headerControls
                    compactHeaderControls
                }
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var detailHeaderArtwork: some View {
        if let album = model.selectedAlbum {
            let artworkURL = model.albumArtworkURLs[album.id] ?? (player.currentTrack?.album == album.name ? model.enrichedInfo?.artworkURL : nil)
            PlayerArtwork(artworkURL: artworkURL, size: 68, cornerRadius: 8, placeholderPointSize: 22)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .task { model.loadArtwork(for: album) }
        } else if let artist = model.selectedArtist, !artist.name.isEmpty {
            PlayerArtwork(artworkURL: model.artistImageURLs[artist.name], size: 68, cornerRadius: 34, placeholderPointSize: 22)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .task { model.loadImage(for: artist) }
        }
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.isInDetail {
                Button(action: closeDetailRestoringScrollPosition) {
                    Label(model.text("戻る", "Back"), systemImage: "chevron.left")
                }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if model.selectedPlaylistID != nil {
                Button {
                    if let playlist = model.playlists.first(where: { $0.id == model.selectedPlaylistID }) {
                        beginEditingPlaylist(playlist)
                    }
                } label: {
                    Text(headerTitle)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.text("クリックしてプレイリスト名を変更", "Click to rename playlist"))
            } else if model.section == .upNext {
                Text(model.text("\(player.queueTotalCount.formatted()) 曲", "\(player.queueTotalCount.formatted()) songs"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let hideTitle = model.section == .favorites && model.selectedAlbum == nil && model.selectedArtist == nil && model.selectedGenre == nil
                if !hideTitle {
                    Text(headerTitle)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if let album = model.selectedAlbum {
                HStack(spacing: 6) {
                    Button { model.openArtist(named: album.artist) } label: {
                        Text(model.displayArtist(album.artist))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.link)
                    if !album.year.isEmpty {
                        Text("• \(album.year)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("• " + model.text("\(model.totalCount.formatted())曲", "\(model.totalCount.formatted()) songs"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    if let summary = model.headerStorageSummary {
                        Text("(\(formattedGigabytes(summary.totalBytes)) GB)")
                            .font(.caption).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else if let artist = model.selectedArtist {
                Text(model.text("\(artist.albumCount.formatted())アルバム・\(artist.trackCount.formatted())曲", "\(artist.albumCount.formatted()) albums · \(artist.trackCount.formatted()) songs"))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.selectedGenre != nil {
                Text(model.text("\(model.genreDetailTitle(model.genreDetailMode))・\(model.totalCount.formatted()) 件", "\(model.genreDetailTitle(model.genreDetailMode)) · \(model.totalCount.formatted()) items"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let genre = model.selectedGenre {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.genreDetailDescription(genre))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let knowledge = model.genreKnowledge(for: genre) {
                            Link(destination: knowledge.sourceURL) {
                                Label(model.text("Wikipedia出典", "Wikipedia Source"), systemImage: "link")
                            }
                            .font(.caption2)
                            .help(knowledge.sourceTitle)
                        }
                    }
                }
            } else if model.section == .settings {
                Text(model.text("表示・保管先・差分・AIおよびメタデータの自動処理を設定します。", "Configure display, storage, diffs, AI, and metadata automation."))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(model.section == .cache
                    ? model.text(
                        "\(model.totalCount.formatted()) 件・合計 \(formattedFileSize(model.cachedStorageBytes))",
                        "\(model.totalCount.formatted()) items · \(formattedFileSize(model.cachedStorageBytes)) total"
                    )
                    : model.text("\(model.totalCount.formatted()) 件", "\(model.totalCount.formatted()) items")
                )
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.section == .cache {
                    Text(model.localCacheDirectoryPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.localCacheDirectoryPath)
                }
            }
            if showsStorageSummary && model.selectedAlbum == nil, let summary = model.headerStorageSummary {
                Text(model.text(
                    "容量: \(formattedGigabytes(summary.totalBytes)) GB",
                    "Size: \(formattedGigabytes(summary.totalBytes)) GB"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                ForEach(summary.absoluteRootPaths, id: \.self) { path in
                    Text(model.text("絶対パス: \(path)", "Absolute path: \(path)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var showsStorageSummary: Bool {
        model.selectedArtist != nil || [.tracks, .albums, .artists].contains(model.section)
    }

    private func formattedGigabytes(_ bytes: Int64) -> String {
        let gigabytes = Double(max(0, bytes)) / 1_000_000_000
        return gigabytes.formatted(.number.precision(.fractionLength(gigabytes >= 100 ? 1 : 2)))
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                if model.section == .cache { cacheHeaderControls }
                nonCacheHeaderControls
            }
            if model.section != .diagnostics {
                LibrarySearchField(model: model, isFocused: $isLibrarySearchFocused)
            }
        }
    }

    private var compactHeaderControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if model.section == .cache { cacheHeaderControls }
                nonCacheHeaderControls
            }
            if model.section != .diagnostics {
                LibrarySearchField(model: model, isFocused: $isLibrarySearchFocused, isFlexible: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cacheHeaderControls: some View {
        HStack(spacing: 8) {
            Button {
                model.cacheEnabled.toggle()
                model.saveCacheSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.cacheEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(model.cacheEnabled ? model.appearance.palette.accent : Color.secondary)
                    Text(model.text("再生時保存", "Auto-Cache"))
                        .font(.caption)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(model.cacheEnabled ? model.appearance.palette.accent.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(model.text("曲を再生した際に自動的にオフラインキャッシュへ保存します", "Automatically save played songs to offline cache"))

            CacheTrackLimitControl(
                value: $model.cacheTrackLimit,
                label: model.text("保持:", "Keep:"),
                unit: model.text("曲", "songs"),
                limits: 0...500,
                onChange: model.saveCacheSettings
            )

            Divider().frame(height: 16)

            // Cloud Sync Menu / Button for iPhone & iPad
            HStack(spacing: 4) {
                if model.isCloudSyncing {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text(model.cloudSyncProgress)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(model.appearance.palette.accent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(model.appearance.palette.accent.opacity(0.12), in: Capsule())
                } else {
                    Button {
                        model.syncCacheToCloud()
                    } label: {
                        Label(
                            model.text("クラウド書き出し", "Cloud Export"),
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(model.text("iPhone/iPadで聴けるようにキャッシュをクラウドストレージへコピーします", "Export cached songs to cloud storage for iPhone/iPad"))

                    Menu {
                        Section(model.text("同期先クラウドストレージ", "Sync Destination")) {
                            ForEach(CloudSyncProvider.allCases) { provider in
                                Button {
                                    model.cloudSyncProvider = provider
                                    model.saveCloudSyncSettings()
                                    if provider == .custom && model.customCloudSyncPath.isEmpty {
                                        model.chooseCustomCloudSyncDirectory()
                                    }
                                } label: {
                                    HStack {
                                        Text(provider.title(isJapanese: model.language == .japanese))
                                        if model.cloudSyncProvider == provider {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        if model.cloudSyncProvider == .custom {
                            Button(model.text("カスタムフォルダを変更…", "Change Custom Folder…")) {
                                model.chooseCustomCloudSyncDirectory()
                            }
                        }

                        Divider()

                        Button(model.text("クラウドフォルダをFinderで開く", "Show Cloud Folder in Finder")) {
                            model.revealCloudSyncDirectory()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }
        }
    }

    private var nonCacheHeaderControls: some View {
        HStack(spacing: 12) {
            if model.selectedGenre != nil, model.selectedAlbum == nil, model.selectedArtist == nil {
                Picker(model.text("表示", "View"), selection: $model.genreDetailMode) {
                    ForEach(GenreDetailMode.allCases) { mode in
                        Text(model.genreDetailTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .onChange(of: model.genreDetailMode) { _, mode in model.changeGenreDetailMode(mode) }
            }

            if showsTrackColumns || [.albums, .artists].contains(model.section) || model.selectedArtist != nil {
                let showsAlbumLayoutPicker = model.selectedAlbum == nil && (model.section == .albums || model.selectedArtist != nil)
                let showsArtistLayoutPicker = model.selectedAlbum == nil && model.selectedArtist == nil && model.section == .artists
                if showsAlbumLayoutPicker || showsArtistLayoutPicker {
                    Picker(model.text("表示方法", "Layout"), selection: showsArtistLayoutPicker ? $artistPresentation : $albumPresentation) {
                        Image(systemName: "list.bullet").tag(SummaryPresentation.list.rawValue)
                        Image(systemName: "square.grid.3x3").tag(SummaryPresentation.grid.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 86)
                    .help(model.text("一覧と画像グリッドを切り替え", "Switch between list and artwork grid"))
                }
                if selectedTracksOnPage.count > 1 && showsTrackColumns {
                    Button { openBatchMetadataEditor() } label: {
                        Label(
                            model.text("\(selectedTracksOnPage.count)曲を一括編集", "Edit \(selectedTracksOnPage.count) Songs"),
                            systemImage: "square.and.pencil"
                        )
                    }
                    .help(model.text("選択した曲の共通情報を一括変更", "Bulk edit shared metadata for selected songs"))
                    Menu {
                        Button(model.text("すべてお気に入りに追加", "Add All to Favorites")) {
                            model.setFavorites(selectedTracksOnPage, isFavorite: true)
                        }
                        Button(model.text("すべてお気に入りから外す", "Remove All from Favorites")) {
                            model.setFavorites(selectedTracksOnPage, isFavorite: false)
                        }
                        Divider()
                        if model.playlists.isEmpty {
                            Button(model.text("新規プレイリストを作成", "Create New Playlist")) {
                                model.createPlaylist()
                            }
                        } else {
                            Menu(model.text("プレイリストに追加", "Add to Playlist")) {
                                ForEach(model.playlists) { playlist in
                                    Button(playlist.name) {
                                        model.addSelectionToPlaylist(playlist.id)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(model.text("一括操作", "Bulk Actions"), systemImage: "checklist")
                    }
                }
                Menu {
                    if (model.section == .albums || model.selectedArtist != nil) && model.selectedAlbum == nil {
                        columnVisibilityButton(model.text("アーティスト", "Artist"), isVisible: $isAlbumViewArtistVisible)
                        columnVisibilityButton(model.text("リリース年", "Release Year"), isVisible: $isAlbumViewYearVisible)
                        columnVisibilityButton(model.text("曲数", "Songs"), isVisible: $isAlbumViewSongsVisible)
                    } else if model.section == .artists && model.selectedArtist == nil {
                        columnVisibilityButton(model.text("ジャンル", "Genre"), isVisible: $isArtistViewGenreVisible)
                        columnVisibilityButton(model.text("アルバム数", "Albums"), isVisible: $isArtistViewAlbumsVisible)
                        columnVisibilityButton(model.text("曲数", "Songs"), isVisible: $isArtistViewSongsVisible)
                    } else {
                        columnVisibilityButton(model.text("タイトル", "Title"), isVisible: $isTitleColumnVisible)
                        columnVisibilityButton(model.text("アーティスト", "Artist"), isVisible: $isArtistColumnVisible)
                        columnVisibilityButton(model.text("アルバム", "Album"), isVisible: $isAlbumColumnVisible)
                        columnVisibilityButton(model.text("ジャンル", "Genre"), isVisible: $isGenreColumnVisible)
                        columnVisibilityButton(model.text("リリース年", "Release Year"), isVisible: $isYearColumnVisible)
                        columnVisibilityButton(model.text("ディスク番号", "Disc Number"), isVisible: $isDiscNumberColumnVisible)
                        columnVisibilityButton(model.text("トラック番号", "Track Number"), isVisible: $isTrackNumberColumnVisible)
                        columnVisibilityButton(model.text("時間", "Duration"), isVisible: $isDurationColumnVisible)
                        columnVisibilityButton(model.text("形式", "Format"), isVisible: $isFormatColumnVisible)
                        columnVisibilityButton(model.text("追加日", "Date Added"), isVisible: $isAddedDateColumnVisible)
                    }
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .help(model.text("表示する列を選択", "Choose visible columns"))
            }
        }
    }

    private var selectedTracksOnPage: [Track] {
        model.tracks.filter { model.selectedTrackIDs.contains($0.id) }
    }

    private var currentSelectionModifiers: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
    }

    private var hasSelectionModifier: Bool {
        let modifiers = currentSelectionModifiers
        return modifiers.contains(.command) || modifiers.contains(.shift)
    }

    private func handleTrackSelection(_ track: Track, at index: Int) {
        let modifiers = currentSelectionModifiers
        if modifiers.contains(.shift),
           let anchorID = selectionAnchorID,
           let anchorIndex = model.tracks.firstIndex(where: { $0.id == anchorID }) {
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            let rangeIDs = Set(range.map { model.tracks[$0].id })
            if modifiers.contains(.command) {
                model.selectedTrackIDs.formUnion(rangeIDs)
            } else {
                model.selectedTrackIDs = rangeIDs
            }
        } else if modifiers.contains(.command) {
            if model.selectedTrackIDs.contains(track.id) {
                model.selectedTrackIDs.remove(track.id)
            } else {
                model.selectedTrackIDs.insert(track.id)
            }
            selectionAnchorID = track.id
        } else {
            model.selectedTrackIDs = [track.id]
            selectionAnchorID = track.id
        }
    }

    private func selectAllVisibleTracks() {
        guard !model.tracks.isEmpty else { return }
        model.selectedTrackIDs = Set(model.tracks.map(\.id))
        selectionAnchorID = model.tracks.last?.id
    }

    private func openBatchMetadataEditor() {
        let selected = selectedTracksOnPage
        guard selected.count > 1 else { return }
        model.resetBatchMetadataProgress()
        batchMetadataEditRequest = BatchMetadataEditRequest(tracks: selected)
    }

    private var defaultTrackColumnOrder: [TrackSort] {
        [.title, .artist, .album, .genre, .year, .discNumber, .trackNumber, .duration, .format, .dateAdded]
    }

    private var orderedTrackColumns: [TrackSort] {
        var seen = Set<String>()
        let stored = trackColumnOrderStorage
            .split(separator: ",")
            .compactMap { TrackSort(rawValue: String($0)) }
            .filter { defaultTrackColumnOrder.contains($0) && seen.insert($0.rawValue).inserted }
        return stored + defaultTrackColumnOrder.filter { !seen.contains($0.rawValue) }
    }

    private var orderedVisibleTrackColumns: [TrackSort] {
        orderedTrackColumns.filter(isTrackColumnVisible)
    }

    private func isTrackColumnVisible(_ column: TrackSort) -> Bool {
        switch column {
        case .title: isTitleColumnVisible
        case .artist: isArtistColumnVisible
        case .album: isAlbumColumnVisible
        case .genre: isGenreColumnVisible
        case .year: isYearColumnVisible
        case .discNumber: isDiscNumberColumnVisible
        case .trackNumber: isTrackNumberColumnVisible
        case .duration: isDurationColumnVisible
        case .format: isFormatColumnVisible
        case .dateAdded: isAddedDateColumnVisible
        case .path: false
        }
    }

    private func moveTrackColumn(_ source: TrackSort, before destination: TrackSort) {
        guard source != destination else { return }
        var order = orderedTrackColumns
        guard let sourceIndex = order.firstIndex(of: source) else { return }
        order.remove(at: sourceIndex)
        guard let destinationIndex = order.firstIndex(of: destination) else { return }
        order.insert(source, at: destinationIndex)
        trackColumnOrderStorage = order.map(\.rawValue).joined(separator: ",")
    }

    private var trackTable: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width, trackContentWidth)
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    TrackSortHeader(
                        model: model,
                        titleWidth: $titleColumnWidth,
                        artistWidth: $artistColumnWidth,
                        albumWidth: $albumColumnWidth,
                        genreWidth: $genreColumnWidth,
                        yearWidth: $yearColumnWidth,
                        discNumberWidth: $discNumberColumnWidth,
                        trackNumberWidth: $trackNumberColumnWidth,
                        durationWidth: $durationColumnWidth,
                        addedDateWidth: $addedDateColumnWidth,
                        showSelectionCheckbox: isDuplicateSelectionMode,
                        showCommentAction: isCommentDiagnosticMode,
                        columns: orderedVisibleTrackColumns,
                        moveColumn: { source, column in
                            moveTrackColumn(source, before: column)
                        }
                    )
                    .frame(width: contentWidth, alignment: .leading)
                    Divider()
                    ScrollViewReader { trackScrollProxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 8) {
                                        if isDuplicateSelectionMode {
                                            duplicateSelectionCheckbox(track)
                                        }
                                        if isCommentDiagnosticMode {
                                            Button {
                                                model.clearComment(for: track)
                                            } label: {
                                                Image(systemName: "bubble.left.and.exclamationmark")
                                                    .foregroundStyle(track.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.3) : Color.orange)
                                                    .frame(width: 30)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(track.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                            .help(model.text("コメントを消去", "Clear Comment"))
                                        }
                                        Button {
                                            if track.isFavorite {
                                                model.setFavorite(track, isFavorite: false)
                                            } else {
                                                model.setFavorite(track, isFavorite: true)
                                            }
                                        } label: {
                                            Image(systemName: track.isFavorite ? "star.fill" : "star")
                                                .foregroundStyle(track.isFavorite ? .yellow : .secondary)
                                                .frame(width: 30)
                                        }
                                        .buttonStyle(.plain)
                                        .help(track.isFavorite ? model.text("お気に入りから外す", "Remove from Favorites") : model.text("お気に入りに追加", "Add to Favorites"))
                                        ForEach(orderedVisibleTrackColumns) { column in
                                            trackColumnCell(column, track: track, index: index)
                                                .tableColumnDivider()
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(width: contentWidth, height: 32, alignment: .leading)
                                    .background(trackRowBackground(track: track, index: index, isCurrent: player.currentTrack?.id == track.id))
                                    .overlay(alignment: .leading) {
                                        if player.currentTrack?.id == track.id {
                                            Rectangle()
                                                .fill(Color.accentColor)
                                                .frame(width: 3)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        isTrackTableFocused = true
                                        if hasSelectionModifier {
                                            handleTrackSelection(track, at: index)
                                        } else {
                                            model.selectedTrackIDs = [track.id]
                                            selectionAnchorID = track.id
                                            if let context = model.trackPlaybackContext {
                                                player.playFromList(track, context: context)
                                            } else {
                                                player.play(track)
                                            }
                                        }
                                    }
                                    .simultaneousGesture(
                                    TapGesture(count: 1)
                                        .onEnded {
                                            isTrackTableFocused = true
                                            handleTrackSelection(track, at: index)
                                        }
                                    )
                                    .draggable(trackDragPayload(for: track))
                                    .contextMenu { trackContextMenu(track) }
                                    .id(track.id)
                                }
                            }
                        }
                        .frame(width: contentWidth, height: max(0, geometry.size.height - 32), alignment: .top)
                        .onAppear {
                            restoreTrackScrollIfNeeded(using: trackScrollProxy)
                        }
                        .onChange(of: model.trackScrollPosition) { _, newPosition in
                            if let newPosition {
                                trackScrollProxy.scrollTo(newPosition, anchor: .top)
                            }
                        }
                    }
                }
                .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
            }
            .scrollDisabled(trackContentWidth <= geometry.size.width)
            .id(trackTableContextID)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focused($isTrackTableFocused)
        .focusEffectDisabled()
        .onKeyPress("a", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            selectAllVisibleTracks()
            return .handled
        }
        .overlay {
            if model.section == .playlists,
               model.selectedPlaylistID != nil,
               model.tracks.isEmpty {
                ContentUnavailableView(
                    model.text("プレイリストに曲がありません", "No Songs in This Playlist"),
                    systemImage: "music.note.list",
                    description: Text(model.text(
                        "曲をこのプレイリストへドラッグするか、曲の右クリックメニューから追加できます。",
                        "Drag songs to this playlist or add them from a song's context menu."
                    ))
                )
            } else if model.isLoading { ProgressView().controlSize(.large) }
            else if model.tracks.isEmpty {
                if model.section == .cache {
                    ContentUnavailableView(
                        model.text("キャッシュされた曲がありません", "No Cached Songs"),
                        systemImage: "internaldrive",
                        description: Text(model.text(
                            "曲を再生するか、曲の右クリックメニューからローカルにキャッシュできます。",
                            "Play a song or use Cache Locally from its context menu."
                        ))
                    )
                } else {
                    ContentUnavailableView(model.text("曲がありません", "No Songs"), systemImage: "music.note", description: Text(model.text("音楽フォルダを追加してください。", "Add a music folder.")))
                }
            }
        }
    }

    private func beginEditingPlaylist(_ playlist: Playlist) {
        guard !isReorderingPlaylists else { return }
        if model.selectedPlaylistID != playlist.id || model.section != .playlists {
            model.selectPlaylist(playlist.id)
        }
        playlistNameDraft = playlist.name
        editingPlaylistID = playlist.id
        Task { @MainActor in
            await Task.yield()
            focusedPlaylistEditorID = playlist.id
        }
    }

    private func commitPlaylistRename(_ playlistID: Int64) {
        guard editingPlaylistID == playlistID else { return }
        if model.renamePlaylist(id: playlistID, name: playlistNameDraft) {
            editingPlaylistID = nil
            focusedPlaylistEditorID = nil
        } else {
            focusedPlaylistEditorID = playlistID
        }
    }

    private func cancelPlaylistRename() {
        editingPlaylistID = nil
        focusedPlaylistEditorID = nil
        playlistNameDraft = ""
    }

    @ViewBuilder private func trackColumnCell(_ column: TrackSort, track: Track, index: Int) -> some View {
        switch column {
        case .title:
            let isPlayable = model.isTrackPlayable(track)
                && (!player.unavailableTrackIDs.contains(track.id) || model.isCached(track))
            TrackTitleCell(
                track: track,
                isPlayable: isPlayable,
                isCurrent: player.currentTrack?.id == track.id,
                helpText: isPlayable ? "" : model.text(
                    "元ファイルが見つからず、ローカルキャッシュもありません",
                    "Original file is missing and no local cache is available"
                ),
                diagnosticKind: model.section == .diagnostics ? model.diagnosticKind : nil,
                isJapanese: model.language == .japanese
            )
            .frame(width: titleColumnWidth, alignment: .leading)
        case .artist:
            let isDiag = model.section == .diagnostics
            TrackNavigationCell(
                title: model.displayArtist(track.artist),
                width: artistColumnWidth,
                hasURL: isDiag && model.diagnosticKind == .urlInMP3Metadata && track.artist.containsURLPattern,
                hasMojibake: isDiag && model.diagnosticKind == .suspectedMojibake && track.artist.containsMojibakePattern
            ) {
                isTrackTableFocused = true
                if hasSelectionModifier {
                    handleTrackSelection(track, at: index)
                } else {
                    model.openArtist(named: track.artist)
                }
            }
        case .album:
            let isDiag = model.section == .diagnostics
            TrackNavigationCell(
                title: track.album,
                width: albumColumnWidth,
                hasURL: isDiag && model.diagnosticKind == .urlInMP3Metadata && track.album.containsURLPattern,
                hasMojibake: isDiag && model.diagnosticKind == .suspectedMojibake && track.album.containsMojibakePattern
            ) {
                isTrackTableFocused = true
                if hasSelectionModifier {
                    handleTrackSelection(track, at: index)
                } else {
                    model.openAlbum(AlbumSummary(name: track.album, artist: track.artist, trackCount: 0))
                }
            }
            .disabled(track.album.isEmpty)
        case .genre:
            let isDiag = model.section == .diagnostics
            TrackNavigationCell(
                title: track.genre.isEmpty ? "—" : track.genre,
                width: genreColumnWidth,
                hasURL: isDiag && model.diagnosticKind == .urlInMP3Metadata && track.genre.containsURLPattern,
                hasMojibake: isDiag && model.diagnosticKind == .suspectedMojibake && track.genre.containsMojibakePattern
            ) {
                isTrackTableFocused = true
                if hasSelectionModifier {
                    handleTrackSelection(track, at: index)
                } else if !track.genre.isEmpty {
                    model.openGenre(track.genre)
                }
            }
            .disabled(track.genre.isEmpty)
        case .year:
            Text(track.year.isEmpty ? "—" : track.year)
                .monospacedDigit()
                .foregroundStyle(track.year.isEmpty ? .secondary : .primary)
                .frame(width: yearColumnWidth, alignment: .leading)
        case .discNumber:
            Text(track.discNumber.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(track.discNumber == nil ? .secondary : .primary)
                .frame(width: discNumberColumnWidth, alignment: .leading)
        case .trackNumber:
            Text(track.trackNumber.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(track.trackNumber == nil ? .secondary : .primary)
                .frame(width: trackNumberColumnWidth, alignment: .leading)
        case .duration:
            Text(formatDuration(track.duration))
                .monospacedDigit()
                .frame(width: durationColumnWidth, alignment: .leading)
        case .format:
            Text(track.format.uppercased()).frame(width: 55, alignment: .leading)
        case .dateAdded:
            Text(formatAddedDate(track.addedAt))
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: addedDateColumnWidth, alignment: .leading)
        case .path:
            EmptyView()
        }
    }

    private func duplicateSelectionCheckbox(_ track: Track) -> some View {
        Toggle(
            model.text("\(track.title)を選択", "Select \(track.title)"),
            isOn: Binding(
                get: { model.selectedTrackIDs.contains(track.id) },
                set: { isSelected in
                    if isSelected {
                        model.selectedTrackIDs.insert(track.id)
                    } else {
                        model.selectedTrackIDs.remove(track.id)
                    }
                    selectionAnchorID = track.id
                }
            )
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(width: 30)
        .help(model.text("削除する曲として選択", "Select this song for deletion"))
    }

    private var trackTableContextID: String {
        [
            model.section.rawValue,
            model.selectedPlaylistID.map(String.init) ?? "",
            model.selectedAlbum.map { "\($0.artist)|\($0.name)" } ?? "",
            model.selectedArtist?.name ?? "",
            model.selectedGenre ?? "",
            model.genreDetailMode.rawValue,
            model.diagnosticKind.rawValue,
            model.metadataIssueFieldFilter?.rawValue ?? ""
        ].joined(separator: "::")
    }

    private func trackRowBackground(track: Track, index: Int, isCurrent: Bool) -> Color {
        if model.selectedTrackIDs.contains(track.id) {
            return Color.accentColor.opacity(0.30)
        }
        if isCurrent {
            return Color.accentColor.opacity(0.18)
        }
        return index.isMultiple(of: 2) ? Color.secondary.opacity(0.06) : Color.clear
    }

    @ViewBuilder
    private func trackContextMenu(_ track: Track) -> some View {
        Button(model.text("次に再生", "Play Next")) { player.addToUpNext(track) }
        if model.isStorageExternal {
            if model.isCached(track) {
                Button(model.text("ローカルキャッシュから削除", "Remove from Local Cache"), role: .destructive) {
                    model.removeTrackFromCache(track)
                }
            } else {
                Button {
                    model.cacheTrack(track)
                } label: {
                    if model.cachingTrackIDs.contains(track.id) {
                        Text(model.text("キャッシュ中…", "Caching…"))
                    } else {
                        Text(model.text("ローカルにキャッシュ", "Cache Locally"))
                    }
                }
                .disabled(model.cachingTrackIDs.contains(track.id))
            }
            Divider()
        }
        Section(model.text("プレイリストに追加", "Add to Playlist")) {
            if model.playlists.isEmpty {
                Button(model.text("新規プレイリストを作成", "Create New Playlist")) {
                    model.createPlaylist()
                }
            } else {
                ForEach(model.playlists) { playlist in
                    Button(playlist.name) {
                        if !model.selectedTrackIDs.contains(track.id) { model.selectedTrackIDs = [track.id] }
                        model.addSelectionToPlaylist(playlist.id)
                    }
                }
            }
        }
        Divider()
        Button {
            player.play(track)
            model.openAndListenWithShazam()
        } label: {
            Label(model.text("Shazamで再生して聴かせる", "Play & Listen with Shazam"), systemImage: "waveform.badge.mic")
        }
        Button {
            Task { await model.recognizeTrackWithShazam(for: track) }
        } label: {
            Label(model.text("Shazamで曲情報を特定・修復…", "Identify & Repair with Shazam…"), systemImage: "waveform.and.magnifyingglass")
        }
        Button {
            model.openShazamApp()
        } label: {
            Label(model.text("Shazamアプリを開く", "Open Shazam App"), systemImage: "arrow.up.forward.app")
        }
        Divider()
        if model.selectedTrackIDs.contains(track.id), selectedTracksOnPage.count > 1 {
            Button(model.text(
                "選択した\(selectedTracksOnPage.count)曲を一括編集…",
                "Bulk Edit \(selectedTracksOnPage.count) Selected Songs…"
            )) { openBatchMetadataEditor() }
        }
        Button(model.text("この曲の情報を編集…", "Edit This Song…")) { trackBeingEdited = track }
        if model.selectedTrackIDs.contains(track.id), selectedTracksOnPage.count > 1 {
            Button(model.text("選択した\(selectedTracksOnPage.count)曲を削除…", "Delete \(selectedTracksOnPage.count) Selected Songs…"), role: .destructive) {
                tracksPendingDeletion = selectedTracksOnPage
            }
        } else {
            Button(model.text("削除…", "Delete…"), role: .destructive) { trackPendingDeletion = track }
        }
        if model.selectedPlaylistID != nil {
            Button(model.text("上へ移動", "Move Up")) { model.moveTrackInSelectedPlaylist(track.id, by: -1) }
            Button(model.text("下へ移動", "Move Down")) { model.moveTrackInSelectedPlaylist(track.id, by: 1) }
            Button(model.text("プレイリストから削除", "Remove from Playlist"), role: .destructive) {
                model.selectedTrackIDs = [track.id]
                model.removeSelectionFromPlaylist()
            }
        }
    }

    @ViewBuilder private var albumSummaryList: some View {
        if model.selectedAlbum == nil,
           (model.section == .albums || model.selectedArtist != nil),
           albumPresentation == SummaryPresentation.grid.rawValue {
            albumSummaryGrid
        } else {
            albumSummaryTable
        }
    }

    private let defaultAlbumColumnOrder: [AlbumSort] = [.name, .artist, .year, .trackCount]

    private var orderedAlbumColumns: [AlbumSort] {
        var seen = Set<String>()
        let stored = albumColumnOrderStorage
            .split(separator: ",")
            .compactMap { AlbumSort(rawValue: String($0)) }
            .filter { defaultAlbumColumnOrder.contains($0) && seen.insert($0.rawValue).inserted }
        return stored + defaultAlbumColumnOrder.filter { !seen.contains($0.rawValue) }
    }

    private var orderedVisibleAlbumColumns: [AlbumSort] {
        orderedAlbumColumns.filter(isAlbumColumnVisible)
    }

    private func isAlbumColumnVisible(_ column: AlbumSort) -> Bool {
        switch column {
        case .name: true
        case .artist: isAlbumViewArtistVisible
        case .year: isAlbumViewYearVisible
        case .trackCount: isAlbumViewSongsVisible
        }
    }

    private func moveAlbumColumn(_ source: AlbumSort, before destination: AlbumSort) {
        guard source != destination else { return }
        var order = orderedAlbumColumns
        guard let sourceIndex = order.firstIndex(of: source) else { return }
        order.remove(at: sourceIndex)
        guard let destinationIndex = order.firstIndex(of: destination) else { return }
        order.insert(source, at: destinationIndex)
        albumColumnOrderStorage = order.map(\.rawValue).joined(separator: ",")
    }

    @ViewBuilder
    private func albumColumnHeader(_ column: AlbumSort) -> some View {
        switch column {
        case .name:
            albumHeaderButton(.name, title: model.text("アルバム", "Album"))
                .frame(width: albumViewAlbumWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $albumViewAlbumWidth, range: 140...900)
                }
        case .artist:
            albumHeaderButton(.artist, title: model.text("アーティスト", "Artist"))
                .frame(width: albumViewArtistWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $albumViewArtistWidth, range: 100...600)
                }
        case .year:
            albumHeaderButton(.year, title: model.text("リリース年", "Release Year"))
                .frame(width: albumViewYearWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $albumViewYearWidth, range: 60...200)
                }
        case .trackCount:
            albumHeaderButton(.trackCount, title: model.text("曲数", "Songs"))
                .frame(width: albumViewSongsWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $albumViewSongsWidth, range: 55...180)
                }
        }
    }

    @ViewBuilder
    private func albumColumnCell(_ column: AlbumSort, album: AlbumSummary) -> some View {
        switch column {
        case .name:
            Button { model.openAlbum(album) } label: {
                Label(album.name, systemImage: "square.stack")
                    .frame(width: albumViewAlbumWidth, alignment: .leading)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        case .artist:
            Button { model.openArtist(named: album.artist) } label: {
                Text(model.displayArtist(album.artist))
                    .foregroundStyle(.primary)
                    .frame(width: albumViewArtistWidth, alignment: .leading)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        case .year:
            Text(album.year.isEmpty ? "-" : album.year)
                .foregroundStyle(album.year.isEmpty ? .secondary : .primary)
                .frame(width: albumViewYearWidth, alignment: .trailing)
                .monospacedDigit()
                .lineLimit(1)
        case .trackCount:
            Text(album.trackCount.formatted())
                .frame(width: albumViewSongsWidth, alignment: .trailing)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var albumSummaryTable: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(orderedVisibleAlbumColumns) { column in
                            albumColumnHeader(column)
                                .tableColumnDivider()
                                .draggable(column.rawValue)
                                .dropDestination(for: String.self) { values, _ in
                                    guard let rawValue = values.first,
                                          let source = AlbumSort(rawValue: rawValue),
                                          orderedVisibleAlbumColumns.contains(source) else { return false }
                                    moveAlbumColumn(source, before: column)
                                    return true
                                }
                        }
                        Spacer().frame(width: 28)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.bar)
                    Divider()
                    List(model.albumSummaries) { album in
                        HStack(spacing: 8) {
                            ForEach(orderedVisibleAlbumColumns) { column in
                                albumColumnCell(column, album: album)
                                    .tableColumnDivider()
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).frame(width: 20)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .frame(width: max(geometry.size.width, albumSummaryContentWidth), height: geometry.size.height)
            }
        }
    }

    private var albumSummaryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 18)], spacing: 22) {
                ForEach(model.albumSummaries) { album in
                    Button { model.openAlbum(album) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            PlayerArtwork(artworkURL: model.albumArtworkURLs[album.id], size: 170, cornerRadius: 10, placeholderPointSize: 38)
                                .frame(maxWidth: .infinity)
                            Text(album.name).font(.headline).lineLimit(2)
                            Text(model.displayArtist(album.artist)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Text(
                                album.year.isEmpty
                                    ? model.text("\(album.trackCount)曲", "\(album.trackCount) songs")
                                    : album.year + model.text("年 • \(album.trackCount)曲", " • \(album.trackCount) songs")
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .task { model.loadArtwork(for: album) }
                }
            }
            .padding(18)
        }
    }

    private var albumSummaryContentWidth: Double {
        albumViewAlbumWidth
            + (isAlbumViewArtistVisible ? albumViewArtistWidth + 8 : 0)
            + (isAlbumViewYearVisible ? albumViewYearWidth + 8 : 0)
            + (isAlbumViewSongsVisible ? albumViewSongsWidth + 8 : 0) + 70
    }

    private func albumHeaderButton(_ sort: AlbumSort, title: String) -> some View {
        let isActive = model.albumSort == sort
        return Button {
            model.albumSortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.albumSortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, alignment: sort == .trackCount ? .trailing : .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }

    @ViewBuilder private var artistSummaryList: some View {
        if model.section == .artists, artistPresentation == SummaryPresentation.grid.rawValue {
            artistSummaryGrid
        } else {
            artistSummaryTable
        }
    }

    private let defaultArtistColumnOrder: [ArtistSort] = [.name, .genre, .albumCount, .trackCount]

    private var orderedArtistColumns: [ArtistSort] {
        var seen = Set<String>()
        let stored = artistColumnOrderStorage
            .split(separator: ",")
            .compactMap { ArtistSort(rawValue: String($0)) }
            .filter { defaultArtistColumnOrder.contains($0) && seen.insert($0.rawValue).inserted }
        return stored + defaultArtistColumnOrder.filter { !seen.contains($0.rawValue) }
    }

    private var orderedVisibleArtistColumns: [ArtistSort] {
        orderedArtistColumns.filter(isArtistColumnVisible)
    }

    private func isArtistColumnVisible(_ column: ArtistSort) -> Bool {
        switch column {
        case .name: true
        case .genre: isArtistViewGenreVisible
        case .albumCount: isArtistViewAlbumsVisible
        case .trackCount: isArtistViewSongsVisible
        }
    }

    private func moveArtistColumn(_ source: ArtistSort, before destination: ArtistSort) {
        guard source != destination else { return }
        var order = orderedArtistColumns
        guard let sourceIndex = order.firstIndex(of: source) else { return }
        order.remove(at: sourceIndex)
        guard let destinationIndex = order.firstIndex(of: destination) else { return }
        order.insert(source, at: destinationIndex)
        artistColumnOrderStorage = order.map(\.rawValue).joined(separator: ",")
    }

    private var artistSummaryTable: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(orderedVisibleArtistColumns) { column in
                    artistColumnHeader(column)
                        .tableColumnDivider()
                        .draggable(column.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard let rawValue = values.first,
                                  let source = ArtistSort(rawValue: rawValue),
                                  orderedVisibleArtistColumns.contains(source) else { return false }
                            moveArtistColumn(source, before: column)
                            return true
                        }
                }
                Spacer().frame(width: 28)
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.artistSummaries) { artist in
                        Button { openArtistPreservingScrollPosition(artist) } label: {
                            HStack(spacing: 8) {
                                ForEach(orderedVisibleArtistColumns) { column in
                                    artistColumnCell(column, artist: artist)
                                        .tableColumnDivider()
                                }
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary).frame(width: 20)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(artist.id)
                        Divider()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $artistScrollPosition, anchor: .top)
        }
        .frame(width: max(geometry.size.width, artistSummaryContentWidth), height: geometry.size.height)
            }
        }
    }

    private var artistSummaryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)], spacing: 24) {
                ForEach(model.artistSummaries) { artist in
                    Button { openArtistPreservingScrollPosition(artist) } label: {
                        VStack(spacing: 8) {
                            PlayerArtwork(artworkURL: model.artistImageURLs[artist.name], size: 150, cornerRadius: 75, placeholderPointSize: 36)
                            Text(model.displayArtist(artist.name)).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                            Text(model.text("\(artist.albumCount)アルバム・\(artist.trackCount)曲", "\(artist.albumCount) albums · \(artist.trackCount) songs"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(artist.id)
                    .task { model.loadImage(for: artist) }
                }
            }
            .scrollTargetLayout()
            .padding(18)
        }
        .scrollPosition(id: $artistScrollPosition, anchor: .top)
    }

    private func openArtistPreservingScrollPosition(_ artist: ArtistSummary) {
        artistReturnScrollPosition = artistScrollPosition ?? artist.id
        model.openArtist(artist)
    }

    private func closeDetailRestoringScrollPosition() {
        let shouldRestoreArtistList = model.section == .artists
            && model.selectedArtist != nil
            && model.selectedAlbum == nil
        model.closeDetail()
        if shouldRestoreArtistList, artistReturnScrollPosition != nil {
            restorePendingArtistScrollPositionIfNeeded()
        }
        restorePendingBrowseScrollPositionIfNeeded()
    }

    private func restorePendingArtistScrollPositionIfNeeded() {
        guard !model.isLoading,
              model.section == .artists,
              model.selectedArtist == nil,
              model.selectedAlbum == nil,
              let returnPosition = artistReturnScrollPosition else { return }
        artistScrollPosition = nil
        Task { @MainActor in
            await Task.yield()
            artistScrollPosition = returnPosition
            artistReturnScrollPosition = nil
        }
    }

    private func restoreTrackScrollIfNeeded(using proxy: ScrollViewProxy) {
        guard model.needsBrowseScrollRestoration, let targetID = model.trackScrollPosition else { return }
        for delay in [0.01, 0.05, 0.12] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            model.completeBrowseScrollRestoration()
        }
    }

    private func restorePendingBrowseScrollPositionIfNeeded() {
        // Handled via ScrollViewReader restoreTrackScrollIfNeeded
    }

    private func restoreVariationScroll(using proxy: ScrollViewProxy) {
        guard let targetID = model.resolvedVariationScrollPositionForRestoration() else { return }
        for delay in [0.01, 0.05, 0.12] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    private func restoreGenreScroll(using proxy: ScrollViewProxy) {
        guard let target = model.resolvedGenreScrollPositionForRestoration() else { return }
        for delay in [0.01, 0.05, 0.12] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    @ViewBuilder private func artistColumnHeader(_ column: ArtistSort) -> some View {
        switch column {
        case .name:
            artistHeaderButton(.name, title: model.text("アーティスト", "Artist"))
                .frame(width: artistViewArtistWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $artistViewArtistWidth, range: 140...900)
                }
        case .genre:
            artistHeaderButton(.genre, title: model.text("ジャンル", "Genre"))
                .frame(width: artistViewGenreWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $artistViewGenreWidth, range: 90...360)
                }
        case .albumCount:
            artistHeaderButton(.albumCount, title: model.text("アルバム数", "Albums"))
                .frame(width: artistViewAlbumsWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $artistViewAlbumsWidth, range: 65...200)
                }
        case .trackCount:
            artistHeaderButton(.trackCount, title: model.text("曲数", "Songs"))
                .frame(width: artistViewSongsWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(width: $artistViewSongsWidth, range: 55...180)
                }
        }
    }

    @ViewBuilder private func artistColumnCell(_ column: ArtistSort, artist: ArtistSummary) -> some View {
        switch column {
        case .name:
            Label(model.displayArtist(artist.name), systemImage: artist.name.isEmpty ? "person.crop.circle.badge.questionmark" : "music.mic")
                .frame(width: artistViewArtistWidth, alignment: .leading)
        case .genre:
            Text(artist.genre.isEmpty ? "—" : artist.genre)
                .foregroundStyle(artist.genre.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: artistViewGenreWidth, alignment: .leading)
        case .albumCount:
            Text(artist.albumCount.formatted())
                .frame(width: artistViewAlbumsWidth, alignment: .trailing)
                .monospacedDigit()
        case .trackCount:
            Text(artist.trackCount.formatted())
                .frame(width: artistViewSongsWidth, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var artistSummaryContentWidth: Double {
        orderedVisibleArtistColumns.reduce(0.0) { sum, column in
            switch column {
            case .name: sum + artistViewArtistWidth + 8
            case .genre: sum + artistViewGenreWidth + 8
            case .albumCount: sum + artistViewAlbumsWidth + 8
            case .trackCount: sum + artistViewSongsWidth + 8
            }
        } + 70
    }

    private func artistHeaderButton(_ sort: ArtistSort, title: String) -> some View {
        let isActive = model.artistSort == sort
        return Button {
            model.artistSortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.artistSortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, alignment: (sort == .name || sort == .genre) ? .leading : .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }

    private var facetList: some View {
        VStack(spacing: 0) {
            if model.section == .genres {
                genreAutomaticScanControls
                Divider()
            }
            ScrollViewReader { proxy in
                List(model.facets) { facet in
                    if model.section == .genres {
                        Button { model.openGenre(facet.name, anchorGenre: facet.name) } label: {
                            HStack {
                                Image(systemName: icon(for: model.section)).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(facet.name)
                                        .lineLimit(1)
                                    Text(model.genreShortDescription(facet.name))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(facet.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .id(facet.name)
                    } else {
                        HStack {
                            Image(systemName: icon(for: model.section)).frame(width: 24)
                            Text(facet.name)
                            Spacer()
                            Text(facet.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 3)
                        .id(facet.name)
                    }
                }
                .onAppear {
                    restoreGenreScroll(using: proxy)
                }
                .onChange(of: model.facets.first?.name) { _, _ in
                    restoreGenreScroll(using: proxy)
                }
            }
        }
    }

    private var genreAutomaticScanControls: some View {
        HStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.text("ジャンル自動登録", "Automatic Genre Registration"))
                    .font(.headline)
                Text(model.text(
                    "ライブラリ内一致→ローカル判定→MusicBrainz→外部AIの順に調べ、確度80%以上だけを登録します。",
                    "Checks library matches, local rules, MusicBrainz, then external AI; only results at 80% confidence or higher are saved."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer(minLength: 12)
            if model.isScanningAutomaticGenres {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: Double(model.automaticGenreScanProcessedCount), total: Double(max(1, model.automaticGenreScanTotalCount)))
                        .frame(width: 150)
                    if model.automaticGenreRetrySecondsRemaining > 0 {
                        Text(model.text(
                            "外部AIへ\(model.automaticGenreRetrySecondsRemaining)秒後に自動再接続",
                            "Reconnecting to external AI in \(model.automaticGenreRetrySecondsRemaining)s"
                        ))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                    }
                    Text(model.text(
                        "確認 \(model.automaticGenreScanProcessedCount.formatted()) / \(model.automaticGenreScanTotalCount.formatted())・登録 \(model.automaticGenreRegisteredCount.formatted())・80%未満 \(model.automaticGenreScanBelowThresholdCount.formatted())・失敗 \(model.automaticGenreScanFailedCount.formatted())",
                        "Checked \(model.automaticGenreScanProcessedCount.formatted()) / \(model.automaticGenreScanTotalCount.formatted()) · Registered \(model.automaticGenreRegisteredCount.formatted()) · Below 80% \(model.automaticGenreScanBelowThresholdCount.formatted()) · Failed \(model.automaticGenreScanFailedCount.formatted())"
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text(model.text(
                        "内訳: ライブラリ \(model.automaticGenreLibraryRegisteredCount)・ローカル \(model.automaticGenreLocalRegisteredCount)・MusicBrainz \(model.automaticGenreMusicBrainzRegisteredCount)・外部AI \(model.automaticGenreExternalAIRegisteredCount)",
                        "Sources: library \(model.automaticGenreLibraryRegisteredCount) · local \(model.automaticGenreLocalRegisteredCount) · MusicBrainz \(model.automaticGenreMusicBrainzRegisteredCount) · external AI \(model.automaticGenreExternalAIRegisteredCount)"
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Button(model.text("停止", "Stop")) { model.cancelAutomaticGenreScan() }
            } else {
                if model.hasRunAutomaticGenreScan {
                    Text(model.text(
                        "登録 \(model.automaticGenreRegisteredCount.formatted())・80%未満 \(model.automaticGenreScanBelowThresholdCount.formatted())・失敗 \(model.automaticGenreScanFailedCount.formatted())",
                        "Registered \(model.automaticGenreRegisteredCount.formatted()) · Below 80% \(model.automaticGenreScanBelowThresholdCount.formatted()) · Failed \(model.automaticGenreScanFailedCount.formatted())"
                    ))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Button {
                    model.startAutomaticGenreScan()
                } label: {
                    Label(model.text("ジャンル検索を開始", "Start Genre Scan"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var activityLogView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(
                    model.text("ログの種類", "Log Type"),
                    selection: Binding(
                        get: { model.activityCategoryFilter },
                        set: { model.setActivityCategoryFilter($0) }
                    )
                ) {
                    ForEach(ActivityLogCategoryFilter.allCases) { filter in
                        Text(filter.title(isJapanese: model.language == .japanese)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                Picker(
                    model.text("保持: \(model.maxLogRetentionLimit.rawValue.formatted())件", "Max: \(model.maxLogRetentionLimit.rawValue.formatted())"),
                    selection: $model.maxLogRetentionLimit
                ) {
                    ForEach(LogRetentionLimit.allCases) { limit in
                        Text(limit.title(isJapanese: model.language == .japanese)).tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .fixedSize()
                .onChange(of: model.maxLogRetentionLimit) { _, _ in
                    model.saveLogRetentionSettings()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            List(model.activityEvents) { event in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: activityKindIcon(event.kind))
                        .font(.title3)
                        .foregroundStyle(activityKindColor(event.kind))
                        .frame(width: 28, height: 28)
                        .background(activityKindColor(event.kind).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(activityKindTitle(event.kind)).font(.headline)
                            Text(event.title.isEmpty ? event.filename : event.title)
                                .fontWeight(.semibold).lineLimit(1)
                            Spacer(minLength: 16)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !event.artist.isEmpty || !event.album.isEmpty {
                            Text([event.artist, event.album].filter { !$0.isEmpty }.joined(separator: " — "))
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        ForEach(event.changes.prefix(4), id: \.self) { change in
                            HStack(spacing: 6) {
                                Text(activityFieldTitle(change.field)).fontWeight(.medium)
                                Text(change.oldValue.isEmpty ? model.text("（空）", "(empty)") : change.oldValue)
                                    .foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                Text(change.newValue.isEmpty ? model.text("（空）", "(empty)") : change.newValue)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                        if event.changes.count > 4 {
                            Text(model.text("ほか\(event.changes.count - 4)件の変更", "\(event.changes.count - 4) more changes"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.absolutePath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                            .help(event.absolutePath).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 5)
            }
            .overlay {
                if !model.isLoading && model.activityEvents.isEmpty {
                    ContentUnavailableView(
                        model.text("ログはまだありません", "No Activity Yet"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(model.text(
                            "選択したカテゴリのログはまだありません。",
                            "There are no log events in this category yet."
                        ))
                    )
                }
            }
        }
    }

    @ViewBuilder private var genreDetailContent: some View {
        switch model.genreDetailMode {
        case .albums: albumSummaryList
        case .artists: artistSummaryList
        case .tracks: trackTable
        }
    }

    private var metadataDiagnosticsView: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                ForEach(MetadataIssueKind.allCases) { kind in
                    Button { model.selectDiagnostic(kind) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(diagnosticTitle(kind), systemImage: diagnosticIcon(kind))
                                .lineLimit(1)
                            Text(diagnosticCount(kind).formatted())
                                .font(.title3.bold()).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(model.diagnosticKind == kind ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            if isDuplicateSelectionMode {
                duplicateSelectionToolbar
                Divider()
            }
            if model.diagnosticKind == .suspectedVariations {
                if model.batchMetadataProgress.state == .running {
                    HStack(spacing: 12) {
                        ProgressView(
                            value: Double(model.batchMetadataProgress.processed),
                            total: Double(max(1, model.batchMetadataProgress.total))
                        )
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)

                        Text(model.text(
                            "表記を「\(model.activeStandardizingTargetValue ?? "")」に統一中… \(model.batchMetadataProgress.processed) / \(model.batchMetadataProgress.total) 曲 (\(Int(Double(model.batchMetadataProgress.processed) / Double(max(1, model.batchMetadataProgress.total)) * 100))%)",
                            "Standardizing to \"\(model.activeStandardizingTargetValue ?? "")\"… \(model.batchMetadataProgress.processed) / \(model.batchMetadataProgress.total) songs (\(Int(Double(model.batchMetadataProgress.processed) / Double(max(1, model.batchMetadataProgress.total)) * 100))%)"
                        ))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)

                        Spacer()

                        Button(model.text("キャンセル", "Cancel")) {
                            model.cancelBatchMetadataUpdate()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                }
                HStack {
                    if model.isAnalyzingMetadata {
                        ProgressView().controlSize(.small)
                        Text(model.text(
                            "\(model.metadataAnalysisProgress.processedTerms.formatted())件を確認・\(model.metadataAnalysisProgress.candidates.formatted())候補",
                            "Checked \(model.metadataAnalysisProgress.processedTerms.formatted()) terms · \(model.metadataAnalysisProgress.candidates.formatted()) candidates"
                        )).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("キャンセル", "Cancel"), action: model.cancelMetadataAnalysis)
                    } else {
                        Text(model.text("候補は自動変更せず、確認用に表示します。", "Candidates are shown for review; nothing is changed automatically."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("表記ゆれを解析", "Analyze Variations"), action: model.runMetadataAnalysis)
                            .disabled(model.batchMetadataProgress.state == .running)
                    }
                }.padding(10)
                HStack(spacing: 10) {
                    Picker(model.text("表示対象", "Show"), selection: Binding(
                        get: { model.variationFieldFilter },
                        set: { model.setVariationFieldFilter($0) }
                    )) {
                        Text(model.text("すべて", "All")).tag(MetadataField?.none)
                        Text(model.text("曲名", "Title")).tag(MetadataField?.some(.title))
                        Text(model.text("アルバム名", "Album")).tag(MetadataField?.some(.album))
                        Text(model.text("アーティスト名", "Artist")).tag(MetadataField?.some(.artist))
                        Text(model.text("ジャンル", "Genre")).tag(MetadataField?.some(.genre))
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 620)
                    Spacer()
                    Text(model.text(
                        "該当候補: \(model.totalCount.formatted())件",
                        "Matching: \(model.totalCount.formatted())"
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                Divider()
                ScrollViewReader { proxy in
                    List(model.variationCandidates) { candidate in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(metadataFieldTitle(candidate.field)).font(.caption.bold()).foregroundStyle(.secondary)
                                    Text(variationReason(candidate)).font(.caption).foregroundStyle(.orange)
                                }
                                variationChoiceRow(
                                    value: candidate.valueA,
                                    count: candidate.trackCountA,
                                    candidate: candidate,
                                    onInspect: {
                                        model.searchVariationValue(candidate.valueA, field: candidate.field, anchorCandidateID: candidate.id)
                                    }
                                )
                                variationChoiceRow(
                                    value: candidate.valueB,
                                    count: candidate.trackCountB,
                                    candidate: candidate,
                                    onInspect: {
                                        model.searchVariationValue(candidate.valueB, field: candidate.field, anchorCandidateID: candidate.id)
                                    }
                                )
                            }
                            Spacer()
                            Button(model.text("候補から除外", "Ignore")) { model.ignoreVariation(candidate) }
                        }
                        .padding(.vertical, 4)
                        .id(candidate.id)
                    }
                    .scrollTargetLayout()
                    .scrollPosition(id: $model.variationScrollPosition, anchor: .top)
                    .onAppear {
                        restoreVariationScroll(using: proxy)
                    }
                    .onChange(of: model.variationCandidates.first?.id) { _, _ in
                        restoreVariationScroll(using: proxy)
                    }
                    .overlay {
                        if !model.isAnalyzingMetadata && model.variationCandidates.isEmpty {
                            ContentUnavailableView(
                                model.variationFieldFilter == nil
                                    ? model.text("表記ゆれ候補はまだありません", "No Variation Candidates Yet")
                                    : model.text("選択した項目の候補はありません", "No Candidates for This Field"),
                                systemImage: "text.magnifyingglass",
                                description: Text(
                                    model.variationFieldFilter == nil
                                        ? model.text("「表記ゆれを解析」をクリックしてください。", "Click Analyze Variations to scan the library.")
                                        : model.text("別の項目を選ぶか、表記ゆれを再解析してください。", "Choose another field or analyze variations again.")
                                )
                            )
                        }
                    }
                }
            } else {
                if model.diagnosticKind == .corruptedOrEmpty {
                    HStack(spacing: 12) {
                        Button {
                            model.repairCorruptedTracks()
                        } label: {
                            Label(model.text("実ファイルからメタデータを再解析・修復", "Scan & Repair from Source File"), systemImage: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isRepairingCorruptedTracks)

                        Button(role: .destructive) {
                            showDeleteUnrepairableAlert = true
                        } label: {
                            Label(model.text("修復できない破損ファイルを削除", "Delete Unrepairable Corrupted Files"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isRepairingCorruptedTracks)

                        Spacer()

                        if model.isRepairingCorruptedTracks {
                            ProgressView().controlSize(.small)
                            if let msg = model.repairProgressMessage {
                                Text(msg).font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(model.text(
                                "該当曲: \(model.totalCount.formatted())曲",
                                "Matching: \(model.totalCount.formatted()) songs"
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .confirmationDialog(
                        model.text("修復できない破損ファイルをゴミ箱へ移動して削除しますか？", "Move unrepairable corrupted files to Trash and remove from library?"),
                        isPresented: $showDeleteUnrepairableAlert,
                        titleVisibility: .visible
                    ) {
                        Button(model.text("削除を実行", "Delete Files"), role: .destructive) {
                            model.removeUnrepairableCorruptedTracks()
                        }
                        Button(model.text("キャンセル", "Cancel"), role: .cancel) { }
                    }
                    Divider()
                } else if [.urlInMP3Metadata, .suspectedMojibake].contains(model.diagnosticKind) {
                    HStack(spacing: 8) {
                        Picker(model.text("表示対象", "Show"), selection: Binding(
                            get: { model.metadataIssueFieldFilter },
                            set: { model.setMetadataIssueFieldFilter($0) }
                        )) {
                            Text(model.text("すべて", "All")).tag(MetadataField?.none)
                            Text(model.text("曲名", "Title")).tag(MetadataField?.some(.title))
                            Text(model.text("アルバム名", "Album")).tag(MetadataField?.some(.album))
                            Text(model.text("アーティスト名", "Artist")).tag(MetadataField?.some(.artist))
                            Text(model.text("コメント", "Comment")).tag(MetadataField?.some(.comment))
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(maxWidth: 320)
                        .fixedSize(horizontal: false, vertical: true)

                        if model.diagnosticKind == .suspectedMojibake {
                            if model.isRecognizingWithShazam {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    if let progress = model.shazamRecognitionProgress {
                                        Text(progress)
                                            .font(.caption.monospacedDigit().bold())
                                            .foregroundStyle(model.appearance.palette.accent)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(model.appearance.palette.accent.opacity(0.12), in: Capsule())
                            } else {
                                Button {
                                    Task { await model.batchRecognizeMojibakeWithShazam() }
                                } label: {
                                    Label(
                                        model.text("Shazam一括修復", "Auto-Repair"),
                                        systemImage: "waveform.and.magnifyingglass"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(model.tracks.isEmpty)

                                Button {
                                    model.openShazamApp()
                                } label: {
                                    Label(
                                        model.text("Shazam", "Shazam"),
                                        systemImage: "arrow.up.forward.app"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(model.text(
                            "該当曲: \(model.totalCount.formatted())曲",
                            "Matching: \(model.totalCount.formatted()) songs"
                        ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    Divider()
                } else if model.diagnosticKind == .commentInMP3 {
                    HStack(spacing: 12) {
                        Button(model.text("このページのコメントを一括消去", "Clear All Comments on This Page")) {
                            model.clearCommentsOnCurrentPage()
                        }
                        .disabled(model.tracks.allSatisfy { $0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || model.batchMetadataProgress.state == .running)

                        if model.batchMetadataProgress.state == .running {
                            ProgressView(
                                value: Double(model.batchMetadataProgress.processed),
                                total: Double(max(1, model.batchMetadataProgress.total))
                            )
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 180)

                            Text(model.text(
                                "コメントを消去中… \(model.batchMetadataProgress.processed) / \(model.batchMetadataProgress.total)",
                                "Clearing comments… \(model.batchMetadataProgress.processed) / \(model.batchMetadataProgress.total)"
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(model.text(
                            "該当曲: \(model.totalCount.formatted())曲",
                            "Matching: \(model.totalCount.formatted()) songs"
                        ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    Divider()
                }
                trackTable
            }
        }
    }

    private var isDuplicateSelectionMode: Bool {
        model.section == .diagnostics && model.diagnosticKind == .duplicateTracks
    }

    private var isCommentDiagnosticMode: Bool {
        model.section == .diagnostics && model.diagnosticKind == .commentInMP3
    }

    private var duplicateSelectionToolbar: some View {
        HStack(spacing: 12) {
            Button(model.text("このページをすべて選択", "Select All on This Page")) {
                model.selectedTrackIDs.formUnion(model.tracks.map(\.id))
            }
            .disabled(model.tracks.isEmpty || selectedTracksOnPage.count == model.tracks.count)

            Button(model.text("選択解除", "Clear Selection")) {
                model.selectedTrackIDs.subtract(model.tracks.map(\.id))
            }
            .disabled(selectedTracksOnPage.isEmpty)

            Text(model.text(
                "選択中: \(selectedTracksOnPage.count)曲",
                "Selected: \(selectedTracksOnPage.count) songs"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Spacer()

            Button(role: .destructive) {
                tracksPendingDeletion = selectedTracksOnPage
            } label: {
                Label(
                    model.text(
                        "選択した\(selectedTracksOnPage.count)曲を削除…",
                        "Delete \(selectedTracksOnPage.count) Selected Songs…"
                    ),
                    systemImage: "trash"
                )
            }
            .disabled(selectedTracksOnPage.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var pageControls: some View {
        HStack {
            Button(action: model.previousPage) { Label(model.text("前へ", "Previous"), systemImage: "chevron.left") }
                .disabled(!model.canGoPrevious)
            Text(model.text("ページ \(model.currentPageNumber) / \(model.pageCount)", "Page \(model.currentPageNumber) / \(model.pageCount)"))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(pageJumpEntries) { entry in
                        Button(entry.label) { model.goToPage(entry.target) }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                entry.kind == .page && entry.target == model.currentPageNumber ? Color.accentColor : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                entry.kind == .page && entry.target == model.currentPageNumber ? Color.white : Color.primary
                            )
                    }
                }
            }
            .frame(maxWidth: 900)
            Button(action: model.nextPage) { Label(model.text("次へ", "Next"), systemImage: "chevron.right") }
                .disabled(!model.canGoNext)
        }
        .padding(8)
    }

    private var pageJumpEntries: [PageJumpEntry] {
        PageNavigation.entries(currentPage: model.currentPageNumber, pageCount: model.pageCount)
    }

    private var scanStatus: some View {
        HStack(spacing: 12) {
            if model.scanProgress.state == .running {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
            }
            
            let stateText = model.scanProgress.state == .paused
                ? model.text("スキャン一時停止中", "Scan paused")
                : model.text("ライブラリをスキャン中...", "Scanning library...")
            
            Text(stateText)
                .fontWeight(.semibold)
            
            Text(model.text("(\(model.scanProgress.processed.formatted()) 曲スキャン済み)", "(\(model.scanProgress.processed.formatted()) songs scanned)"))
                .foregroundStyle(.secondary)
            
            let speed = String(format: "%.1f", model.scanProgress.tracksPerSecond)
            Text(model.text("\(speed) 曲/秒", "\(speed) songs/sec"))
                .foregroundStyle(.secondary)
            if model.scanProgress.errors > 0 {
                Label(model.text("\(model.scanProgress.errors) エラー", "\(model.scanProgress.errors) errors"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text(model.scanProgress.currentPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer()
            if model.scanProgress.state == .paused {
                Button(model.text("再開", "Resume"), action: model.resumeScan)
            } else {
                Button(model.text("一時停止", "Pause"), action: model.pauseScan)
            }
            Button(model.text("キャンセル", "Cancel"), role: .destructive, action: model.cancelScan)
        }
        .font(.caption)
        .padding(8)
        .background(.bar)
    }

    private var importStatus: some View {
        HStack(spacing: 12) {
            let overallProgress: Double = {
                guard model.importProgress.totalFiles > 0 else { return 0.0 }
                let completedFiles = Double(max(0, model.importProgress.currentFileIndex - 1))
                let currentFileProgress = model.importProgress.state == .moving ? 1.0 : model.importProgress.fileProgress
                return (completedFiles + currentFileProgress) / Double(model.importProgress.totalFiles)
            }()
            
            ProgressView(value: overallProgress)
                .progressViewStyle(.linear)
                .frame(width: 80)
            
            let statusText: String = {
                switch model.importProgress.state {
                case .converting:
                    let percentStr = String(format: "%.0f%%", model.importProgress.fileProgress * 100)
                    return model.text(
                        "MP3に変換中... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles)) \(percentStr)",
                        "Converting... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles)) \(percentStr)"
                    )
                case .moving:
                    return model.text(
                        "保存中... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles))",
                        "Saving... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles))"
                    )
                case .completed:
                    return model.text("取り込み完了", "Import completed")
                case .failed(let err):
                    return model.text("エラー: \(err)", "Error: \(err)")
                case .idle:
                    return ""
                }
            }()
            
            Text(statusText)
            
            Text(model.importProgress.currentFileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .font(.caption)
        .padding(8)
        .background(.bar)
    }

    private var headerTitle: String {
        if let id = model.selectedPlaylistID, let playlist = model.playlists.first(where: { $0.id == id }) { return playlist.name }
        if let album = model.selectedAlbum { return album.name }
        if let artist = model.selectedArtist { return model.displayArtist(artist.name) }
        if let genre = model.selectedGenre { return genre }
        if let filter = model.exactMetadataFilter { return filter.value }
        return model.sectionTitle(model.section)
    }

    private func icon(for section: LibrarySection) -> String {
        switch section {
        case .tracks: "music.note"
        case .history: "clock.arrow.circlepath"
        case .recentlyAdded: "clock.fill"
        case .upNext: "text.line.first.and.arrowtriangle.forward"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .genres: "guitars"
        case .playlists: "music.note.list"
        case .folders: "folder"
        case .favorites: "star.fill"
        case .cache: "internaldrive.fill"
        case .settings: "gearshape"
        case .activityLog: "doc.text.magnifyingglass"
        case .diagnostics: "stethoscope"
        }
    }

    private func sidebarCount(for section: LibrarySection) -> String? {
        switch section {
        case .cache: return model.cachedTrackCount.formatted()
        case .tracks: return model.libraryTrackCount.formatted()
        case .history: return model.recentlyPlayedTrackCount.formatted()
        case .albums: return model.libraryAlbumCount.formatted()
        case .artists: return model.libraryArtistCount.formatted()
        case .genres: return model.libraryGenreCount.formatted()
        case .folders: return model.libraryFolderCount.formatted()
        case .favorites: return model.favoriteTrackCount.formatted()
        case .upNext: return player.upNextTracks.count.formatted()
        case .recentlyAdded: return model.recentlyAddedTrackCount.formatted()
        default:
            return nil
        }
    }

    private func activityKindTitle(_ kind: LibraryActivityKind) -> String {
        switch kind {
        case .added: model.text("ファイル追加", "File Added")
        case .addedToCache: model.text("キャッシュに追加", "Added to Cache")
        case .addedToMainStorage: model.text("メイン保管先に追加", "Added to Main Storage")
        case .fileModified: model.text("ファイル情報を更新", "File Info Updated")
        case .metadataChanged: model.text("曲情報を編集", "Metadata Edited")
        case .unavailable: model.text("ファイルが見つかりません", "File Unavailable")
        case .restored: model.text("ファイルを再検出", "File Restored")
        case .removedFromLibrary: model.text("リストから削除", "Removed from Library")
        case .movedToTrash: model.text("ファイルをゴミ箱へ移動", "File Moved to Trash")
        }
    }

    private func activityKindIcon(_ kind: LibraryActivityKind) -> String {
        switch kind {
        case .added: "plus.circle.fill"
        case .addedToCache: "internaldrive.fill"
        case .addedToMainStorage: "externaldrive.fill.badge.plus"
        case .fileModified, .metadataChanged: "pencil.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .restored: "arrow.clockwise.circle.fill"
        case .removedFromLibrary: "minus.circle.fill"
        case .movedToTrash: "trash.circle.fill"
        }
    }

    private func activityKindColor(_ kind: LibraryActivityKind) -> Color {
        switch kind {
        case .added, .restored: .green
        case .addedToCache: .cyan
        case .addedToMainStorage: .mint
        case .fileModified, .metadataChanged: .blue
        case .unavailable: .orange
        case .removedFromLibrary, .movedToTrash: .red
        }
    }

    private func activityFieldTitle(_ field: String) -> String {
        switch field {
        case "title": model.text("タイトル", "Title")
        case "artist": model.text("アーティスト", "Artist")
        case "album": model.text("アルバム", "Album")
        case "album_artist": model.text("アルバムアーティスト", "Album Artist")
        case "genre": model.text("ジャンル", "Genre")
        case "disc_number": model.text("ディスク番号", "Disc Number")
        case "track_number": model.text("トラック番号", "Track Number")
        case "file_size": model.text("ファイルサイズ", "File Size")
        case "modified_at": model.text("更新日時", "Modified Date")
        case "relative_path": model.text("相対パス", "Relative Path")
        case "filename": model.text("ファイル名", "Filename")
        case "format": model.text("形式", "Format")
        case "bitrate": model.text("ビットレート", "Bitrate")
        case "has_artwork": model.text("ジャケット", "Artwork")
        default: field
        }
    }

    private func diagnosticTitle(_ kind: MetadataIssueKind) -> String {
        switch kind {
        case .missingTitle: model.text("曲名なし", "Missing Title")
        case .missingArtist: model.text("不明なアーティスト", "Unknown Artist")
        case .missingAlbum: model.text("アルバム名なし", "Missing Album")
        case .missingYear: model.text("リリース年なし", "Missing Release Year")
        case .urlInMP3Metadata: model.text("URLを含むMP3", "MP3 Metadata URLs")
        case .commentInMP3: model.text("💬 コメントを含むMP3", "MP3 Comments")
        case .suspectedMojibake: model.text("文字化け候補", "Garbled Text Candidates")
        case .duplicateTracks: model.text("重複曲", "Duplicate Tracks")
        case .suspectedVariations: model.text("表記ゆれ候補", "Variation Candidates")
        case .corruptedOrEmpty: model.text("破損・未再生可能", "Corrupted / Unplayable")
        }
    }

    private func diagnosticIcon(_ kind: MetadataIssueKind) -> String {
        switch kind {
        case .missingTitle: "music.note"
        case .missingArtist: "person.crop.circle.badge.questionmark"
        case .missingAlbum: "square.stack.3d.up.slash"
        case .missingYear: "calendar.badge.exclamationmark"
        case .urlInMP3Metadata: "link.badge.plus"
        case .commentInMP3: "bubble.left.and.text.bubble.right"
        case .suspectedMojibake: "text.badge.exclamationmark"
        case .duplicateTracks: "square.2.layers.3d"
        case .suspectedVariations: "text.magnifyingglass"
        case .corruptedOrEmpty: "exclamationmark.triangle.fill"
        }
    }

    private func diagnosticCount(_ kind: MetadataIssueKind) -> Int {
        model.diagnosticSummaries.first(where: { $0.kind == kind })?.count ?? 0
    }

    private var showsTrackColumns: Bool {
        if model.section == .settings || model.section == .activityLog || model.section == .upNext { return false }
        if model.section == .diagnostics { return model.diagnosticKind != .suspectedVariations }
        if model.selectedAlbum != nil || model.selectedArtist?.name.isEmpty == true { return true }
        if model.selectedGenre != nil { return model.genreDetailMode == .tracks }
        return ![.albums, .artists, .genres, .folders].contains(model.section)
    }

    private var trackContentWidth: Double {
        var width = 46.0 // outer padding and the persistent favorite/action column
        if isDuplicateSelectionMode { width += 38 }
        var visibleColumns = 0
        if isTitleColumnVisible { width += titleColumnWidth; visibleColumns += 1 }
        if isArtistColumnVisible { width += artistColumnWidth; visibleColumns += 1 }
        if isAlbumColumnVisible { width += albumColumnWidth; visibleColumns += 1 }
        if isGenreColumnVisible { width += genreColumnWidth; visibleColumns += 1 }
        if isYearColumnVisible { width += yearColumnWidth; visibleColumns += 1 }
        if isDiscNumberColumnVisible { width += discNumberColumnWidth; visibleColumns += 1 }
        if isTrackNumberColumnVisible { width += trackNumberColumnWidth; visibleColumns += 1 }
        if isDurationColumnVisible { width += durationColumnWidth; visibleColumns += 1 }
        if isFormatColumnVisible { width += 55; visibleColumns += 1 }
        if isAddedDateColumnVisible { width += addedDateColumnWidth; visibleColumns += 1 }
        return width + Double(visibleColumns) * 8
    }

    private func columnVisibilityButton(_ title: String, isVisible: Binding<Bool>) -> some View {
        Button {
            isVisible.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: isVisible.wrappedValue ? "checkmark" : "")
        }
    }

    private func metadataFieldTitle(_ field: MetadataField) -> String {
        switch field {
        case .title: model.text("曲名", "Title")
        case .artist: model.text("アーティスト", "Artist")
        case .album: model.text("アルバム", "Album")
        case .genre: model.text("ジャンル", "Genre")
        case .comment: model.text("コメント", "Comment")
        }
    }

    private func variationReason(_ candidate: MetadataVariationCandidate) -> String {
        switch candidate.reason {
        case .normalization: model.text("全角・半角／空白／大文字小文字", "Width, spacing, or case")
        case .likelyTypo: model.text("タイプミスの可能性（距離 \(candidate.editDistance)）", "Possible typo (distance \(candidate.editDistance))")
        }
    }

    private func variationChoiceRow(
        value: String,
        count: Int,
        candidate: MetadataVariationCandidate,
        onInspect: @escaping () -> Void
    ) -> some View {
        let isThisActionRunning = model.batchMetadataProgress.state == .running
            && model.activeStandardizingCandidateID == candidate.id
            && model.activeStandardizingTargetValue == value

        return HStack(spacing: 10) {
            Button("\(value)  (\(count.formatted()))", action: onInspect)
                .buttonStyle(.link)
                .lineLimit(1)

            if isThisActionRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.text(
                        "統一中… \(model.batchMetadataProgress.processed)/\(model.batchMetadataProgress.total)曲 (\(Int(Double(model.batchMetadataProgress.processed) / Double(max(1, model.batchMetadataProgress.total)) * 100))%)",
                        "Updating… \(model.batchMetadataProgress.processed)/\(model.batchMetadataProgress.total) songs (\(Int(Double(model.batchMetadataProgress.processed) / Double(max(1, model.batchMetadataProgress.total)) * 100))%)"
                    ))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            } else {
                Button(model.text("この表記に統一", "Use This Spelling")) {
                    model.standardizeVariation(candidate, choosing: value)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.batchMetadataProgress.state == .running)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func formatAddedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func trackDragPayload(for track: Track) -> String {
        let ids: [Int64]
        if model.selectedTrackIDs.contains(track.id) {
            ids = selectedTracksOnPage.map(\.id)
        } else {
            ids = [track.id]
        }
        return "vibe-track-ids:" + ids.map(String.init).joined(separator: ",")
    }

    private func parseTrackDragPayload(_ payload: String) -> [Int64] {
        let prefix = "vibe-track-ids:"
        guard payload.hasPrefix(prefix) else { return [] }
        return payload.dropFirst(prefix.count).split(separator: ",").compactMap { Int64($0) }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider], playlistID: Int64? = nil) {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        } else if let path = String(data: data, encoding: .utf8), let url = URL(string: path) {
                            urls.append(url)
                        }
                    } else if let url = item as? URL {
                        urls.append(url)
                    }
                    group.leave()
                }
            } else {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                model.importURLs(urls, toPlaylist: playlistID)
            }
        }
    }
}

private struct LibrarySearchField: View {
    @ObservedObject var model: LibraryViewModel
    @FocusState.Binding var isFocused: Bool
    var isFlexible = false

    @ViewBuilder
    var body: some View {
        if isFlexible {
            searchField
                .frame(minWidth: 120, maxWidth: .infinity)
        } else {
            searchField
                .frame(minWidth: 140, idealWidth: 200, maxWidth: 260)
        }
    }

    private var searchField: some View {
        let isSearching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let accent = model.appearance.palette.accent

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearching ? accent : Color.secondary)
                .font(.system(size: 13, weight: isSearching ? .bold : .regular))
                .accessibilityHidden(true)
            let searchPlaceholder = switch model.section {
            case .tracks: model.text("曲名を検索…", "Search song titles…")
            case .albums: model.text("アルバムを検索…", "Search albums…")
            case .artists: model.text("アーティストを検索…", "Search artists…")
            case .genres: model.text("ジャンルを検索…", "Search genres…")
            case .cache: model.text("キャッシュ内を検索…", "Search cache…")
            default: model.text("検索…", "Search…")
            }
            TextField(
                searchPlaceholder,
                text: $model.searchText
            )
            .textFieldStyle(.plain)
            .focused($isFocused)
            .help(model.text("検索（AND / OR / -除外 / \"フレーズ\" / /正規表現/）", "Search (AND / OR / -exclude / \"phrase\" / /regex/)"))
            .onChange(of: model.searchText) { _, _ in model.searchChanged() }

            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
                .opacity(model.isSearchInProgress ? 1 : 0)
                .accessibilityHidden(!model.isSearchInProgress)
                .accessibilityLabel(model.text("検索中", "Searching"))

            if isSearching {
                Button(action: model.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(model.text("検索を解除してすべて表示", "Clear search and show all"))
                .accessibilityLabel(model.text("検索内容を消去", "Clear Search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSearching ? accent.opacity(model.appearance.isDark ? 0.12 : 0.07) : model.appearance.palette.elevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSearching ? accent : model.appearance.palette.divider, lineWidth: isSearching ? 1.5 : 1)
        }
        .shadow(
            color: isSearching ? accent.opacity(model.appearance.isDark ? 0.45 : 0.28) : Color.clear,
            radius: isSearching ? 5 : 0,
            x: 0,
            y: 0
        )
        .animation(.easeInOut(duration: 0.18), value: isSearching)
        .animation(.easeInOut(duration: 0.15), value: model.isSearchInProgress)
        .help(model.text(
            "検索構文:\n• 単語をスペース区切りで AND 検索 (kiss me)\n• \"フレーズ\" で語順完全一致 (\"kiss me\")\n• OR または | でいずれか一致 (kiss OR love)\n• - または NOT で除外 (kiss -live)\n• artist:, album:, title:, genre: で項目限定\n• /パターン/ または regex: で正規表現 (/^A.*Kiss/i)",
            "Search Syntax:\n• Space-separated terms for AND (kiss me)\n• \"phrase\" for exact phrase (\"kiss me\")\n• OR or | for either match (kiss OR love)\n• - or NOT to exclude (kiss -live)\n• artist:, album:, title:, genre: to target field\n• /pattern/ or regex: for regular expression (/^A.*Kiss/i)"
        ))
    }
}

private struct TrackSortHeader: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var titleWidth: Double
    @Binding var artistWidth: Double
    @Binding var albumWidth: Double
    @Binding var genreWidth: Double
    @Binding var yearWidth: Double
    @Binding var discNumberWidth: Double
    @Binding var trackNumberWidth: Double
    @Binding var durationWidth: Double
    @Binding var addedDateWidth: Double
    let showSelectionCheckbox: Bool
    let showCommentAction: Bool
    let columns: [TrackSort]
    let moveColumn: (TrackSort, TrackSort) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showSelectionCheckbox {
                Color.clear.frame(width: 30)
            }
            if showCommentAction {
                Color.clear.frame(width: 30)
            }
            Color.clear.frame(width: 30)
            ForEach(columns) { column in
                columnHeader(column)
                    .tableColumnDivider()
                    .draggable(column.rawValue)
                    .dropDestination(for: String.self) { values, _ in
                        guard let rawValue = values.first,
                              let source = TrackSort(rawValue: rawValue),
                              columns.contains(source) else { return false }
                        moveColumn(source, column)
                        return true
                    }
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder private func columnHeader(_ column: TrackSort) -> some View {
        switch column {
        case .title:
            header(.title).frame(width: titleWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $titleWidth, range: 80...500) }
        case .artist:
            header(.artist).frame(width: artistWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $artistWidth, range: 80...420) }
        case .album:
            header(.album).frame(width: albumWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $albumWidth, range: 80...500) }
        case .genre:
            header(.genre).frame(width: genreWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $genreWidth, range: 70...300) }
        case .year:
            header(.year).frame(width: yearWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $yearWidth, range: 68...140) }
        case .discNumber:
            header(.discNumber).frame(width: discNumberWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $discNumberWidth, range: 64...160) }
        case .trackNumber:
            header(.trackNumber).frame(width: trackNumberWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $trackNumberWidth, range: 64...170) }
        case .duration:
            header(.duration).frame(width: durationWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $durationWidth, range: 50...140) }
        case .format:
            header(.format).frame(width: 55, alignment: .leading)
        case .dateAdded:
            header(.dateAdded).frame(width: addedDateWidth, alignment: .leading)
                .overlay(alignment: .trailing) { ColumnResizeHandle(width: $addedDateWidth, range: 90...240) }
        case .path:
            EmptyView()
        }
    }

    private func header(_ sort: TrackSort) -> some View {
        let isActive = model.sort == sort
        return Button {
            model.sortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(model.sortTitle(sort))
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }
}

private struct TableColumnDividerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }
}

private extension View {
    func tableColumnDivider() -> some View {
        modifier(TableColumnDividerModifier())
    }
}

private struct ColumnResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 1)
            .frame(width: 9, height: 22)
            .contentShape(Rectangle())
            .offset(x: 4)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let proposed = (dragStartWidth ?? width) + value.translation.width
                        width = min(range.upperBound, max(range.lowerBound, proposed))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .help("Drag to resize column")
    }
}

private struct PlayerArtwork: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholderPointSize: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: placeholderPointSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: artworkURL) {
            image = artworkURL.flatMap(NSImage.init(contentsOf:))
        }
    }
}

private struct UpNextLibraryView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.text("次に再生する曲（\(player.queueTotalCount.formatted())曲）", "Up Next (\(player.queueTotalCount.formatted()) songs)"))
                    .font(.headline)
                Spacer()
                Button(model.text("すべて消去", "Clear All"), role: .destructive, action: player.clearUpNext)
                    .disabled(player.queueTotalCount == 0)
            }
            .padding(14)
            Divider()
            if player.queueTotalCount == 0 {
                ContentUnavailableView(
                    model.text("次に再生する曲はありません", "Nothing Up Next"),
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    description: Text(model.text("曲を右クリックして「次に再生」を選ぶと、ここに追加されます。", "Right-click a song and add it to Up Next."))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.upNextTracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 28)
                                Button { player.playQueued(track) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Text(track.album).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 240, alignment: .leading)
                                Button { player.removeFromUpNext(track) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 14).frame(height: 46)
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button(model.text("前へ", "Previous"), action: player.previousQueuePage).disabled(!player.canGoToPreviousQueuePage)
                Spacer()
                Text(model.text("ページ \(player.queuePageNumber) / \(player.queuePageCount)", "Page \(player.queuePageNumber) / \(player.queuePageCount)"))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button(model.text("次へ", "Next"), action: player.nextQueuePage).disabled(!player.canGoToNextQueuePage)
            }
            .padding(10)
        }
    }
}

private struct InspectorDivider: View {
    @Binding var inspectorWidth: Double
    let helpText: String
    let accessibilityText: String
    @State private var isHovered = false
    @State private var dragStartWidth: Double?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Capsule()
                .fill(isHovered || dragStartWidth != nil
                    ? Color.accentColor
                    : Color.secondary.opacity(0.45))
                .frame(width: 4.5, height: 60)
                .overlay {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color.white.opacity(0.85)).frame(width: 2, height: 2)
                        }
                    }
                }
        }
        .frame(width: 14)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartWidth ?? inspectorWidth
                    dragStartWidth = start
                    let dragDistance = value.startLocation.x - value.location.x
                    inspectorWidth = min(600, max(260, start + dragDistance))
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .onTapGesture(count: 2) { inspectorWidth = 310 }
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }
}

private struct NowPlayingInspector: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    @ObservedObject private var progress: PlaybackController.Progress
    @Binding var isMiniPlayer: Bool
    @Binding var browserURL: URL?
    let openAISettings: () -> Void
    @State private var tab = 0
    @State private var showStatsView = false
    @AppStorage("lyrics.autoScroll") private var lyricsAutoScroll = true
    @AppStorage("discovery.displayCount") private var discoveryDisplayCount = 15
    @State private var isEditingManualLyrics = false
    @State private var tabSearchInstrument = "guitar"

    init(model: LibraryViewModel, player: PlaybackController, isMiniPlayer: Binding<Bool>, browserURL: Binding<URL?>, openAISettings: @escaping () -> Void) {
        self.model = model
        self.player = player
        self._progress = ObservedObject(wrappedValue: player.progress)
        self._isMiniPlayer = isMiniPlayer
        self._browserURL = browserURL
        self.openAISettings = openAISettings
    }

    private struct DisplayLyricLine: Identifiable {
        let id: Int
        let text: String
        let time: Double?
    }

    var body: some View {
        VStack(spacing: 0) {
            InspectorPlayerControls(player: player, model: model, isMiniPlayer: $isMiniPlayer)
            Divider()

            Group {
                if let browserURL {
                    EmbeddedBrowserView(
                        url: browserURL,
                        targetLanguage: model.language.rawValue,
                        autoTranslate: browserAutoTranslateBinding
                    ) {
                        self.browserURL = nil
                        if tab == 5 { tab = 0 }
                    }
                } else {
                    playerInformation
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(model.appearance.palette.inspector)
    }

    private var browserAutoTranslateBinding: Binding<Bool> {
        Binding(
            get: { model.autoTranslateExternalArticles },
            set: { enabled in
                model.autoTranslateExternalArticles = enabled
                model.savePresentationSettings()
            }
        )
    }

    @ViewBuilder private var playerInformation: some View {
        if player.currentTrack == nil {
            idleDiscovery
        } else {
            GeometryReader { geo in
                VStack(spacing: 10) {
                    inspectorTabBar(availableWidth: geo.size.width)

                    Group {
                        if showStatsView {
                            idleDiscovery
                        } else if model.isEnriching {
                            ProgressView(model.text("情報を取得中…", "Loading information…"))
                        } else if tab == 0 {
                            information
                        } else if tab == 1 {
                            lyrics
                        } else if tab == 2 {
                            discovery
                        } else if tab == 3 {
                            practice
                        } else if tab == 4 {
                            tabSearch
                        } else {
                            ProgressView(model.text("コードを検索中…", "Searching for chords…"))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: tab) { _, newTab in
                if newTab == 5 {
                    browserURL = chordifySearchURL
                }
            }
            .sheet(isPresented: $isEditingManualLyrics) {
                if let track = player.currentTrack {
                    ManualLyricsEditor(
                        model: model,
                        track: track,
                        initialLyrics: model.enrichedInfo?.lyrics?.plainLyrics ?? ""
                    )
                }
            }
        }
    }

    private func inspectorTabBar(availableWidth: CGFloat) -> some View {
        let isNarrow = availableWidth < 360
        let currentSelection: Int = showStatsView ? 6 : tab

        return VStack(spacing: 3) {
            if isNarrow {
                // 2段レイアウト（上段: 4項目 / 下段: 3項目）
                HStack(spacing: 3) {
                    tabItemButton(index: 0, current: currentSelection)
                    tabItemButton(index: 1, current: currentSelection)
                    tabItemButton(index: 2, current: currentSelection)
                    tabItemButton(index: 3, current: currentSelection)
                }
                HStack(spacing: 3) {
                    tabItemButton(index: 4, current: currentSelection)
                    tabItemButton(index: 5, current: currentSelection)
                    tabItemButton(index: 6, current: currentSelection)
                }
            } else {
                // 1段レイアウト
                HStack(spacing: 3) {
                    tabItemButton(index: 0, current: currentSelection)
                    tabItemButton(index: 1, current: currentSelection)
                    tabItemButton(index: 2, current: currentSelection)
                    tabItemButton(index: 3, current: currentSelection)
                    tabItemButton(index: 4, current: currentSelection)
                    tabItemButton(index: 5, current: currentSelection)
                    tabItemButton(index: 6, current: currentSelection, isIconOnly: true)
                }
            }
        }
        .padding(3)
        .background(model.appearance.palette.elevated, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(model.appearance.palette.divider, lineWidth: 1))
    }

    @ViewBuilder
    private func tabItemButton(index: Int, current: Int, isIconOnly: Bool = false) -> some View {
        let isSelected = current == index
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                if index == 6 {
                    showStatsView = true
                } else {
                    showStatsView = false
                    tab = index
                }
            }
        } label: {
            Group {
                if isIconOnly {
                    Text("📊")
                } else {
                    switch index {
                    case 0: Text(model.text("情報", "Info")).tag(0)
                    case 1: Text(model.text("歌詞", "Lyrics")).tag(1)
                    case 2: Text(model.text("発見", "Discover")).tag(2)
                    case 3: Text(model.text("練習", "Practice")).tag(3)
                    case 4: Text("TAB").tag(4)
                    case 5: Text(model.text("コード", "Chords")).tag(5)
                    default: Text(model.text("📊 統計", "📊 Stats")).tag(6)
                    }
                }
            }
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? Color.white : model.appearance.palette.secondaryText)
            .frame(maxWidth: isIconOnly ? 32 : .infinity)
            .frame(height: 22)
            .background(
                isSelected ? model.appearance.palette.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private var chordifySearchURL: URL? {
        guard let track = player.currentTrack else { return nil }
        let query = [track.artist, track.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return URL(string: "https://chordify.net/en") }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://chordify.net/search/\(encoded)")
    }

    private var youtubeTabSearchURL: URL? {
        guard let track = player.currentTrack else { return nil }
        let query = [track.title, track.artist, "tab", tabSearchInstrument]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components?.url
    }

    private var tabSearch: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.text("TAB動画を探す", "Find TAB Videos"), systemImage: "play.rectangle.fill")
                .font(.headline)
            Text(model.text(
                "曲名・アーティスト名に「tab」と選んだ楽器を加えてYouTubeを検索します。",
                "Search YouTube using the title, artist, “tab”, and your selected instrument."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker(model.text("楽器", "Instrument"), selection: $tabSearchInstrument) {
                Text("guitar").tag("guitar")
                Text("bass").tag("bass")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                browserURL = youtubeTabSearchURL
            } label: {
                Label(model.text("YouTubeでTABを検索", "Search TAB on YouTube"), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(youtubeTabSearchURL == nil)

            if let track = player.currentTrack {
                Text("\(track.title)  ·  \(track.artist)  ·  tab  ·  \(tabSearchInstrument)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var idleDiscovery: some View {
        IdleListeningInsightsView(model: model, player: player)
    }

    private var lyrics: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Toggle(isOn: $lyricsAutoScroll) {
                    Label(model.text("自動スクロール", "Auto Scroll"), systemImage: "arrow.up.and.down.text.horizontal")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .tint(.accentColor)
                .opacity(lyricsAutoScroll ? 1.0 : 0.4)
            }
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(displayLyricLines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(line.id == activeLyricLineIndex ? Color.primary : Color.secondary)
                                .fontWeight(line.id == activeLyricLineIndex ? .semibold : .regular)
                                .id(line.id)
                        }

                        if player.currentTrack != nil {
                            Button {
                                isEditingManualLyrics = true
                            } label: {
                                Label(
                                    model.enrichedInfo?.lyrics?.plainLyrics == nil
                                        ? model.text("歌詞を手動で登録…", "Add Lyrics Manually…")
                                        : model.text("歌詞を編集…", "Edit Lyrics…"),
                                    systemImage: "square.and.pencil"
                                )
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 12)
                        }
                        Color.clear.frame(height: 80)
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: activeLyricLineIndex) { _, index in
                    guard lyricsAutoScroll, displayLyricLines.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onChange(of: model.enrichedInfo?.lyrics?.plainLyrics) { _, _ in
                    proxy.scrollTo(0, anchor: .top)
                }
            }
        }
    }

    private var displayLyricLines: [DisplayLyricLine] {
        if let synced = model.enrichedInfo?.lyrics?.syncedLyrics,
           !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = synced.components(separatedBy: .newlines).compactMap(parseSyncedLyricLine)
            if !parsed.isEmpty { return parsed.enumerated().map { DisplayLyricLine(id: $0.offset, text: $0.element.text, time: $0.element.time) } }
        }
        let text = model.enrichedInfo?.lyrics?.plainLyrics ?? model.text(
            "歌詞が見つかりませんでした。LRCLIBで一致した歌詞は自動保存され、次回はオフラインで表示されます。",
            "No matching lyrics were found. LRCLIB matches are saved for offline viewing."
        )
        return text.components(separatedBy: .newlines).enumerated().map {
            DisplayLyricLine(id: $0.offset, text: $0.element, time: nil)
        }
    }

    private var activeLyricLineIndex: Int {
        let lines = displayLyricLines
        guard !lines.isEmpty else { return 0 }
        if lines.contains(where: { $0.time != nil }) {
            return lines.last(where: { ($0.time ?? .greatestFiniteMagnitude) <= player.elapsed })?.id ?? 0
        }
        guard player.duration > 0 else { return 0 }
        return min(lines.count - 1, max(0, Int((player.elapsed / player.duration) * Double(lines.count))))
    }

    private func parseSyncedLyricLine(_ raw: String) -> (time: Double, text: String)? {
        guard raw.first == "[", let close = raw.firstIndex(of: "]") else { return nil }
        let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
        guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
        return (minutes * 60 + seconds, String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces))
    }


    private var discovery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text("ライブラリ内の似た曲", "Similar Songs in Your Library"))
                        .font(.headline)
                    Text(model.text("似た曲調で、まだあまり聴いていない曲", "Similar style, undiscovered gems"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Picker(
                    model.text("表示件数", "Count"),
                    selection: $discoveryDisplayCount
                ) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { count in
                        Text(model.text("\(count)曲", "\(count) songs")).tag(count)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .fixedSize()
                .labelsHidden()

                if let current = player.currentTrack {
                    Button {
                        model.enrich(current)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(model.text("別の曲を再発見", "Discover other songs"))
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.similarTracks.prefix(discoveryDisplayCount)) { track in
                        HStack(spacing: 8) {
                            Button {
                                player.play(track)
                                tab = 0
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text("\(track.artist) • \(track.genre.isEmpty ? track.album : track.genre)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button { player.addToUpNext(track) } label: {
                                Image(systemName: "text.badge.plus")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(model.text("次に再生へ追加", "Add to Up Next"))
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private var practice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "metronome")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BPM").font(.caption.bold()).foregroundStyle(.secondary)
                        if let bpm = player.currentBPM {
                            Text("\(Int(bpm.rounded()))")
                                .font(.title2.bold().monospacedDigit())
                        } else if player.isAnalyzingBPM {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(model.text("自動解析中…", "Analyzing…"))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(model.text("取得できません", "Unavailable"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(model.text("音源タグを優先し、未登録なら音声から推定します", "Uses the audio tag first, then estimates from audio"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 8) {
                    Label(model.text("区間リピート", "Section Loop"), systemImage: "repeat")
                        .font(.headline)
                    Text(model.text(
                        "3つの区間を曲ごとに保存し、アプリを終了しても保持します。ソロの開始位置でA、終了位置でBを押してください。",
                        "Save three loops for each song, even after quitting the app. Set A at the start of a solo and B at the end."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Picker(
                        model.text("練習区間", "Practice Loop"),
                        selection: Binding(
                            get: { player.activeSectionLoopSlot },
                            set: { player.selectSectionLoopSlot($0) }
                        )
                    ) {
                        ForEach(0..<PlaybackController.sectionLoopSlotCount, id: \.self) { slot in
                            Text(sectionLoopSlotTitle(slot)).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(model.text("保存する区間", "Saved Loop Slot"))

                    HStack(spacing: 7) {
                        practiceActionButton(
                            title: model.text("A 開始", "Set A"),
                            systemImage: "a.circle",
                            action: player.setSectionLoopStart
                        )
                        practiceActionButton(
                            title: model.text("B 終了", "Set B"),
                            systemImage: "b.circle",
                            action: player.setSectionLoopEnd
                        )
                        .disabled(!player.canSetSectionLoopEnd)
                        practiceActionButton(
                            title: model.text("解除", "Clear"),
                            systemImage: "xmark.circle",
                            action: player.clearSectionLoop
                        )
                        .disabled(player.sectionLoopStart == nil)
                    }

                    if let start = player.sectionLoopStart {
                        HStack(spacing: 8) {
                            Text("A  \(formatPracticeTime(start))")
                            Image(systemName: "arrow.right")
                            if let end = player.sectionLoopEnd {
                                Text("B  \(formatPracticeTime(end))")
                            } else {
                                Text(model.text("B 未設定", "B not set"))
                            }
                            Spacer()
                        }
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(player.sectionLoopEnd == nil ? Color.secondary : Color.accentColor)
                    }

                    Toggle(
                        model.text("区間リピート", "Section Loop"),
                        isOn: Binding(
                            get: { player.isSectionLoopEnabled },
                            set: { _ in player.toggleSectionLoop() }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(player.sectionLoopEnd == nil)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label(model.text("再生速度", "Playback Speed"), systemImage: "gauge.with.dots.needle.67percent")
                        .font(.headline)
                    Text(model.text(
                        "音程を保ったまま、ギター練習に合わせてゆっくり再生します。",
                        "Slow playback for practice while preserving the original pitch."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                        ForEach(PlaybackController.supportedSpeeds, id: \.self) { speed in
                            practiceButton(
                                title: "\(Int((speed * 100).rounded()))%",
                                isSelected: player.playbackSpeed == speed
                            ) {
                                player.setPlaybackSpeed(speed)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label(model.text("ピッチ", "Pitch"), systemImage: "music.note.list")
                        .font(.headline)
                    Text(model.text(
                        "速度は変えず、原曲より半音下げ／半音上げで再生します。",
                        "Keep the selected speed and play one semitone below or above the original."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        practiceButton(
                            title: model.text("半音下げ", "-1 semitone"),
                            isSelected: player.pitchSemitones == -1
                        ) { player.setPitchSemitones(-1) }
                        practiceButton(
                            title: model.text("原音", "Original"),
                            isSelected: player.pitchSemitones == 0
                        ) { player.setPitchSemitones(0) }
                        practiceButton(
                            title: model.text("半音上げ", "+1 semitone"),
                            isSelected: player.pitchSemitones == 1
                        ) { player.setPitchSemitones(1) }
                    }
                }

                Label(
                    practiceStatus,
                    systemImage: player.pitchSemitones == 0 ? "speedometer" : "tuningfork"
                )
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
        }
        .task(id: player.currentTrack?.id) {
            player.requestCurrentTrackBPM()
        }
    }

    private func sectionLoopSlotTitle(_ slot: Int) -> String {
        let savedMark = player.sectionLoopIsConfigured(at: slot) ? " •" : ""
        return "\(slot + 1)\(savedMark)"
    }

    private func practiceButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func practiceActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func formatPracticeTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d.%01d", Int(seconds) / 60, Int(seconds) % 60, Int(seconds * 10) % 10)
    }

    private var practiceStatus: String {
        let speed = Int((player.playbackSpeed * 100).rounded())
        let pitchJA = switch player.pitchSemitones {
        case -1: "半音下げ"
        case 1: "半音上げ"
        default: "原音"
        }
        let pitchEN = switch player.pitchSemitones {
        case -1: "-1 semitone"
        case 1: "+1 semitone"
        default: "original pitch"
        }
        return model.text(
            "現在: 速度\(speed)%・\(pitchJA)",
            "Current: \(speed)% speed, \(pitchEN)"
        )
    }

    private var information: some View {
        Group {
            if let track = player.currentTrack {
                CurrentTrackInfoEditorView(model: model, player: player, track: track, browserURL: $browserURL, openAISettings: openAISettings)
            } else {
                ContentUnavailableView(
                    model.text("曲情報がありません", "No Track Info"),
                    systemImage: "info.circle",
                    description: Text(model.text("再生中の曲がありません。", "No song is currently playing."))
                )
            }
        }
    }
}


private struct CurrentTrackInfoEditorView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    let track: Track
    @Binding var browserURL: URL?
    let openAISettings: () -> Void

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var albumArtist: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""
    @State private var discNumber: String = ""
    @State private var trackNumber: String = ""

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var saveSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Editable Fields
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("基本情報", "Basic Info")).font(.headline)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("曲名", "Title")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("曲名", "Title"), text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アーティスト", "Artist")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アーティスト", "Artist"), text: $artist)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アルバム", "Album")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アルバム", "Album"), text: $album)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アルバムアーティスト", "Album Artist")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アルバムアーティスト", "Album Artist"), text: $albumArtist)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("ジャンル", "Genre")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("ジャンル", "Genre"), text: $genre)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("リリース年", "Release Year")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("リリース年 (例: 2024)", "Release Year (e.g. 2024)"), text: $year)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("ディスク番号", "Disc #")).font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $discNumber)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("トラック番号", "Track #")).font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $trackNumber)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                // Save button & status
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(action: saveChanges) {
                            if isSaving {
                                ProgressView().controlSize(.small).padding(.trailing, 4)
                            }
                            Text(model.text("ファイルへ保存", "Save to File"))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges || isSaving || !numbersAreValid)
                        
                        if saveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                                .transition(.opacity)
                        }
                    }
                    
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                
                Divider()
                
                // Read-Only Specs
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("ファイル仕様", "File Specifications")).font(.headline)
                    LabeledContent(model.text("形式", "Format"), value: track.format.uppercased())
                    if let bitrate = track.bitrate {
                        LabeledContent(model.text("ビットレート", "Bitrate"), value: "\(bitrate) kbps")
                    }
                    LabeledContent(model.text("再生時間", "Duration"), value: formatDuration(track.duration))
                    LabeledContent(model.text("ファイルサイズ", "File Size"), value: ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("ファイル名", "Filename")).font(.caption).foregroundStyle(.secondary)
                        Text(track.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(track.filename)
                        
                        Text(model.text("相対パス", "Relative Path")).font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(track.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(track.relativePath)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
                
                Divider()
                
                // Navigation/Search Buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("関連リンク", "Related Links")).font(.headline)
                    HStack(spacing: 8) {
                        Button(model.text("Wikipedia", "Wikipedia")) { browserURL = model.enrichedInfo?.wikipediaURL }
                            .disabled(model.enrichedInfo?.wikipediaURL == nil)
                        Button(model.text("ニュース", "News")) {
                            browserURL = model.newsURL(for: track.artist)
                        }.disabled(track.artist.isEmpty)
                        Button(model.text("YouTube", "YouTube")) {
                            browserURL = model.youtubeURL(for: track)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(model.text("Wikipedia (アルバム)", "Wikipedia (Album)")) {
                            browserURL = model.albumWikipediaURL(for: track)
                        }.disabled(track.album.isEmpty)
                        Button(model.text("Google (アルバム)", "Google (Album)")) {
                            browserURL = model.albumGoogleURL(for: track)
                        }.disabled(track.album.isEmpty)
                    }
                }
                
                Divider()
                
                // AI Suggestions
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("AIジャンル候補", "AI Genre Suggestion")).font(.headline)
                    if model.isClassifyingGenre {
                        ProgressView(model.text("メタデータから判定中…", "Classifying from metadata…"))
                    } else if let suggestion = model.genreSuggestion {
                        Text(suggestion.genre).font(.title3.bold())
                        Label(
                            suggestion.source == .local ? model.text("内蔵AI", "Built-in AI") :
                                (suggestion.source == .openAI ? "OpenAI" : "Gemini"),
                            systemImage: suggestion.source == .local ? "desktopcomputer" : "cloud"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(model.text("確信度 \(Int(suggestion.confidence * 100))%", "Confidence \(Int(suggestion.confidence * 100))%"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(suggestion.rationale).font(.caption)
                        HStack {
                            Button(model.text("ライブラリへ登録", "Save to Library")) { model.applyGenreSuggestion(to: track) }
                            Button(model.text("閉じる", "Dismiss"), action: model.clearGenreSuggestion)
                        }
                        if let message = model.aiFallbackMessage {
                            Label(message, systemImage: "arrow.triangle.branch")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Button(model.text("AIでジャンル候補を提案", "Suggest Genre with AI")) { model.classifyGenre(for: track) }
                        Text(model.text("曲名・アーティスト・アルバム等だけを送信します。音声解析ではありません。", "Only title, artist, album, and related metadata are sent. Audio is not analyzed."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        AIProviderStatusBadge(model: model, name: "OpenAI", status: model.openAIStatus)
                        AIProviderStatusBadge(model: model, name: "Gemini", status: model.geminiStatus)
                    }
                    Button(model.text("AI設定を開く（OpenAI・Gemini）", "Open AI Settings (OpenAI & Gemini)"), action: openAISettings)
                        .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { loadTrackData() }
        .onChange(of: track) { _, _ in loadTrackData() }
        .onChange(of: model.lastMetadataEditedTrack) { _, updatedTrack in
            guard let updatedTrack, updatedTrack.id == track.id else { return }
            loadTrackData(from: updatedTrack)
            player.updateCurrentTrack(
                title: updatedTrack.title,
                artist: updatedTrack.artist,
                album: updatedTrack.album,
                albumArtist: updatedTrack.albumArtist,
                genre: updatedTrack.genre,
                discNumber: updatedTrack.discNumber,
                trackNumber: updatedTrack.trackNumber
            )
        }
    }

    private var hasChanges: Bool {
        title != track.title ||
        artist != track.artist ||
        album != track.album ||
        albumArtist != track.albumArtist ||
        genre != track.genre ||
        year != track.year ||
        discNumber != (track.discNumber.map(String.init) ?? "") ||
        trackNumber != (track.trackNumber.map(String.init) ?? "")
    }

    private var numbersAreValid: Bool {
        let discOK = discNumber.isEmpty || Int(discNumber) != nil
        let trackOK = trackNumber.isEmpty || Int(trackNumber) != nil
        return discOK && trackOK
    }

    private func loadTrackData(from updatedTrack: Track? = nil) {
        let source = updatedTrack ?? track
        title = source.title
        artist = source.artist
        album = source.album
        albumArtist = source.albumArtist
        genre = source.genre
        year = source.year
        discNumber = source.discNumber.map(String.init) ?? ""
        trackNumber = source.trackNumber.map(String.init) ?? ""
        saveError = nil
        saveSuccess = false
    }

    private func saveChanges() {
        guard hasChanges && !isSaving && numbersAreValid else { return }
        isSaving = true
        saveError = nil
        saveSuccess = false
        
        let editTitle = title
        let editArtist = artist
        let editAlbum = album
        let editAlbumArtist = albumArtist
        let editGenre = genre
        let editYear = year
        let editDisc = Int(discNumber)
        let editTrackNum = Int(trackNumber)
        
        var edit = TrackMetadataEdit(track: track)
        edit.title = editTitle
        edit.artist = editArtist
        edit.album = editAlbum
        edit.albumArtist = editAlbumArtist
        edit.genre = editGenre
        edit.year = editYear
        edit.discNumber = editDisc
        edit.trackNumber = editTrackNum
        
        Task {
            let saved = await model.updateMetadataFromEditor(for: track, edit: edit)
            if saved {
                await MainActor.run {
                    player.updateCurrentTrack(
                        title: editTitle,
                        artist: editArtist,
                        album: editAlbum,
                        albumArtist: editAlbumArtist,
                        genre: editGenre,
                        discNumber: editDisc,
                        trackNumber: editTrackNum
                    )
                    isSaving = false
                    saveSuccess = true
                    withAnimation {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            saveSuccess = false
                        }
                    }
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    saveError = model.errorMessage ?? model.text("曲情報を保存できませんでした。", "Could not save track information.")
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct ManualLyricsEditor: View {
    @ObservedObject var model: LibraryViewModel
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: String
    @State private var isSaving = false
    let isEditingExistingLyrics: Bool

    init(model: LibraryViewModel, track: Track, initialLyrics: String) {
        self.model = model
        self.track = track
        _lyrics = State(initialValue: initialLyrics)
        isEditingExistingLyrics = !initialLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.text(isEditingExistingLyrics ? "歌詞を修正" : "歌詞を手動で登録", isEditingExistingLyrics ? "Edit Lyrics" : "Add Lyrics Manually"))
                    .font(.title2.bold())
                Text("\(track.title) — \(model.displayArtist(track.artist))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextEditor(text: $lyrics)
                .font(.body)
                .frame(minWidth: 520, minHeight: 320)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                }

            Text(model.text(
                "ここで登録した歌詞はアプリ内に保存され、次回からオフラインでも表示されます。音源ファイルのタグは変更しません。",
                "Lyrics entered here are saved in the app and shown offline next time. Audio file tags are not modified."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(model.text("キャンセル", "Cancel")) { dismiss() }
                Button {
                    isSaving = true
                    model.saveManualLyrics(for: track, lyrics: lyrics)
                    dismiss()
                } label: {
                    if isSaving { ProgressView().controlSize(.small) }
                    Text(model.text("保存", "Save"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
    }
}

private struct AIProviderStatusBadge: View {
    @ObservedObject var model: LibraryViewModel
    let name: String
    let status: AIProviderStatus

    var body: some View {
        Label("\(name): \(title)", systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .help(detail)
    }

    private var title: String {
        switch status {
        case .notConfigured: model.text("未登録", "Not Set")
        case .configured: model.text("保存済み", "Saved")
        case .checking: model.text("確認中", "Checking")
        case .valid: model.text("有効", "Valid")
        case .invalid: model.text("エラー", "Error")
        }
    }

    private var icon: String {
        switch status {
        case .notConfigured: "key.slash"
        case .configured: "key.fill"
        case .checking: "clock"
        case .valid: "checkmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .valid: .green
        case .invalid: .red
        case .checking: .orange
        case .configured: .blue
        case .notConfigured: .secondary
        }
    }

    private var detail: String {
        if case let .invalid(message) = status { return message }
        return title
    }
}

private enum EditorTab: String, CaseIterable, Identifiable {
    case basic
    case credits
    case details
    case commentLyrics

    var id: String { rawValue }

    func title(isJapanese: Bool) -> String {
        switch self {
        case .basic: isJapanese ? "基本情報" : "Basic Info"
        case .credits: isJapanese ? "クレジット・制作" : "Credits"
        case .details: isJapanese ? "詳細・コード" : "Details & Codes"
        case .commentLyrics: isJapanese ? "歌詞・コメント・URL" : "Lyrics & Links"
        }
    }
}

private struct TrackMetadataEditor: View {
    @ObservedObject var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var navigationTracks: [Track]
    @State private var track: Track
    @State private var edit: TrackMetadataEdit
    @State private var selectedTab: EditorTab = .basic
    @State private var discNumber: String
    @State private var totalDiscs: String = ""
    @State private var trackNumber: String
    @State private var totalTracks: String = ""
    @State private var metadataCandidates: [MusicMetadataCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var isLookingUpMetadata = false
    @State private var isRecognizingShazam = false
    @State private var metadataLookupMessage: String?
    @State private var isSaving = false
    @State private var initialEdit: TrackMetadataEdit
    @State private var initialTrackNumber: String
    @State private var initialDiscNumber: String
    @State private var initialTotalTracks: String = ""
    @State private var initialTotalDiscs: String = ""

    init(model: LibraryViewModel, track: Track, navigationTracks: [Track]) {
        self.model = model
        let sequence = navigationTracks.contains(where: { $0.id == track.id }) ? navigationTracks : [track]
        _navigationTracks = State(initialValue: sequence)
        _track = State(initialValue: track)
        let initialMetadataEdit = TrackMetadataEdit(track: track)
        _edit = State(initialValue: initialMetadataEdit)
        _initialEdit = State(initialValue: initialMetadataEdit)
        let discStr = track.discNumber.map(String.init) ?? ""
        _discNumber = State(initialValue: discStr)
        _initialDiscNumber = State(initialValue: discStr)
        let trkStr = track.trackNumber.map(String.init) ?? ""
        _trackNumber = State(initialValue: trkStr)
        _initialTrackNumber = State(initialValue: trkStr)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.title(isJapanese: model.language == .japanese)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Form {
                switch selectedTab {
                case .basic:
                    LabeledContent(model.text("ファイル名", "Filename")) {
                        Text(track.filename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    TextField(model.text("曲名 (TIT2)", "Title (TIT2)"), text: $edit.title)
                    TextField(model.text("アーティスト (TPE1)", "Artist (TPE1)"), text: $edit.artist)
                    TextField(model.text("アルバム (TALB)", "Album (TALB)"), text: $edit.album)
                    TextField(model.text("アルバムアーティスト (TPE2)", "Album Artist (TPE2)"), text: $edit.albumArtist)
                    HStack(spacing: 12) {
                        TextField(model.text("ジャンル (TCON)", "Genre (TCON)"), text: $edit.genre)
                        TextField(model.text("リリース年 (TYER/TDRC)", "Release Year (TYER/TDRC)"), text: $edit.year)
                    }
                    HStack(spacing: 12) {
                        LabeledContent(model.text("トラック番号", "Track Number")) {
                            HStack(spacing: 4) {
                                TextField(model.text("番号", "No."), text: $trackNumber)
                                    .textFieldStyle(.roundedBorder)
                                Text("/")
                                    .foregroundStyle(.secondary)
                                TextField(model.text("総数", "Total"), text: $totalTracks)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        LabeledContent(model.text("ディスク番号", "Disc Number")) {
                            HStack(spacing: 4) {
                                TextField(model.text("番号", "No."), text: $discNumber)
                                    .textFieldStyle(.roundedBorder)
                                Text("/")
                                    .foregroundStyle(.secondary)
                                TextField(model.text("総数", "Total"), text: $totalDiscs)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    Toggle(model.text("コンピレーションアルバム (TCMP)", "Compilation Album (TCMP)"), isOn: $edit.isCompilation)
                        .disabled(track.format.lowercased() != "mp3")

                    LabeledContent(model.text("自動特定", "Auto Identify")) {
                        HStack(spacing: 10) {
                            Button {
                                recognizeWithShazam()
                            } label: {
                                Label(
                                    model.text("Shazamで音声から曲情報を認識", "Identify with Shazam"),
                                    systemImage: "waveform.and.magnifyingglass"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRecognizingShazam)

                            Button(model.text("MusicBrainz検索", "MusicBrainz"), action: lookUpMetadata)
                                .disabled(isLookingUpMetadata || edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if isRecognizingShazam || isLookingUpMetadata {
                                ProgressView().controlSize(.small)
                                Text(isRecognizingShazam ? model.text("Shazam照合中…", "Matching on Shazam…") : model.text("検索中…", "Searching…"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let candidate = selectedCandidate {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(model.text("MusicBrainzの候補", "MusicBrainz Suggestion"), systemImage: "magnifyingglass.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                if metadataCandidates.count > 1 {
                                    Menu(model.text("他の候補（\(metadataCandidates.count)件）", "Other Matches (\(metadataCandidates.count))")) {
                                        ForEach(metadataCandidates) { item in
                                            Button(candidateLabel(item)) { select(item) }
                                        }
                                    }
                                }
                            }
                            Text(candidateLabel(candidate)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(model.text("この候補の番号を入力", "Use Suggested Numbers")) {
                                    useNumbers(from: candidate)
                                }
                                Text(model.text(
                                    "曲名・アーティスト・アルバム名は自動変更しません。",
                                    "Title, artist, and album are never changed automatically."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if let metadataLookupMessage {
                                Text(metadataLookupMessage).font(.caption).foregroundStyle(.secondary)
                            }
                            if let url = URL(string: "https://musicbrainz.org/release/\(candidate.releaseID)") {
                                Link(model.text("MusicBrainzで確認", "Review on MusicBrainz"), destination: url)
                                    .font(.caption)
                            }
                        }
                        .padding(10)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                case .credits:
                    TextField(model.text("作曲者 (TCOM)", "Composer (TCOM)"), text: $edit.composer)
                    TextField(model.text("作詞者 (TEXT)", "Lyricist / Writer (TEXT)"), text: $edit.lyricist)
                    TextField(model.text("編曲者・リミキサー (TPE4)", "Arranger / Remixer (TPE4)"), text: $edit.arranger)
                    TextField(model.text("指揮者 (TPE3)", "Conductor (TPE3)"), text: $edit.conductor)
                    TextField(model.text("出版社・レーベル (TPUB)", "Publisher / Label (TPUB)"), text: $edit.publisher)

                case .details:
                    TextField(model.text("BPM / テンポ (TBPM)", "BPM / Tempo (TBPM)"), text: $edit.bpm)
                    TextField(model.text("キー (TKEY)", "Initial Key (TKEY)"), text: $edit.initialKey)
                    TextField(model.text("ISRC コード (TSRC)", "ISRC Code (TSRC)"), text: $edit.isrc)
                    TextField(model.text("著作権情報 (TCOP)", "Copyright (TCOP)"), text: $edit.copyright)
                    TextField(model.text("グループ化 / ワーク名 (TIT1)", "Grouping / Work (TIT1)"), text: $edit.grouping)
                    TextField(model.text("サブタイトル / バージョン (TIT3)", "Subtitle / Version (TIT3)"), text: $edit.subtitle)
                    TextField(model.text("原題アルバム (TOAL)", "Original Album (TOAL)"), text: $edit.originalAlbum)
                    TextField(model.text("原曲アーティスト (TOPE)", "Original Artist (TOPE)"), text: $edit.originalArtist)

                case .commentLyrics:
                    TextField(model.text("関連WebURL (WXXX)", "Related Web URL (WXXX)"), text: $edit.url)
                    TextField(model.text("コメント (COMM)", "Comment (COMM)"), text: $edit.comment)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.text("歌詞 (USLT)", "Unsynchronised Lyrics (USLT)"))
                            .font(.headline)
                        TextEditor(text: $edit.lyrics)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 160)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()
            HStack {
                Button {
                    saveAndNavigate(by: -1)
                } label: {
                    Label(model.text("前へ", "Previous"), systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help(model.text("変更を保存して前の曲へ（⌘[）", "Save changes and go to the previous song (⌘[)"))
                .disabled(previousTrack == nil || isSaving)

                Button {
                    saveAndNavigate(by: 1)
                } label: {
                    Label(model.text("次へ", "Next"), systemImage: "chevron.right")
                }
                .keyboardShortcut("]", modifiers: .command)
                .help(model.text("変更を保存して次の曲へ（⌘]）", "Save changes and go to the next song (⌘])"))
                .disabled(nextTrack == nil || isSaving)

                Text(positionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()
                Button(model.text("キャンセル", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.text("ファイルへ保存", "Save to File")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(14)
            .background(.bar)
        }
        .frame(width: 650, height: 680)
        .task(id: track.id) {
            await loadExtendedID3Async(for: track)
        }
    }

    private func loadExtendedID3Async(for targetTrack: Track) async {
        let fields = await model.readExtendedID3(for: targetTrack)
        if let val = fields["TCOM"] { edit.composer = val; initialEdit.composer = val }
        if let val = fields["TEXT"] { edit.lyricist = val; initialEdit.lyricist = val }
        if let val = fields["TPE4"] { edit.arranger = val; initialEdit.arranger = val }
        if let val = fields["TPE3"] { edit.conductor = val; initialEdit.conductor = val }
        if let val = fields["TPUB"] { edit.publisher = val; initialEdit.publisher = val }
        if let val = fields["TYER"] ?? fields["TDRC"] { edit.year = val; initialEdit.year = val }
        if let val = fields["TBPM"] { edit.bpm = val; initialEdit.bpm = val }
        if let val = fields["TKEY"] { edit.initialKey = val; initialEdit.initialKey = val }
        if let val = fields["TSRC"] { edit.isrc = val; initialEdit.isrc = val }
        if let val = fields["TCOP"] { edit.copyright = val; initialEdit.copyright = val }
        if let val = fields["TIT1"] { edit.grouping = val; initialEdit.grouping = val }
        if let val = fields["TIT3"] { edit.subtitle = val; initialEdit.subtitle = val }
        if let val = fields["TOAL"] { edit.originalAlbum = val; initialEdit.originalAlbum = val }
        if let val = fields["TOPE"] { edit.originalArtist = val; initialEdit.originalArtist = val }
        if let val = fields["COMM"] { edit.comment = val; initialEdit.comment = val }
        if let val = fields["USLT"] { edit.lyrics = val; initialEdit.lyrics = val }
        if let val = fields["WXXX"] ?? fields["WOAR"] ?? fields["WCOM"] { edit.url = val; initialEdit.url = val }
        if let trkStr = fields["TRCK"] {
            if trkStr.contains("/") {
                let parts = trkStr.components(separatedBy: "/")
                if parts.count >= 2 { totalTracks = parts[1]; initialTotalTracks = parts[1] }
            }
        }
        if let dscStr = fields["TPOS"] {
            if dscStr.contains("/") {
                let parts = dscStr.components(separatedBy: "/")
                if parts.count >= 2 { totalDiscs = parts[1]; initialTotalDiscs = parts[1] }
            }
        }
    }

    private var selectedCandidate: MusicMetadataCandidate? {
        guard let selectedCandidateID else { return nil }
        return metadataCandidates.first { $0.id == selectedCandidateID }
    }

    private var currentIndex: Int? {
        navigationTracks.firstIndex(where: { $0.id == track.id })
    }

    private var previousTrack: Track? {
        guard let currentIndex, currentIndex > navigationTracks.startIndex else { return nil }
        return navigationTracks[navigationTracks.index(before: currentIndex)]
    }

    private var nextTrack: Track? {
        guard let currentIndex else { return nil }
        let index = navigationTracks.index(after: currentIndex)
        return index < navigationTracks.endIndex ? navigationTracks[index] : nil
    }

    private var positionLabel: String {
        guard let currentIndex else { return "1 / 1" }
        return "\(currentIndex + 1) / \(navigationTracks.count)"
    }

    private var hasChanges: Bool {
        edit != initialEdit
            || trackNumber != initialTrackNumber
            || discNumber != initialDiscNumber
            || totalTracks != initialTotalTracks
            || totalDiscs != initialTotalDiscs
    }

    private var canSave: Bool {
        !isSaving
            && !edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && numbersAreValid
    }

    private func saveAndNavigate(by offset: Int) {
        let destination = offset < 0 ? previousTrack : nextTrack
        guard let destination, !isSaving else { return }
        Task {
            if hasChanges {
                guard canSave else { return }
                guard await saveCurrentTrack() else { return }
            }
            load(destination)
        }
    }

    private func saveAndDismiss() {
        Task {
            guard await saveCurrentTrack() else { return }
            dismiss()
        }
    }

    private func saveCurrentTrack() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        var pendingEdit = edit
        pendingEdit.discNumber = validNumber(discNumber)
        pendingEdit.totalDiscs = validNumber(totalDiscs)
        pendingEdit.trackNumber = validNumber(trackNumber)
        pendingEdit.totalTracks = validNumber(totalTracks)
        let saved = await model.updateMetadataFromEditor(for: track, edit: pendingEdit)
        if saved, let currentIndex {
            let updated = track.applying(pendingEdit)
            navigationTracks[currentIndex] = updated
            track = updated
            initialEdit = pendingEdit
            initialTrackNumber = trackNumber
            initialDiscNumber = discNumber
            initialTotalTracks = totalTracks
            initialTotalDiscs = totalDiscs
        }
        return saved
    }

    private func load(_ destination: Track) {
        track = destination
        let nextEdit = TrackMetadataEdit(track: destination)
        edit = nextEdit
        initialEdit = nextEdit
        let discStr = destination.discNumber.map(String.init) ?? ""
        discNumber = discStr
        initialDiscNumber = discStr
        totalDiscs = ""
        initialTotalDiscs = ""
        let trkStr = destination.trackNumber.map(String.init) ?? ""
        trackNumber = trkStr
        initialTrackNumber = trkStr
        totalTracks = ""
        initialTotalTracks = ""
        metadataCandidates = []
        selectedCandidateID = nil
        metadataLookupMessage = nil
        isLookingUpMetadata = false
        Task {
            await loadExtendedID3Async(for: destination)
        }
    }

    private func lookUpMetadata() {
        guard !isLookingUpMetadata else { return }
        isLookingUpMetadata = true
        metadataLookupMessage = nil
        metadataCandidates = []
        selectedCandidateID = nil
        var lookupTrack = track
        if edit.title != track.title || edit.artist != track.artist || edit.album != track.album {
            lookupTrack = Track(
                id: track.id, rootID: track.rootID, relativePath: track.relativePath, filename: track.filename,
                title: edit.title, artist: edit.artist, album: edit.album, albumArtist: edit.albumArtist,
                genre: edit.genre, isCompilation: edit.isCompilation,
                discNumber: track.discNumber, trackNumber: track.trackNumber,
                duration: track.duration, fileSize: track.fileSize, modifiedAt: track.modifiedAt,
                format: track.format, bitrate: track.bitrate, hasArtwork: track.hasArtwork,
                isAvailable: track.isAvailable, addedAt: track.addedAt, isFavorite: track.isFavorite
            )
        }
        let requestedTrackID = track.id
        Task {
            do {
                let results = try await model.webMetadataCandidates(for: lookupTrack)
                guard track.id == requestedTrackID else { return }
                metadataCandidates = Array(results.prefix(30))
                if let first = metadataCandidates.first {
                    select(first)
                } else {
                    metadataLookupMessage = model.text(
                        "一致する候補が見つかりませんでした。曲名やアーティスト名を確認してください。",
                        "No matching release was found. Check the song title and artist."
                    )
                }
            } catch {
                guard track.id == requestedTrackID else { return }
                metadataLookupMessage = model.text(
                    "Web検索に失敗しました: \(error.localizedDescription)",
                    "Web lookup failed: \(error.localizedDescription)"
                )
            }
            if track.id == requestedTrackID { isLookingUpMetadata = false }
        }
    }

    private func recognizeWithShazam() {
        guard !isRecognizingShazam else { return }
        isRecognizingShazam = true
        metadataLookupMessage = nil
        let requestedTrackID = track.id
        Task {
            do {
                let (scope, audioURL) = try await model.resolveAudioURL(for: track)
                let result: ShazamRecognizedMetadata?
                if let scope {
                    result = try await scope.withAccess { _ in
                        try await ShazamService.shared.recognizeTrack(fileURL: audioURL)
                    }
                } else {
                    result = try await ShazamService.shared.recognizeTrack(fileURL: audioURL)
                }
                guard track.id == requestedTrackID else { return }
                if let result {
                    if !result.title.isEmpty { edit.title = result.title }
                    if !result.artist.isEmpty { edit.artist = result.artist }
                    if let album = result.album, !album.isEmpty { edit.album = album }
                    if let genre = result.genre, !genre.isEmpty { edit.genre = genre }
                    metadataLookupMessage = model.text(
                        "Shazamで曲情報を取得・反映しました（\(result.title) / \(result.artist)）",
                        "Shazam recognized: \(result.title) by \(result.artist)"
                    )
                } else {
                    metadataLookupMessage = model.text(
                        "Shazamで曲を特定できませんでした。",
                        "No match found on Shazam."
                    )
                }
            } catch {
                guard track.id == requestedTrackID else { return }
                metadataLookupMessage = model.text(
                    "Shazam認識に失敗しました: \(error.localizedDescription)",
                    "Shazam recognition failed: \(error.localizedDescription)"
                )
            }
            if track.id == requestedTrackID { isRecognizingShazam = false }
        }
    }

    private func select(_ candidate: MusicMetadataCandidate) {
        selectedCandidateID = candidate.id
        metadataLookupMessage = nil
        guard model.autoFillMusicBrainzTrackNumbers else { return }
        Task {
            let localCount = await model.albumTrackCount(album: edit.album, artist: edit.artist)
            if namesMatch(candidate), let expected = candidate.mediumTrackCount,
               expected > 0, localCount == expected {
                useNumbers(from: candidate)
                metadataLookupMessage = model.text(
                    "アーティスト・アルバム・曲数が一致したため、ディスク番号とトラック番号を入力しました。",
                    "Disc and track numbers were filled because artist, album, and track count all match."
                )
            } else {
                metadataLookupMessage = model.text(
                    "名前または曲数が一致しないため、番号は自動入力していません。候補を確認してください。",
                    "Numbers were not auto-filled because the names or track count do not match. Review the suggestion."
                )
            }
        }
    }

    private func useNumbers(from candidate: MusicMetadataCandidate) {
        discNumber = String(candidate.discNumber)
        trackNumber = String(candidate.trackNumber)
        if let total = candidate.mediumTrackCount, total > 0 {
            totalTracks = String(total)
        }
    }

    private func namesMatch(_ candidate: MusicMetadataCandidate) -> Bool {
        normalized(candidate.recordingTitle) == normalized(edit.title)
            && normalized(candidate.artist) == normalized(edit.artist)
            && normalized(candidate.album) == normalized(edit.album)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private func candidateLabel(_ candidate: MusicMetadataCandidate) -> String {
        let date = candidate.releaseDate.map { " · \($0)" } ?? ""
        return model.text(
            "\(candidate.recordingTitle) · \(candidate.artist) · \(candidate.album) · ディスク \(candidate.discNumber) / トラック \(candidate.trackNumber)\(date)",
            "\(candidate.recordingTitle) · \(candidate.artist) · \(candidate.album) · Disc \(candidate.discNumber) / Track \(candidate.trackNumber)\(date)"
        )
    }

    private var numbersAreValid: Bool {
        [discNumber, totalDiscs, trackNumber, totalTracks].allSatisfy { value in
            value.trimmingCharacters(in: .whitespaces).isEmpty || validNumber(value) != nil
        }
    }

    private func validNumber(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let number = Int(trimmed), number >= 0 else { return nil }
        return number
    }
}

private struct BatchTrackMetadataEditor: View {
    @ObservedObject var model: LibraryViewModel
    let tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: EditorTab = .basic
    @State private var artist: String
    @State private var album: String
    @State private var albumArtist: String
    @State private var genre: String
    @State private var year: String
    @State private var isCompilation: Bool
    @State private var discNumber: String
    @State private var totalDiscs: String
    @State private var totalTracks: String
    @State private var composer: String = ""
    @State private var lyricist: String = ""
    @State private var arranger: String = ""
    @State private var conductor: String = ""
    @State private var publisher: String = ""
    @State private var bpm: String = ""
    @State private var grouping: String = ""
    @State private var copyright: String = ""
    @State private var url: String = ""
    @State private var comment: String = ""
    @State private var artworkData: Data?
    @State private var artworkImage: NSImage?
    @State private var artworkPasteError: String?

    private let initialArtist: String
    private let initialAlbum: String
    private let initialAlbumArtist: String
    private let initialGenre: String
    private let initialYear: String
    private let initialIsCompilation: Bool
    private let initialDiscNumber: String
    private let initialTotalDiscs: String
    private let initialTotalTracks: String
    private let initialComposer: String = ""
    private let initialLyricist: String = ""
    private let initialArranger: String = ""
    private let initialConductor: String = ""
    private let initialPublisher: String = ""
    private let initialBpm: String = ""
    private let initialGrouping: String = ""
    private let initialCopyright: String = ""
    private let initialUrl: String = ""
    private let initialComment: String = ""

    init(model: LibraryViewModel, tracks: [Track]) {
        self.model = model
        self.tracks = tracks
        let initArtist = Self.commonValue(tracks.map(\.artist))
        let initAlbum = Self.commonValue(tracks.map(\.album))
        let initAlbumArtist = Self.commonValue(tracks.map(\.albumArtist))
        let initGenre = Self.commonValue(tracks.map(\.genre))
        let initYear = Self.commonValue(tracks.map(\.year))
        let initComp = tracks.allSatisfy(\.isCompilation)
        let initDisc = Self.commonNumber(tracks.map(\.discNumber))

        initialArtist = initArtist
        initialAlbum = initAlbum
        initialAlbumArtist = initAlbumArtist
        initialGenre = initGenre
        initialYear = initYear
        initialIsCompilation = initComp
        initialDiscNumber = initDisc
        initialTotalDiscs = ""
        initialTotalTracks = ""

        _artist = State(initialValue: initArtist)
        _album = State(initialValue: initAlbum)
        _albumArtist = State(initialValue: initAlbumArtist)
        _genre = State(initialValue: initGenre)
        _year = State(initialValue: initYear)
        _isCompilation = State(initialValue: initComp)
        _discNumber = State(initialValue: initDisc)
        _totalDiscs = State(initialValue: "")
        _totalTracks = State(initialValue: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.text("曲情報を一括編集", "Bulk Edit Song Info"))
                    .font(.title2.bold())
                Text(model.text(
                    "変更したい項目を入力し、下の「保存」ボタンを押してください。選択した\(tracks.count)曲にまとめて反映されます。",
                    "Enter values to change and click 'Save' to update all \(tracks.count) selected songs."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Picker("", selection: $selectedTab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.title(isJapanese: model.language == .japanese)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case .basic:
                        GroupBox(model.text("基本情報", "Basic Info")) {
                            VStack(spacing: 10) {
                                batchField(model.text("アーティスト (TPE1)", "Artist (TPE1)"), value: $artist)
                                batchField(model.text("アルバム (TALB)", "Album (TALB)"), value: $album)
                                batchField(model.text("アルバムアーティスト (TPE2)", "Album Artist (TPE2)"), value: $albumArtist)
                                batchField(model.text("ジャンル (TCON)", "Genre (TCON)"), value: $genre)
                                batchField(model.text("リリース年 (TYER)", "Release Year (TYER)"), value: $year)

                                HStack(spacing: 12) {
                                    Text(model.text("ディスク番号", "Disc Number"))
                                        .frame(width: 145, alignment: .leading)
                                    HStack(spacing: 4) {
                                        TextField(model.text("番号", "No."), text: $discNumber)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 70)
                                        Text("/")
                                            .foregroundStyle(.secondary)
                                        TextField(model.text("総数", "Total"), text: $totalDiscs)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 70)
                                    }
                                    Spacer()
                                }

                                HStack(spacing: 12) {
                                    Text(model.text("トラック総数", "Total Tracks"))
                                        .frame(width: 145, alignment: .leading)
                                    HStack(spacing: 4) {
                                        Text(model.text("各曲番号 /", "Each track /"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField(model.text("総数", "Total"), text: $totalTracks)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 70)
                                    }
                                    Spacer()
                                }

                                HStack(spacing: 12) {
                                    Text(model.text("コンピレーション", "Compilation"))
                                        .frame(width: 145, alignment: .leading)
                                    Toggle(model.text("コンピレーションアルバム (TCMP)", "Compilation Album (TCMP)"), isOn: $isCompilation)
                                        .toggleStyle(.switch)
                                    Spacer()
                                }
                            }
                            .padding(.top, 4)
                        }

                        GroupBox(model.text("アルバムジャケット", "Album Artwork")) {
                            HStack(spacing: 12) {
                                if let artworkImage {
                                    Image(nsImage: artworkImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Button(model.text("画像を選択…", "Choose Image…"), action: chooseArtwork)
                                    .disabled(isRunning)
                                Button(model.text("クリップボードから貼り付け", "Paste from Clipboard"), action: pasteArtworkFromClipboard)
                                    .disabled(isRunning)
                                    .help(model.text("クリップボードの画像を貼り付け（⌘V）", "Paste an image from the clipboard (⌘V)"))
                                if artworkData != nil {
                                    Button(model.text("解除", "Clear")) {
                                        artworkData = nil
                                        artworkImage = nil
                                    }
                                    .buttonStyle(.link)
                                    .disabled(isRunning)
                                }
                                Spacer()
                            }
                            .padding(.top, 4)
                            Text(model.text(
                                "画像をコピーして⌘Vを押すか、貼り付けボタンを使用できます。",
                                "Copy an image and press ⌘V, or use the paste button."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let artworkPasteError {
                                Text(artworkPasteError).font(.caption).foregroundStyle(.red)
                            }
                        }

                    case .credits:
                        GroupBox(model.text("クレジット・制作", "Credits & Production")) {
                            VStack(spacing: 10) {
                                batchField(model.text("作曲者 (TCOM)", "Composer (TCOM)"), value: $composer)
                                batchField(model.text("作詞者 (TEXT)", "Lyricist (TEXT)"), value: $lyricist)
                                batchField(model.text("編曲者 (TPE4)", "Arranger (TPE4)"), value: $arranger)
                                batchField(model.text("指揮者 (TPE3)", "Conductor (TPE3)"), value: $conductor)
                                batchField(model.text("出版社・レーベル (TPUB)", "Publisher / Label (TPUB)"), value: $publisher)
                            }
                            .padding(.top, 4)
                        }

                    case .details:
                        GroupBox(model.text("詳細・ワーク情報", "Details & Work")) {
                            VStack(spacing: 10) {
                                batchField(model.text("BPM / テンポ (TBPM)", "BPM / Tempo (TBPM)"), value: $bpm)
                                batchField(model.text("グループ化 / ワーク名 (TIT1)", "Grouping / Work (TIT1)"), value: $grouping)
                                batchField(model.text("著作権情報 (TCOP)", "Copyright (TCOP)"), value: $copyright)
                                batchField(model.text("関連WebURL (WXXX)", "Related Web URL (WXXX)"), value: $url)
                            }
                            .padding(.top, 4)
                        }

                    case .commentLyrics:
                        GroupBox(model.text("コメント", "Comments")) {
                            VStack(alignment: .leading, spacing: 8) {
                                batchField(model.text("コメント (COMM)", "Comment (COMM)"), value: $comment)
                            }
                            .padding(.top, 4)
                        }
                    }

                    if unsupportedArtworkCount > 0 {
                        warningText(model.text(
                            "ジャケットはMP3だけに書き込めます。MP3以外が\(unsupportedArtworkCount)曲含まれています。",
                            "Artwork can be written only to MP3. The selection contains \(unsupportedArtworkCount) non-MP3 songs."
                        ))
                    }
                    if unsupportedCompilationCount > 0 {
                        warningText(model.text(
                            "コンピレーション（TCMP）はMP3だけに書き込めます。MP3以外が\(unsupportedCompilationCount)曲含まれています。",
                            "Compilation (TCMP) can be written only to MP3. The selection contains \(unsupportedCompilationCount) non-MP3 songs."
                        ))
                    }
                    if !isValidNumberInput(discNumber) || !isValidNumberInput(totalDiscs) || !isValidNumberInput(totalTracks) {
                        warningText(model.text("番号には0以上の整数を入力してください。", "Enter a whole number of zero or greater."))
                    }
                    Text(model.text(
                        "「保存」を押すと、入力・変更したすべての項目が選択曲に保存されます。コンピレーションを有効にしても、曲ごとのアーティスト名は変わりません。",
                        "Clicking 'Save' applies all modified fields. Enabling Compilation does not alter each song's artist."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
            .disabled(isRunning || isFinished)

            Divider()
            footer
                .padding(14)
                .background(.bar)
        }
        .frame(width: 720, height: 640)
        .interactiveDismissDisabled(isRunning)
        .onPasteCommand(of: [.image]) { _ in
            guard !isRunning, !isFinished else { return }
            pasteArtworkFromClipboard()
        }
    }

    @ViewBuilder
    private func batchField(
        _ title: String,
        value: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 175, alignment: .leading)
            TextField("", text: value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func applyAll() {
        var changes = BatchMetadataChanges()
        if artist != initialArtist { changes.artist = artist }
        if album != initialAlbum { changes.album = album }
        if albumArtist != initialAlbumArtist { changes.albumArtist = albumArtist }
        if genre != initialGenre { changes.genre = genre }
        if year != initialYear { changes.year = year }
        if isCompilation != initialIsCompilation { changes.isCompilation = isCompilation }
        if discNumber != initialDiscNumber && isValidNumberInput(discNumber) {
            changes.discNumber = parsedNumber(discNumber)
            changes.changesDiscNumber = true
        }
        if totalDiscs != initialTotalDiscs && isValidNumberInput(totalDiscs) {
            changes.totalDiscs = parsedNumber(totalDiscs)
            changes.changesTotalDiscs = true
        }
        if totalTracks != initialTotalTracks && isValidNumberInput(totalTracks) {
            changes.totalTracks = parsedNumber(totalTracks)
            changes.changesTotalTracks = true
        }
        if composer != initialComposer { changes.composer = composer }
        if lyricist != initialLyricist { changes.lyricist = lyricist }
        if arranger != initialArranger { changes.arranger = arranger }
        if conductor != initialConductor { changes.conductor = conductor }
        if publisher != initialPublisher { changes.publisher = publisher }
        if bpm != initialBpm { changes.bpm = bpm }
        if grouping != initialGrouping { changes.grouping = grouping }
        if copyright != initialCopyright { changes.copyright = copyright }
        if url != initialUrl { changes.url = url }
        if comment != initialComment { changes.comment = comment }
        if let artworkData {
            changes.artworkData = artworkData
        }
        guard !changes.isEmpty else { return }
        model.updateMetadata(for: tracks, changes: changes)
    }

    private var hasAnyPendingChange: Bool {
        artist != initialArtist ||
        album != initialAlbum ||
        albumArtist != initialAlbumArtist ||
        genre != initialGenre ||
        year != initialYear ||
        isCompilation != initialIsCompilation ||
        (discNumber != initialDiscNumber && isValidNumberInput(discNumber)) ||
        (totalDiscs != initialTotalDiscs && isValidNumberInput(totalDiscs)) ||
        (totalTracks != initialTotalTracks && isValidNumberInput(totalTracks)) ||
        composer != initialComposer ||
        lyricist != initialLyricist ||
        arranger != initialArranger ||
        conductor != initialConductor ||
        publisher != initialPublisher ||
        bpm != initialBpm ||
        grouping != initialGrouping ||
        copyright != initialCopyright ||
        url != initialUrl ||
        comment != initialComment ||
        artworkData != nil
    }

    private func warningText(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    @ViewBuilder
    private var footer: some View {
        let progress = model.batchMetadataProgress
        if isRunning {
            VStack(spacing: 8) {
                ProgressView(value: Double(progress.processed), total: Double(max(1, progress.total)))
                HStack {
                    Text(model.text(
                        "\(progress.processed) / \(progress.total)曲・失敗 \(progress.failed)曲",
                        "\(progress.processed) / \(progress.total) songs · \(progress.failed) failed"
                    ))
                    .monospacedDigit()
                    Spacer()
                    Text(progress.currentFilename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button(model.text("キャンセル", "Cancel"), action: model.cancelBatchMetadataUpdate)
                }
            }
        } else if isFinished {
            HStack {
                Text(completionText(progress)).foregroundStyle(progress.failed == 0 ? Color.secondary : Color.red)
                Spacer()
                Button(model.text("閉じる", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack {
                Button(model.text("閉じる", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.text("保存", "Save")) {
                    applyAll()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasAnyPendingChange || !isValidNumberInput(discNumber) || !isValidNumberInput(totalDiscs) || !isValidNumberInput(totalTracks))
            }
        }
    }

    private var isRunning: Bool { model.batchMetadataProgress.state == .running }
    private var isFinished: Bool {
        [.completed, .cancelled].contains(model.batchMetadataProgress.state)
    }
    private var unsupportedArtworkCount: Int {
        tracks.lazy.filter { $0.format.lowercased() != "mp3" }.count
    }
    private var unsupportedCompilationCount: Int {
        tracks.lazy.filter { $0.format.lowercased() != "mp3" }.count
    }

    private func completionText(_ progress: BatchMetadataProgress) -> String {
        switch progress.state {
        case .cancelled:
            model.text(
                "キャンセルしました（成功 \(progress.succeeded)曲・失敗 \(progress.failed)曲）",
                "Cancelled (\(progress.succeeded) succeeded · \(progress.failed) failed)"
            )
        default:
            model.text(
                "完了しました（成功 \(progress.succeeded)曲・失敗 \(progress.failed)曲）",
                "Completed (\(progress.succeeded) succeeded · \(progress.failed) failed)"
            )
        }
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.title = model.text("アルバムジャケットを選択", "Choose Album Artwork")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let normalized = Self.normalizedJPEG(from: image) else {
            return
        }
        artworkData = normalized
        artworkImage = NSImage(data: normalized)
        artworkPasteError = nil
    }

    private func pasteArtworkFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage else {
            artworkPasteError = model.text(
                "クリップボードに貼り付け可能な画像がありません。",
                "The clipboard does not contain a pasteable image."
            )
            return
        }
        guard let normalized = Self.normalizedJPEG(from: image) else {
            artworkPasteError = model.text(
                "クリップボードの画像を読み込めませんでした。",
                "The clipboard image could not be read."
            )
            return
        }
        artworkData = normalized
        artworkImage = NSImage(data: normalized)
        artworkPasteError = nil
    }

    private static func commonValue(_ values: [String]) -> String {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return "" }
        return first
    }

    private static func commonNumber(_ values: [Int?]) -> String {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return "" }
        return first.map(String.init) ?? ""
    }

    private func parsedNumber(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private func isValidNumberInput(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || (Int(trimmed).map { $0 >= 0 } ?? false)
    }

    private static func normalizedJPEG(from image: NSImage) -> Data? {
        let maximum = 1_600.0
        let scale = min(1, maximum / max(image.size.width, image.size.height))
        let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        let representation = NSBitmapImageRep(focusedViewRect: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        return representation?.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}

private struct AutomationStatusRow: View {
    enum State {
        case running(current: Int, total: Int, label: String)
        case runningIndeterminate(message: String)
        case completed(message: String)
        case waiting(message: String)
        case disabled(message: String)
    }

    let state: State

    var body: some View {
        HStack(spacing: 7) {
            switch state {
            case .running(let current, let total, let label):
                ProgressView()
                    .controlSize(.small)
                if total > 0 {
                    let percent = Int(Double(current) / Double(max(1, total)) * 100)
                    Text("\(label)… \(current.formatted()) / \(total.formatted()) 曲 (\(percent)%)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(label)…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            case .runningIndeterminate(let message):
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            case .completed(let message):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                Text(message)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .waiting(let message):
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text(message)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .disabled(let message):
                Image(systemName: "pause.circle")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LibrarySettingsView: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var selectedTab: SettingsTab
    @State private var openAIAPIKey = ""
    @State private var openAIModel = ""
    @State private var geminiAPIKey = ""
    @State private var geminiModel = ""
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header Tab Bar
            HStack(spacing: 8) {
                settingsTabButton(tab: .display, title: model.text("表示", "Display"), systemImage: "paintbrush")
                settingsTabButton(tab: .storage, title: model.text("保存先", "Storage"), systemImage: "externaldrive")
                settingsTabButton(tab: .differences, title: model.text("差分", "Differences"), systemImage: "arrow.left.arrow.right")
                if model.isStorageExternal {
                    settingsTabButton(tab: .offline, title: model.text("オフライン", "Offline"), systemImage: "arrow.down.circle")
                }
                settingsTabButton(tab: .ai, title: "AI", systemImage: "sparkles")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Content Area
            Group {
                switch selectedTab {
                case .display:
                    displaySettingsPage
                case .storage:
                    storageSettingsPage
                case .differences:
                    differencesSettingsPage
                case .offline:
                    if model.isStorageExternal {
                        offlineSettingsPage
                    } else {
                        displaySettingsPage
                    }
                case .ai:
                    aiSettingsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            openAIModel = model.openAIModel
            geminiModel = model.geminiModel
            model.refreshStorageSyncHistory()
            focusAPIKeyIfNeeded()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .differences { model.refreshStorageSyncHistory() }
            focusAPIKeyIfNeeded()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.appearance.palette.library)
    }

    private func settingsTabButton(tab: SettingsTab, title: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background(
                isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displaySettingsPage: some View {
        SettingsPage {
            SettingsCard(
                title: model.text("表示", "Display"),
                subtitle: model.text("アプリ全体の言語と外観を設定します。", "Configure the language and appearance used throughout the app."),
                systemImage: "paintbrush"
            ) {
                Picker(model.text("言語", "Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                AppearanceThemePicker(model: model, selection: $model.appearance)
                Toggle(
                    model.text("外部記事を選択言語へ自動翻訳", "Automatically translate external articles"),
                    isOn: $model.autoTranslateExternalArticles
                )
                .onChange(of: model.autoTranslateExternalArticles) { _, _ in
                    model.savePresentationSettings()
                }
                Text(model.text(
                    "Wikipediaとニュースは選択言語の版を優先します。自動翻訳をオフにすると、内部ブラウザは翻訳サービスを使わず元ページを表示します。",
                    "Wikipedia and news prefer the selected locale. When automatic translation is off, the internal browser shows the original page without using the translation service."
                ))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(
                title: model.text("メタデータの自動補完", "Metadata Automation"),
                subtitle: model.text("安全条件を満たす場合だけ、タグ情報を補助・正規化します。", "Assist and normalize tags only when safety checks pass."),
                systemImage: "wand.and.stars"
            ) {
                Toggle(
                    model.text(
                        "AIジャンル候補を確信度80%以上のとき自動登録",
                        "Auto-save AI genres at 80% confidence or higher"
                    ),
                    isOn: $model.autoRegisterHighConfidenceGenres
                )
                .onChange(of: model.autoRegisterHighConfidenceGenres) { _, _ in
                    model.saveAutomaticGenreSettings()
                }
                Text(model.text(
                    "オフのときは候補表示だけを行います。オンでも、既存ジャンルは上書きせず、内蔵判定の確信度が80%以上の未分類曲だけを登録します。",
                    "When off, suggestions are shown without saving. When on, only unclassified songs at 80% confidence or higher are saved; existing genres are never replaced."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.isScanningAutomaticGenres
                        ? .running(
                            current: model.automaticGenreScanProcessedCount,
                            total: model.automaticGenreScanTotalCount,
                            label: model.text("ジャンルを自動解析中", "Analyzing genres")
                        )
                        : (model.autoRegisterHighConfidenceGenres
                            ? .waiting(message: model.automaticGenreAutomationStatus)
                            : .disabled(message: model.text("自動登録はオフ（候補表示のみ）", "Auto-save is off (suggestions only)")))
                )

                Divider()

                Toggle(
                    model.text(
                        "ジャンル名を英語・標準表記へ自動マージ",
                        "Automatically standardize & merge genre names to English"
                    ),
                    isOn: $model.autoNormalizeGenresToEnglish
                )
                .onChange(of: model.autoNormalizeGenresToEnglish) { _, _ in
                    model.saveGenreNormalizationSettings()
                }
                Text(model.text(
                    "大文字・小文字の表記揺れ（acid house → Acid House）、点やハイフン（オルタナティヴ・ロック → Alternative Rock）や日本語ジャンル名を自動的に英語標準タイトルケース表記へ統一・統合します。",
                    "Standardizes casing (acid house → Acid House), punctuation, and Japanese genres (e.g. オルタナティヴ・ロック → Alternative Rock) to standard English Title Case."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.isNormalizingGenres
                        ? .runningIndeterminate(
                            message: model.genreNormalizationProgress.isEmpty
                                ? model.text("ジャンル名を自動マージ中…", "Standardizing & merging genres…")
                                : model.genreNormalizationProgress
                        )
                        : (model.genreNormalizationLastCompletedAt != nil
                            ? .completed(
                                message: model.text(
                                    "完了: \(model.genreNormalizationLastChecked.formatted())曲 確認済 · \(model.genreNormalizationLastUpdated.formatted())曲 更新 (\(model.genreNormalizationLastCompletedAt!.formatted(date: .abbreviated, time: .shortened)))",
                                    "Completed: \(model.genreNormalizationLastChecked.formatted()) checked · \(model.genreNormalizationLastUpdated.formatted()) updated (\(model.genreNormalizationLastCompletedAt!.formatted(date: .abbreviated, time: .shortened)))"
                                )
                            )
                            : (model.autoNormalizeGenresToEnglish
                                ? .waiting(message: model.genreNormalizationStatusText)
                                : .disabled(message: model.text("自動マージはオフです", "Auto-merge is off"))))
                )

                Divider()

                Toggle(
                    model.text(
                        "AI・Webからアルバムのリリース年を自動取得・登録",
                        "Automatically fetch & save album release year via Web/AI"
                    ),
                    isOn: $model.autoFetchAlbumYear
                )
                .onChange(of: model.autoFetchAlbumYear) { _, _ in
                    model.saveAlbumYearSettings()
                }
                Text(model.text(
                    "リリース年が未設定のアルバム/楽曲について、MusicBrainzおよびWeb/AIからオリジナルのリリース年（西暦）を自動調査して登録します。",
                    "Automatically checks MusicBrainz and Web/AI for missing album release years (YYYY) and updates tracks."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.isScanningAutomaticAlbumYears
                        ? .running(
                            current: model.automaticAlbumYearProcessedCount,
                            total: model.automaticAlbumYearTotalCount,
                            label: model.text("リリース年を自動取得中", "Fetching release years")
                        )
                        : (model.autoFetchAlbumYear
                            ? .waiting(message: model.albumYearAutomationStatus)
                            : .disabled(message: model.text("自動取得はオフです", "Auto-fetch is off")))
                )

                Divider()

                Toggle(
                    model.text(
                        "MusicBrainzで一致した番号候補を自動入力",
                        "Auto-fill matching MusicBrainz number suggestions"
                    ),
                    isOn: $model.autoFillMusicBrainzTrackNumbers
                )
                .onChange(of: model.autoFillMusicBrainzTrackNumbers) { _, _ in
                    model.saveMusicBrainzSettings()
                }
                Text(model.text(
                    "曲名・アーティスト・アルバム名は変更せず、3つの名前とアルバム曲数が一致した場合だけディスク番号・トラック番号を編集欄へ入力します。",
                    "Names are never changed. Disc and track numbers are filled only when title, artist, album, and album track count match."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.isBulkAutoFilling
                        ? .runningIndeterminate(
                            message: model.text("MusicBrainzで番号候補を照合・入力中…", "Matching & auto-filling numbers from MusicBrainz…")
                        )
                        : (model.autoFillMusicBrainzTrackNumbers
                            ? .waiting(
                                message: model.text(
                                    "完了 \(model.musicBrainzAutoFillSummary.completed.formatted())曲 · 未解析 \(model.musicBrainzAutoFillPendingCount.formatted())曲 · 一致なし \(model.musicBrainzAutoFillSummary.noMatch.formatted())件 · 失敗 \(model.musicBrainzAutoFillSummary.transientFailure.formatted())件",
                                    "Completed \(model.musicBrainzAutoFillSummary.completed.formatted()) · Pending \(model.musicBrainzAutoFillPendingCount.formatted()) · No match \(model.musicBrainzAutoFillSummary.noMatch.formatted()) · Failures \(model.musicBrainzAutoFillSummary.transientFailure.formatted())"
                                )
                            )
                            : .disabled(message: model.text("自動入力はオフです", "Auto-fill is off")))
                )
                if model.autoFillMusicBrainzTrackNumbers && (model.musicBrainzAutoFillSummary.noMatch > 0 || model.musicBrainzAutoFillSummary.transientFailure > 0) {
                    HStack(spacing: 8) {
                        if model.musicBrainzAutoFillSummary.noMatch > 0 {
                            Button(model.text("一致なしを再解析", "Retry No Matches")) {
                                model.retryMusicBrainzNoMatches()
                            }
                            .controlSize(.small)
                            .disabled(model.isBulkAutoFilling)
                        }
                        if model.musicBrainzAutoFillSummary.transientFailure > 0 {
                            Button(model.text("通信失敗を再試行", "Retry Network Failures")) {
                                model.retryMusicBrainzFailures()
                            }
                            .controlSize(.small)
                            .disabled(model.isBulkAutoFilling)
                        }
                    }
                    .padding(.top, 2)
                }

                Divider()

                Toggle(
                    model.text(
                        "文字幅を自動で正規化",
                        "Automatically normalize metadata character widths"
                    ),
                    isOn: $model.normalizeMetadataCharacterWidths
                )
                .onChange(of: model.normalizeMetadataCharacterWidths) { _, _ in
                    model.saveMetadataNormalizationSettings()
                }
                Text(model.text(
                    "半角カナを全角カナへ、全角英数字・記号を半角へ変換して音源ファイルへ保存します。通常のひらがな、アクセント付き文字、文字間の空白は変更しません。処理は小分けで実行され、中断後も続きから再開します。",
                    "Converts half-width kana to full-width kana and full-width ASCII letters, digits, and punctuation to half-width, then saves the tags to the audio file. Hiragana, accented letters, and spaces between characters are preserved. Processing is resumable and runs in small batches."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.normalizeMetadataCharacterWidths
                        ? .waiting(message: model.text("有効・全角/半角のゆらぎを自動変換して保存", "Active · Auto-converting full/half width characters"))
                        : .disabled(message: model.text("自動正規化はオフです", "Auto-normalization is off"))
                )

                Divider()

                Toggle(
                    model.text(
                        "先頭・末尾の空白を自動で削除",
                        "Automatically trim leading and trailing whitespace"
                    ),
                    isOn: $model.trimMetadataWhitespace
                )
                .onChange(of: model.trimMetadataWhitespace) { _, _ in
                    model.saveWhitespaceTrimmingSettings()
                }
                Text(model.text(
                    "曲名、アーティスト、アルバム名などの先頭や末尾にある余計な空白（半角スペース・全角スペース）を自動的に検出して削除・保存します。単語間のスペースは変更されません。",
                    "Automatically detects and removes leading and trailing spaces (half-width & full-width) from titles, artists, and album names. Spaces between words remain untouched."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.trimMetadataWhitespace
                        ? .waiting(message: model.text("有効・余分な前後の空白を自動削除して保存", "Active · Auto-trimming leading & trailing spaces"))
                        : .disabled(message: model.text("自動削除はオフです", "Auto-trim is off"))
                )

                Divider()

                Toggle(
                    model.text(
                        "ID3v2.2タグを自動でv2.3へ移行",
                        "Automatically migrate ID3v2.2 tags to v2.3"
                    ),
                    isOn: $model.autoMigrateID3v22ToV23
                )
                .onChange(of: model.autoMigrateID3v22ToV23) { _, _ in
                    model.saveID3MigrationSettings()
                }
                Text(model.text(
                    "すべての曲をバックグラウンドで確認し、古いID3v2.2以前のMP3タグを検出した場合は、音声データを保ったまま最新互換のID3v2.3ヘッダーへ全自動で変換・保存します。",
                    "Scans all tracks in the background and automatically converts legacy ID3v2.2 or earlier MP3 tags to ID3v2.3 format while preserving audio data."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                AutomationStatusRow(
                    state: model.autoMigrateID3v22ToV23
                        ? .waiting(message: model.text("有効・古いID3v2.2タグをv2.3へ自動変換", "Active · Auto-converting ID3v2.2 tags to v2.3"))
                        : .disabled(message: model.text("自動移行はオフです", "Auto-migration is off"))
                )

                Divider()

                HStack {
                    Text(model.text(
                        "ログ保持件数の上限",
                        "Log Retention Limit"
                    ))
                    Spacer()
                    Picker(
                        "",
                        selection: $model.maxLogRetentionLimit
                    ) {
                        ForEach(LogRetentionLimit.allCases) { limit in
                            Text(limit.title(isJapanese: model.language == .japanese)).tag(limit)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .onChange(of: model.maxLogRetentionLimit) { _, _ in
                        model.saveLogRetentionSettings()
                    }
                }
                Text(model.text(
                    "アクティビティログに保持する最大件数を設定します。上限を超えた古いログは1,000件単位で自動クリーンアップされます。",
                    "Set the maximum number of log events to retain. Older logs exceeding this limit will be cleaned up in batches of 1,000."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var storageSettingsPage: some View {
        SettingsPage {
            SettingsCard(
                title: model.text("ライブラリへ追加", "Add to Library"),
                subtitle: model.text("音楽フォルダの登録と、新しい曲の取り込みをここで行います。", "Register music folders and import new songs here."),
                systemImage: "folder.badge.plus"
            ) {
                HStack {
                    Button(model.text("フォルダを追加…", "Add Folder…"), action: model.chooseAndScanFolder)
                    Button(model.text("曲を取り込む…", "Import Songs…"), action: model.importNewTracks)
                }
                Text(model.text(
                    "フォルダを追加すると既存の音源を登録します。曲を取り込むと、設定したメイン保管先へ新しい音源をコピーします。",
                    "Add Folder registers existing music. Import Songs copies new audio into the configured main storage."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            SettingsCard(
                title: model.text("メイン保管先", "Main Storage"),
                subtitle: model.text("音源の原本を保管する場所です。", "The location that stores your original audio files."),
                systemImage: "externaldrive"
            ) {
                Label(
                    model.primaryStorageIsConnected
                        ? model.text("メイン保管先：接続中", "Main Storage: Connected")
                        : model.text("メイン保管先：未接続", "Main Storage: Disconnected"),
                    systemImage: model.primaryStorageIsConnected
                        ? "externaldrive.fill.badge.checkmark"
                        : "externaldrive.badge.exclamationmark"
                )
                .foregroundStyle(model.primaryStorageIsConnected ? Color.green : Color.orange)
                LabeledContent(model.text("現在の保存先", "Current Destination")) {
                    Text(model.storageDestinations.first(where: \.isPrimary)?.path ?? model.text("未設定", "Not set"))
                        .lineLimit(1).truncationMode(.middle)
                }
                Button(model.text("保存先を変更…", "Change Destination…"), action: model.chooseStorageDestination)
                Text(model.isStorageExternal
                     ? model.text("外部ストレージを使用中です。Mac内のオフラインキャッシュは原本と分けて管理されます。", "External storage is in use. Offline copies on this Mac are managed separately from originals.")
                     : model.text("Mac内の保存先を使用中です。この場所がオフライン保存先も兼ねます。", "Local storage is in use and also serves as offline storage."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(
                title: model.text("SSDへ移動待ち", "Waiting for Main Storage"),
                subtitle: model.text("SSDが外れている間に追加した曲をMacへ安全に保管し、再接続後に移動します。", "Songs added while the SSD is disconnected are kept safely on this Mac, then moved after reconnection."),
                systemImage: "tray.and.arrow.down"
            ) {
                let stagedImports = model.pendingImports.filter { $0.state == .staged }
                if stagedImports.isEmpty {
                    Label(model.text("移動待ちの曲はありません", "No songs are waiting to be moved."), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(stagedImports) { item in
                    HStack {
                        Text(item.filename).lineLimit(1)
                        Spacer()
                        if let destination = model.storageDestinations.first(where: \.isPrimary) {
                            Button(model.text("確認して移動", "Review and Move")) { model.moveImport(item, to: destination) }
                                .disabled(!destination.isAvailable)
                        }
                    }
                }
            }
        }
    }

    private var differencesSettingsPage: some View {
        SettingsPage {
            SettingsCard(title: model.text("ライブラリと保管先の差分", "Library and Storage Differences"), subtitle: model.text("登録情報と、現在アクセスできるファイルを比較します。", "Compare library records with files currently accessible."), systemImage: "arrow.left.arrow.right") {
                LabeledContent(model.text("現在再生できない曲", "Currently Unavailable Songs")) {
                    Text(model.unavailableTrackCount.formatted())
                        .monospacedDigit()
                        .foregroundStyle(model.unavailableTrackCount > 0 ? Color.orange : Color.secondary)
                }
                if model.primaryStorageIsConnected {
                    Label(
                        model.text("メイン保管先は接続されています", "Main storage is connected"),
                        systemImage: "externaldrive.fill.badge.checkmark"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(
                        model.text("メイン保管先が接続されていません", "Main storage is disconnected"),
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                    .foregroundStyle(.orange)
                }
                Text(model.text(
                    "ライブラリには登録されていますが、現在の保管先で見つからない曲の件数です。再接続または再スキャン後に自動更新されます。",
                    "Songs registered in the library but not currently found in storage. This updates after reconnecting or rescanning."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            SettingsCard(title: model.text("キャッシュと同期の履歴", "Cache and Sync History"), subtitle: model.text("SSD未接続時の一時保存と、メイン保管先へ移した時刻を表示します。", "Shows temporary saves while the SSD was offline and transfers to main storage."), systemImage: "clock.arrow.circlepath") {
                if model.storageSyncEvents.isEmpty {
                    Label(model.text("同期履歴はまだありません", "No sync history yet"), systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.storageSyncEvents) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.kind == .addedToCache ? "internaldrive.fill" : "externaldrive.fill.badge.checkmark")
                            .foregroundStyle(event.kind == .addedToCache ? Color.orange : Color.green)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title.isEmpty ? event.filename : event.title).lineLimit(1)
                            Text(event.kind == .addedToCache
                                 ? model.text("Macへ一時保存", "Saved temporarily on Mac")
                                 : model.text("メイン保管先へ同期", "Synced to main storage"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private var offlineSettingsPage: some View {
        SettingsPage {
            SettingsCard(title: model.text("オフライン再生", "Offline Playback"), subtitle: model.text("よく聴く曲をMacに保持し、SSDがなくても再生できます。", "Keep recent songs on this Mac so they play without the SSD."), systemImage: "arrow.down.circle") {
                Toggle(model.text("再生した曲をローカルにキャッシュ", "Cache Played Songs Locally"), isOn: $model.cacheEnabled)
                CacheTrackLimitControl(
                    value: $model.cacheTrackLimit,
                    label: model.text("保持する直近の曲:", "Recent songs to keep:"),
                    unit: model.text("曲", "songs"),
                    limits: 0...500,
                    onChange: model.saveCacheSettings
                )
                Text(model.text("上限を超えた曲は最終アクセスの古い順に自動削除します。SSD上の原本は変更しません。", "Songs beyond the limit are evicted least-recently-used. Originals on the SSD are not changed."))
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent(model.text("キャッシュ保存場所", "Cache Location")) {
                    Text(model.localCacheDirectoryPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Text(model.text(
                    "お気に入りまたはプレイリストに含まれる曲は、キャッシュ上限を超えても自動削除しません。",
                    "Cached songs in Favorites or playlists are never automatically evicted when the limit is exceeded."
                )).font(.caption).foregroundStyle(.secondary)
                Button(model.text("Finderでキャッシュを表示", "Show Cache in Finder"), action: model.revealLocalCache)
                Button(model.text("設定を保存", "Save Settings"), action: model.saveCacheSettings)
            }

            SettingsCard(
                title: model.text("クラウド共有 (iPhone / iPad 連携)", "Cloud Sharing (iPhone / iPad Sync)"),
                subtitle: model.text("Macのキャッシュ曲をクラウドに書き出し、iPhoneやiPadの「ファイル」アプリや音楽プレイヤーで再生できます。", "Export cached tracks to cloud storage to listen on iPhone/iPad via Files app or media players."),
                systemImage: "icloud.fill"
            ) {
                Picker(model.text("同期先クラウド", "Destination"), selection: $model.cloudSyncProvider) {
                    ForEach(CloudSyncProvider.allCases) { provider in
                        Label(
                            provider.title(isJapanese: model.language == .japanese),
                            systemImage: provider.icon
                        ).tag(provider)
                    }
                }
                .onChange(of: model.cloudSyncProvider) { _, newProvider in
                    model.saveCloudSyncSettings()
                    if newProvider == .custom && model.customCloudSyncPath.isEmpty {
                        model.chooseCustomCloudSyncDirectory()
                    }
                }

                if model.cloudSyncProvider == .custom {
                    HStack {
                        Text(model.customCloudSyncPath.isEmpty ? model.text("未選択", "Not selected") : model.customCloudSyncPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(model.text("フォルダを選択…", "Choose Folder…")) {
                            model.chooseCustomCloudSyncDirectory()
                        }
                        .controlSize(.small)
                    }
                } else {
                    LabeledContent(model.text("書き出し先パス", "Export Path")) {
                        Text(model.resolvedCloudSyncPathDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                Toggle(model.text("プレイリストファイル (.m3u8) も同時に出力", "Generate Playlist File (.m3u8)"), isOn: $model.exportM3UPlaylist)
                    .onChange(of: model.exportM3UPlaylist) { _, _ in model.saveCloudSyncSettings() }

                Text(model.text(
                    "💡 iPhone / iPad での聴き方:\n1. 「今すぐクラウドに書き出す」を実行\n2. iPhone/iPad の「ファイル」アプリ > iCloud Drive >「Vibe Music」を開く\n3. そのままタップして再生、または VLC / Evermusic などのプレイヤーでプレイリストを一括読み込み",
                    "💡 How to listen on iPhone / iPad:\n1. Click 'Export Cache to Cloud Now'\n2. Open Files app on iPhone/iPad > iCloud Drive > 'Vibe Music'\n3. Play directly or import the .m3u8 playlist into VLC, Evermusic, or Documents app."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(model.appearance.palette.elevated, in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 10) {
                    if model.isCloudSyncing {
                        ProgressView().controlSize(.small)
                        Text(model.cloudSyncProgress)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(model.appearance.palette.accent)
                    } else {
                        Button(model.text("今すぐクラウドに書き出す", "Export Cache to Cloud Now")) {
                            model.syncCacheToCloud()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(model.text("Finderでクラウドフォルダを開く", "Show in Finder")) {
                            model.revealCloudSyncDirectory()
                        }
                    }

                    Spacer()

                    if let lastSync = model.lastCloudSyncDate {
                        Text(model.text("最終同期: \(lastSync.formatted(date: .abbreviated, time: .shortened))", "Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var aiSettingsPage: some View {
        SettingsPage {
            SettingsCard(title: "OpenAI", subtitle: model.text("優先して使用するクラウドAIです。", "The preferred cloud AI provider."), systemImage: "sparkles") {
                LabeledContent(model.text("接続状態", "Connection")) {
                    AIProviderStatusBadge(model: model, name: "OpenAI", status: model.openAIStatus)
                }
                if case let .invalid(message) = model.openAIStatus {
                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                SecureField(model.text("変更するOpenAI APIキー", "Replacement OpenAI API Key"), text: $openAIAPIKey)
                    .focused($isAPIKeyFocused)
                TextField(model.text("OpenAIモデル", "OpenAI Model"), text: $openAIModel)
                HStack {
                    Link(model.text("OpenAIでAPIキーを作成", "Create an OpenAI API Key"), destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!)
                    if model.hasOpenAIAPIKey {
                        Button(model.text("OpenAIキーを削除", "Delete OpenAI Key"), role: .destructive, action: model.removeOpenAIAPIKey)
                    }
                }
            }

            SettingsCard(title: "Gemini", subtitle: model.text("OpenAIが失敗した場合に自動で使用します。", "Used automatically when OpenAI fails."), systemImage: "sparkles.rectangle.stack") {
                LabeledContent(model.text("接続状態", "Connection")) {
                    AIProviderStatusBadge(model: model, name: "Gemini", status: model.geminiStatus)
                }
                if case let .invalid(message) = model.geminiStatus {
                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                SecureField(model.text("変更するGemini APIキー", "Replacement Gemini API Key"), text: $geminiAPIKey)
                TextField(model.text("Geminiモデル", "Gemini Model"), text: $geminiModel)
                HStack {
                    Link(model.text("Google AI Studioでキーを作成", "Create a Key in Google AI Studio"), destination: URL(string: "https://aistudio.google.com/apikey")!)
                    if model.hasGeminiAPIKey {
                        Button(model.text("Geminiキーを削除", "Delete Gemini Key"), role: .destructive, action: model.removeGeminiAPIKey)
                    }
                }
            }

            SettingsCard(title: model.text("プライバシーとフォールバック", "Privacy and Fallback"), subtitle: nil, systemImage: "lock.shield") {
                Text(model.text(
                "キーはアプリ専用の保護データベースに保存します。ジャンル判定はOpenAI、失敗時はGemini、さらに失敗した場合は内蔵AIへ自動で切り替えます。外部へ送るのは曲名・アーティスト・アルバム等だけで、音声ファイルは送信しません。",
                "Keys are stored in the app's protected database. Genre classification tries OpenAI, then Gemini on failure, and finally the built-in AI. Only title, artist, album, and related metadata are sent; audio files are never uploaded."
            )).font(.caption).foregroundStyle(.secondary)

                HStack {
                Button(model.text("キーとモデルを保存", "Save Keys and Models")) {
                    model.saveAISettings(
                        openAIAPIKey: openAIAPIKey, openAIModel: openAIModel,
                        geminiAPIKey: geminiAPIKey, geminiModel: geminiModel
                    )
                    openAIAPIKey = ""
                    geminiAPIKey = ""
                }
                .keyboardShortcut(.defaultAction)
                Button(model.text("接続を再確認", "Test Connections"), action: model.validateAIProviders)
                }
            }
        }
    }

    private func focusAPIKeyIfNeeded() {
        guard selectedTab == .ai else { return }
        DispatchQueue.main.async { isAPIKeyFocused = true }
    }
}

private struct AppearanceThemePicker: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var selection: AppearanceMode

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            themeGroup(model.text("ダーク", "Dark"), modes: [.codexDark, .graphiteDark, .midnightDark])
            themeGroup(model.text("ライト", "Light"), modes: [.paperLight, .warmLight, .mistLight])
        }
    }

    private func themeGroup(_ title: String, modes: [AppearanceMode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(modes) { mode in
                    AppearanceThemeCard(
                        title: model.appearanceTitle(mode),
                        mode: mode,
                        isSelected: selection == mode
                    ) {
                        selection = mode
                    }
                }
            }
        }
    }
}

private struct AppearanceThemeCard: View {
    let title: String
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 0) {
                    mode.palette.sidebar.frame(width: 28)
                    mode.palette.library
                    mode.palette.inspector.frame(width: 30)
                }
                .frame(height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(mode.palette.divider, lineWidth: 1)
                }
                HStack(spacing: 5) {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? mode.palette.accent : Color.secondary)
                }
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(mode.isDark ? Color.white : Color.black.opacity(0.82))
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(mode.palette.elevated.opacity(isSelected ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? mode.palette.accent : mode.palette.divider, lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String?, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage).font(.title3).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}



private struct HoverTrackingView: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HoverNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? HoverNSView {
            view.onHover = onHover
        }
    }

    class HoverNSView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .activeAlways,
                .assumeInside
            ]
            
            let area = NSTrackingArea(
                rect: bounds,
                options: options,
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
            
            // Check initial mouse position
            if let window = window {
                let mouseLocation = window.mouseLocationOutsideOfEventStream
                let localPoint = convert(mouseLocation, from: nil)
                let isInside = bounds.contains(localPoint)
                onHover?(isInside)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            print("[HoverNSView] mouseEntered - bounds: \(bounds)")
            fflush(stdout)
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            print("[HoverNSView] mouseExited")
            fflush(stdout)
            onHover?(false)
        }
    }
}

extension View {
    func onHoverStrong(perform action: @escaping (Bool) -> Void) -> some View {
        self.background(HoverTrackingView(onHover: action))
    }
}

private struct TrackTitleCell: View {
    let track: Track
    let isPlayable: Bool
    let isCurrent: Bool
    let helpText: String
    var diagnosticKind: MetadataIssueKind? = nil
    var isJapanese: Bool = true
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
            } else if diagnosticKind == .urlInMP3Metadata && track.title.containsURLPattern {
                Image(systemName: "link")
                    .foregroundStyle(Color.accentColor)
                    .help(isJapanese ? "曲名にURLが含まれています" : "Title contains a URL")
            } else if diagnosticKind == .suspectedMojibake && track.title.containsMojibakePattern {
                Image(systemName: "character.badge.exclamationmark")
                    .foregroundStyle(Color.orange)
                    .help(isJapanese ? "曲名に文字化けが含まれています" : "Title contains suspected mojibake")
            } else if isPlayable {
                Image(systemName: "music.note")
                    .foregroundStyle(Color.secondary)
            } else {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(Color.orange)
                    .contentShape(Rectangle())
                    .onHoverStrong { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }
            }
            
            if !isPlayable && isHovered {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            
            Text(track.title)
                .lineLimit(1)
                .fontWeight(isCurrent ? .semibold : .regular)

            if diagnosticKind == .urlInMP3Metadata {
                let locations = track.urlMatchLocations(isJapanese: isJapanese)
                let extraLocations = locations.filter { $0.fieldName != (isJapanese ? "曲名" : "Title") }
                ForEach(extraLocations) { loc in
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text(loc.fieldName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.accentColor)
                    .help("\(loc.fieldName): \(loc.value)")
                }
            } else if diagnosticKind == .suspectedMojibake {
                let locations = track.mojibakeMatchLocations(isJapanese: isJapanese)
                let extraLocations = locations.filter { $0.fieldName != (isJapanese ? "曲名" : "Title") }
                ForEach(extraLocations) { loc in
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text(loc.fieldName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.orange)
                    .help("\(loc.fieldName): \(loc.value)")
                }
            }
        }
    }
}

private struct TrackNavigationCell: View {
    let title: String
    let width: CGFloat
    var hasURL: Bool = false
    var hasMojibake: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if hasURL {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                } else if hasMojibake {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                }
                Text(title)
                    .lineLimit(1)
            }
            .frame(width: width, height: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct InspectorPlayerControls: View {
    @ObservedObject var player: PlaybackController
    @ObservedObject var model: LibraryViewModel
    @Binding var isMiniPlayer: Bool

    var body: some View {
        UnifiedPlayerControls(player: player, model: model, isMiniPlayer: $isMiniPlayer, isCompact: true)
    }
}

private struct UnifiedPlayerControls: View {
    @ObservedObject var player: PlaybackController
    @ObservedObject var model: LibraryViewModel
    @ObservedObject private var progress: PlaybackController.Progress
    @Binding var isMiniPlayer: Bool
    let isCompact: Bool
    @State private var isVolumePopoverPresented = false

    init(player: PlaybackController, model: LibraryViewModel, isMiniPlayer: Binding<Bool>, isCompact: Bool) {
        self.player = player
        self.model = model
        self._progress = ObservedObject(wrappedValue: player.progress)
        self._isMiniPlayer = isMiniPlayer
        self.isCompact = isCompact
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularPlayerLayout
                .frame(minWidth: isCompact ? 360 : 420)
            narrowPlayerLayout
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 8 : 12)
        .background {
            ZStack {
                Rectangle().fill(.bar)
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 16 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 16 : 14, style: .continuous)
                .stroke(model.appearance.palette.divider, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
    }

    private var regularPlayerLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            playerArtwork(size: isCompact ? 44 : 72)

            VStack(spacing: 9) {
                HStack {
                    trackIdentity
                    Spacer(minLength: 0)
                    utilityControls
                }
                transportControls
                seekControls
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var narrowPlayerLayout: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                playerArtwork(size: isCompact ? 40 : 52)
                trackIdentity
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            utilityControls
                .frame(maxWidth: .infinity, alignment: .trailing)
            transportControls
            seekControls
        }
    }

    private func playerArtwork(size: CGFloat) -> some View {
        Button {
            guard let track = player.currentTrack else { return }
            model.openAlbumFromPlayer(for: track)
        } label: {
            PlayerArtwork(
                artworkURL: model.enrichedInfo?.artworkURL,
                size: size,
                cornerRadius: isCompact ? 8 : 9,
                placeholderPointSize: isCompact ? 17 : 25
            )
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack?.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        .help(model.text("このアルバムを表示", "Show This Album"))
        .accessibilityLabel(model.text("アルバムを表示", "Show Album"))
    }

    private var trackIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                guard let track = player.currentTrack else { return }
                model.openAlbumFromPlayer(for: track)
            } label: {
                Text(player.currentTrack?.title ?? model.text("再生していません", "Not Playing"))
                    .font(.headline)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack?.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            .help(model.text("このアルバムを表示", "Show This Album"))

            HStack(spacing: 4) {
                Button {
                    guard let track = player.currentTrack else { return }
                    model.openArtistFromPlayer(named: track.artist)
                } label: {
                    Text(player.currentTrack?.artist ?? model.text("曲を選択してください", "Select a song"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(player.currentTrack?.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                .help(model.text("このアーティストを表示", "Show This Artist"))

                if let album = player.currentTrack?.album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button {
                        guard let track = player.currentTrack else { return }
                        model.openAlbumFromPlayer(for: track)
                    } label: {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.text("このアルバムを表示", "Show This Album"))
                }
            }
        }
    }

    private var utilityControls: some View {
        HStack(spacing: 2) {
            favoriteButton
            playlistMenuButton
            shuffleButton
            repeatButton
            miniPlayerButton
            volumeButton
        }
    }

    private var playlistMenuButton: some View {
        Menu {
            Section(model.text("プレイリストに追加", "Add to Playlist")) {
                if model.playlists.isEmpty {
                    Button(model.text("新規プレイリストを作成", "Create New Playlist")) {
                        model.createPlaylist()
                    }
                } else {
                    ForEach(model.playlists) { playlist in
                        Button {
                            guard let track = player.currentTrack else { return }
                            model.addTrackIDsToPlaylist([track.id], playlistID: playlist.id)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                    Divider()
                    Button(model.text("新規プレイリストを作成", "Create New Playlist")) {
                        model.createPlaylist()
                    }
                }
            }
        } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(player.currentTrack == nil)
        .help(model.text("プレイリストに追加", "Add to Playlist"))
        .accessibilityLabel(model.text("プレイリストに追加", "Add to Playlist"))
    }

    private var favoriteButton: some View {
        Button {
            guard let track = player.currentTrack else { return }
            let newState = !track.isFavorite
            player.setCurrentTrackFavorite(newState)
            model.setFavorite(track, isFavorite: newState)
        } label: {
            Image(systemName: player.currentTrack?.isFavorite == true ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(player.currentTrack?.isFavorite == true ? Color.yellow : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil)
        .help(player.currentTrack?.isFavorite == true ? model.text("お気に入りから外す", "Remove from Favorites") : model.text("お気に入りに追加", "Add to Favorites"))
        .accessibilityLabel(model.text("お気に入り", "Favorite"))
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            Button(action: player.previous) {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel(model.text("前の曲", "Previous Track"))
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: isCompact ? 27 : 34))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? model.text("一時停止", "Pause") : model.text("再生", "Play"))
            .keyboardShortcut(.space, modifiers: [])
            Button(action: player.next) {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel(model.text("次の曲", "Next Track"))
            Spacer(minLength: 4)
        }
        .disabled(player.currentTrack == nil)
    }

    private var seekControls: some View {
        HStack(spacing: 7) {
            timeLabel(player.elapsed)
            Slider(
                value: Binding(
                    get: { player.elapsed },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(1, player.duration)
            )
            .accessibilityLabel(model.text("再生位置", "Playback Position"))
            timeLabel(player.duration)
        }
        .disabled(player.currentTrack == nil)
    }

    private var shuffleButton: some View {
        Menu {
            Button(action: player.toggleShuffle) {
                if player.shuffleEnabled && !player.isGlobalShuffleEnabled {
                    Label(model.text("現在の一覧をランダム再生", "Shuffle Current List"), systemImage: "checkmark")
                } else {
                    Text(model.text("現在の一覧をランダム再生", "Shuffle Current List"))
                }
            }
            Divider()
            Button(action: player.startGlobalShuffle) {
                if player.isGlobalShuffleEnabled {
                    Label(model.text("ライブラリ全体をランダム再生", "Shuffle Entire Library"), systemImage: "checkmark")
                } else {
                    Label(model.text("ライブラリ全体をランダム再生", "Shuffle Entire Library"), systemImage: "music.note.list")
                }
            }
        } label: {
            Image(systemName: "shuffle")
                .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(player.shuffleEnabled ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.text("ランダム再生", "Shuffle"))
        .accessibilityLabel(model.text("ランダム再生", "Shuffle"))
        .accessibilityValue(player.isGlobalShuffleEnabled
            ? model.text("ライブラリ全体", "Entire Library")
            : (player.shuffleEnabled ? model.text("現在の一覧", "Current List") : model.text("オフ", "Off")))
    }

    private var miniPlayerButton: some View {
        Button { isMiniPlayer.toggle() } label: {
            Label(
                isCompact ? model.text("通常", "Full") : model.text("ミニ", "Mini"),
                systemImage: isCompact ? "arrow.up.left.and.arrow.down.right" : "pip"
            )
                .labelStyle(.iconOnly)
                .font(.caption)
                .frame(width: 30, height: 28)
                .background(Color.secondary.opacity(0.10), in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCompact ? model.text("通常画面に戻す", "Return to Full Player") : model.text("ミニプレイヤーに切り替え", "Switch to Mini Player"))
        .accessibilityLabel(isCompact ? model.text("通常画面に戻す", "Return to Full Player") : model.text("ミニプレイヤーに切り替え", "Switch to Mini Player"))
    }

    private var repeatButton: some View {
        Menu {
            ForEach(PlaybackController.RepeatMode.allCases, id: \.self) { mode in
                Button { player.repeatMode = mode } label: {
                    if player.repeatMode == mode {
                        Label(repeatModeTitle(mode), systemImage: "checkmark")
                    } else {
                        Text(repeatModeTitle(mode))
                    }
                }
            }
        } label: {
            Image(systemName: repeatModeSymbol)
                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                .frame(width: 30, height: 28)
                .background(
                    player.repeatMode == .off ? Color.secondary.opacity(0.10) : Color.accentColor.opacity(0.16),
                    in: Capsule()
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.text("リピート", "Repeat"))
        .accessibilityLabel(model.text("リピート", "Repeat"))
        .accessibilityValue(repeatModeTitle(player.repeatMode))
    }

    private var repeatModeSymbol: String {
        player.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private func repeatModeTitle(_ mode: PlaybackController.RepeatMode) -> String {
        switch mode {
        case .off: model.text("リピートなし", "Repeat Off")
        case .one: model.text("1曲リピート", "Repeat One")
        case .all: model.text("アルバム／プレイリストをリピート", "Repeat Album/Playlist")
        }
    }

    private var volumeButton: some View {
        Button { isVolumePopoverPresented.toggle() } label: {
            Image(systemName: volumeSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 28)
                .background(Color.secondary.opacity(0.10), in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("音量を調整", "Adjust Volume"))
        .accessibilityLabel(model.text("音量", "Volume"))
        .accessibilityValue("\(Int((player.volume * 100).rounded()))%")
        .popover(isPresented: $isVolumePopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(model.text("音量", "Volume"), systemImage: volumeSymbol)
                        .font(.headline)
                    Spacer()
                    Text("\(Int((player.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $player.volume, in: 0...1)
                    .accessibilityLabel(model.text("音量", "Volume"))
            }
            .padding(14)
            .frame(width: 230)
        }
    }

    private var volumeSymbol: String {
        if player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.34 { return "speaker.wave.1.fill" }
        if player.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func timeLabel(_ seconds: Double) -> some View {
        Text(format(seconds))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 34)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

struct MiniPlayerView: View {
    @ObservedObject var player: PlaybackController
    @ObservedObject var model: LibraryViewModel
    @Binding var isMiniPlayer: Bool

    var body: some View {
        UnifiedPlayerControls(player: player, model: model, isMiniPlayer: $isMiniPlayer, isCompact: true)
        .frame(width: 390, height: 132)
        .background(WindowAppearanceSynchronizer(mode: model.appearance).frame(width: 0, height: 0))
        .onAppear { model.enrich(player.currentTrack) }
        .onChange(of: player.currentTrack) { _, track in model.enrich(track) }
    }
}

