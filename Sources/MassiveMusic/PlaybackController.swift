@preconcurrency import AVFoundation
import Combine
import Foundation
import MassiveMusicCore
@preconcurrency import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    enum RepeatMode: String, CaseIterable {
        case off = "リピートなし"
        case one = "1曲リピート"
        case all = "全体リピート"
    }

    @MainActor
    final class Progress: ObservableObject {
        @Published var elapsed: Double = 0
        @Published var duration: Double = 0

        init(elapsed: Double = 0, duration: Double = 0) {
            self.elapsed = elapsed
            self.duration = duration
        }
    }

    let progress = Progress()

    var elapsed: Double {
        get { progress.elapsed }
        set { progress.elapsed = newValue }
    }

    var duration: Double {
        get { progress.duration }
        set { progress.duration = newValue }
    }

    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false {
        didSet {
            guard oldValue != isPlaying else { return }
            updatePracticeTimerState()
        }
    }
    @Published var volume: Double = 0.8 {
        didSet {
            let normalizedVolume = Float(max(0, min(1, volume)))
            player.volume = normalizedVolume
            audioNode.volume = normalizedVolume
        }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false
    @Published private(set) var isGlobalShuffleEnabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var unavailableTrackIDs: Set<Int64> = []
    @Published private(set) var upNextTracks: [Track] = []
    @Published private(set) var queueTotalCount = 0
    @Published private(set) var queueOffset = 0
    @Published private(set) var playbackSpeed: Double
    @Published private(set) var pitchSemitones: Int {
        didSet {
            guard oldValue != pitchSemitones else { return }
            updatePracticeTimerState()
        }
    }
    @Published private(set) var sectionLoopStart: Double?
    @Published private(set) var sectionLoopEnd: Double?
    @Published private(set) var isSectionLoopEnabled = false
    @Published private(set) var activeSectionLoopSlot = 0
    @Published private(set) var currentBPM: Double?
    @Published private(set) var isAnalyzingBPM = false

    let queuePageSize = 100
    static let sectionLoopSlotCount = 3

    private let database: LibraryDatabase
    private let offlineCache: OfflineCacheManager
    private let player = AVPlayer()
    private let audioEngine = AVAudioEngine()
    private let audioNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var periodicObserver: Any?
    private var practiceTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var activeScopedURL: URL?
    private var activeScopeStarted = false
    private var activePlaybackURL: URL?
    private var activeAudioFile: AVAudioFile?
    private var engineStartFrame: AVAudioFramePosition = 0
    private var engineGeneration = UUID()
    private var loadToken = UUID()
    private var shuffleSeed = Int64.random(in: 1...Int64.max)
    private var sequenceContext: TrackPlaybackContext?
    private var sequenceCursor: Track?
    private let sectionLoopStorageKey = "playback.practice.sectionLoops.v1"
    private let bpmStorageKey = "playback.practice.detectedBPM.v1"
    private var bpmAnalysisTask: Task<Void, Never>?

    private struct StoredSectionLoop: Codable {
        let start: Double
        let end: Double?
    }

    init(database: LibraryDatabase) {
        self.database = database
        offlineCache = OfflineCacheManager(database: database)
        let savedSpeed = UserDefaults.standard.double(forKey: "playback.practice.speed")
        playbackSpeed = Self.supportedSpeeds.contains(savedSpeed) ? savedSpeed : 1
        let savedPitch = UserDefaults.standard.integer(forKey: "playback.practice.pitch")
        pitchSemitones = (-1...1).contains(savedPitch) ? savedPitch : 0
        player.volume = Float(volume)
        audioNode.volume = Float(volume)
        audioEngine.attach(audioNode)
        audioEngine.attach(timePitch)
        audioEngine.connect(audioNode, to: timePitch, format: nil)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: nil)
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.pitchSemitones == 0 else { return }
                let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
                if self.restartSectionLoopIfNeeded(at: seconds) { return }
                self.elapsed = seconds
                let ratePlaying = self.player.rate > 0
                if self.isPlaying != ratePlaying {
                    self.isPlaying = ratePlaying
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackReachedEnd() }
        }
        configureRemoteCommands()
        refreshQueue()
    }

    func play(_ track: Track) {
        isGlobalShuffleEnabled = false
        sequenceContext = nil
        sequenceCursor = nil
        startPlayback(track)
    }

    func playFromList(_ track: Track, context: TrackPlaybackContext) {
        isGlobalShuffleEnabled = false
        sequenceContext = context
        sequenceCursor = track
        startPlayback(track)
    }

    private func startPlayback(_ track: Track) {
        let token = UUID()
        loadToken = token
        bpmAnalysisTask?.cancel()
        currentBPM = nil
        isAnalyzingBPM = false
        resetSectionLoopState()
        stopPitchPlayback()
        Task {
            var resolvedSourceURL: URL?
            do {
                let url: URL
                if let cachedURL = try await offlineCache.cachedPlayableURL(for: track) {
                    guard token == loadToken else { return }
                    releaseScope()
                    url = cachedURL
                } else {
                    guard let root = try await Task.detached(priority: .userInitiated, operation: {
                        try self.database.scanRoot(id: track.rootID)
                    }).value else { throw MassiveMusicError.scanRootUnavailable }
                    let scoped = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
                    guard FileManager.default.fileExists(atPath: scoped.url.path) else {
                        throw MassiveMusicError.scanRootUnavailable
                    }
                    guard token == loadToken else { return }
                    releaseScope()
                    activeScopeStarted = scoped.url.startAccessingSecurityScopedResource()
                    activeScopedURL = scoped.url
                    let sourceURL = scoped.url.appending(path: track.relativePath)
                    resolvedSourceURL = sourceURL
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        throw MassiveMusicError.trackUnavailable
                    }
                    url = try await offlineCache.playableURL(for: track, sourceURL: sourceURL)
                }
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if fileSize == 0 || track.duration <= 0 {
                    let isEnglish = (try? database.setting(forKey: "app.language")) == "en"
                    errorMessage = isEnglish
                        ? "The audio file is empty (0 bytes) or corrupted and cannot be played."
                        : "音声ファイルが空（0バイト）または破損しているため再生できません。"
                    isPlaying = false
                    currentTrack = track
                    elapsed = 0
                    duration = 0
                    return
                }
                let item = AVPlayerItem(url: url)
                item.audioTimePitchAlgorithm = .spectral
                unavailableTrackIDs.remove(track.id)
                player.replaceCurrentItem(with: item)
                activePlaybackURL = url
                currentTrack = track
                currentBPM = storedBPM(for: track)
                isAnalyzingBPM = false
                elapsed = 0
                duration = track.duration
                restoreSectionLoopPreset(for: track, enableIfComplete: false)
                errorMessage = nil
                if pitchSemitones == 0 {
                    playAVPlayer()
                } else {
                    do {
                        try startPitchPlayback(at: 0, shouldPlay: true)
                    } catch {
                        pitchSemitones = 0
                        UserDefaults.standard.set(0, forKey: "playback.practice.pitch")
                        playAVPlayer()
                    }
                }
                try? await Task.detached { try self.database.markPlayed(trackID: track.id) }.value
                updateNowPlaying()
            } catch {
                if token == loadToken {
                    let sourceDisappeared = resolvedSourceURL.map {
                        !FileManager.default.fileExists(atPath: $0.path)
                    } ?? false
                    if sourceDisappeared {
                        await markTrackUnavailable(track)
                    } else {
                        switch error {
                        case MassiveMusicError.trackUnavailable:
                            await markTrackUnavailable(track)
                        case MassiveMusicError.scanRootUnavailable:
                            errorMessage = unavailablePlaybackMessage(rootDisconnected: true)
                        default:
                            errorMessage = error.localizedDescription
                        }
                    }
                    isPlaying = false
                }
            }
        }
    }

    private func markTrackUnavailable(_ track: Track) async {
        unavailableTrackIDs.insert(track.id)
        try? await Task.detached {
            try self.database.setTrackAvailability(id: track.id, isAvailable: false)
        }.value
        errorMessage = unavailablePlaybackMessage(rootDisconnected: false)
    }

    private func unavailablePlaybackMessage(rootDisconnected: Bool) -> String {
        let isEnglish = (try? database.setting(forKey: "app.language")) == "en"
        if isEnglish {
            return rootDisconnected
                ? "The storage drive is not connected and no local cache is available."
                : "The original file is missing and no local cache is available. Reconnect the storage drive or rescan the library."
        }
        return rootDisconnected
            ? "保存先のドライブが接続されておらず、ローカルキャッシュもありません。"
            : "元ファイルが見つからず、ローカルキャッシュもありません。保存先を再接続するか、ライブラリを再スキャンしてください。"
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if isPlaying { pauseActivePlayer() } else { playActivePlayer() }
        updateNowPlaying()
    }

    static let supportedSpeeds: [Double] = [0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00]

    func requestCurrentTrackBPM() {
        guard let track = currentTrack, let url = activePlaybackURL else { return }
        if let saved = storedBPM(for: track) {
            currentBPM = saved
            return
        }
        bpmAnalysisTask?.cancel()
        isAnalyzingBPM = true
        let trackID = track.id
        bpmAnalysisTask = Task { [weak self] in
            do {
                let bpm = try await BPMDetector.detect(at: url)
                guard !Task.isCancelled, let self, self.currentTrack?.id == trackID else { return }
                self.currentBPM = bpm
                self.isAnalyzingBPM = false
                if let bpm { self.storeBPM(bpm, trackID: trackID) }
            } catch {
                guard !Task.isCancelled, let self, self.currentTrack?.id == trackID else { return }
                self.currentBPM = nil
                self.isAnalyzingBPM = false
            }
        }
    }

    private func storedBPM(for track: Track) -> Double? {
        UserDefaults.standard.dictionary(forKey: bpmStorageKey)?[String(track.id)] as? Double
    }

    private func storeBPM(_ bpm: Double, trackID: Int64) {
        var values = UserDefaults.standard.dictionary(forKey: bpmStorageKey) ?? [:]
        values[String(trackID)] = bpm
        UserDefaults.standard.set(values, forKey: bpmStorageKey)
    }

    func setPlaybackSpeed(_ speed: Double) {
        guard Self.supportedSpeeds.contains(speed) else { return }
        let wasPlaying = isPlaying
        let position = elapsed
        playbackSpeed = speed
        UserDefaults.standard.set(speed, forKey: "playback.practice.speed")
        guard currentTrack != nil else { return }
        if pitchSemitones == 0 {
            stopPitchPlayback()
            guard player.currentItem != nil else { return }
            seekAVPlayer(to: position)
            if wasPlaying { playAVPlayer() }
        } else {
            do {
                try startPitchPlayback(at: position, shouldPlay: wasPlaying)
            } catch {
                pitchSemitones = 0
                UserDefaults.standard.set(0, forKey: "playback.practice.pitch")
                errorMessage = error.localizedDescription
                seekAVPlayer(to: position)
                if wasPlaying { playAVPlayer() }
            }
        }
        updateNowPlaying()
    }

    func setPitchSemitones(_ semitones: Int) {
        guard (-1...1).contains(semitones) else { return }
        let wasPlaying = isPlaying
        let position = elapsed
        pitchSemitones = semitones
        UserDefaults.standard.set(semitones, forKey: "playback.practice.pitch")
        guard currentTrack != nil else { return }
        if semitones == 0 {
            stopPitchPlayback()
            seekAVPlayer(to: position)
            if wasPlaying { playAVPlayer() }
        } else {
            player.pause()
            do {
                try startPitchPlayback(at: position, shouldPlay: wasPlaying)
            } catch {
                pitchSemitones = 0
                UserDefaults.standard.set(0, forKey: "playback.practice.pitch")
                errorMessage = error.localizedDescription
                seekAVPlayer(to: position)
                if wasPlaying { playAVPlayer() }
            }
        }
        updateNowPlaying()
    }

    var canSetSectionLoopEnd: Bool {
        guard let sectionLoopStart else { return false }
        return elapsed >= sectionLoopStart + 0.5
    }

    func setSectionLoopStart() {
        guard currentTrack != nil else { return }
        sectionLoopStart = max(0, min(duration, elapsed))
        sectionLoopEnd = nil
        isSectionLoopEnabled = false
        persistActiveSectionLoop()
    }

    func setSectionLoopEnd() {
        guard let start = sectionLoopStart, canSetSectionLoopEnd else { return }
        sectionLoopEnd = max(start + 0.5, min(duration, elapsed))
        isSectionLoopEnabled = true
        persistActiveSectionLoop()
        seek(to: start)
    }

    func toggleSectionLoop() {
        guard let start = sectionLoopStart,
              let end = sectionLoopEnd,
              end > start else { return }
        isSectionLoopEnabled.toggle()
        if isSectionLoopEnabled, !(start..<end).contains(elapsed) {
            seek(to: start)
        }
    }

    func clearSectionLoop() {
        resetSectionLoopState()
        persistActiveSectionLoop()
    }

    func selectSectionLoopSlot(_ slot: Int) {
        guard (0..<Self.sectionLoopSlotCount).contains(slot), slot != activeSectionLoopSlot else { return }
        let wasEnabled = isSectionLoopEnabled
        activeSectionLoopSlot = slot
        if let currentTrack {
            restoreSectionLoopPreset(for: currentTrack, enableIfComplete: wasEnabled)
        } else {
            resetSectionLoopState()
        }
    }

    func sectionLoopIsConfigured(at slot: Int) -> Bool {
        guard let currentTrack,
              (0..<Self.sectionLoopSlotCount).contains(slot),
              let trackLoops = storedSectionLoops()[sectionLoopTrackKey(currentTrack)],
              slot < trackLoops.count else { return false }
        return trackLoops[slot]?.end != nil
    }

    private func resetSectionLoopState() {
        sectionLoopStart = nil
        sectionLoopEnd = nil
        isSectionLoopEnabled = false
    }

    private func restoreSectionLoopPreset(for track: Track, enableIfComplete: Bool) {
        let trackLoops = storedSectionLoops()[sectionLoopTrackKey(track)] ?? []
        let preset = activeSectionLoopSlot < trackLoops.count ? trackLoops[activeSectionLoopSlot] : nil
        sectionLoopStart = preset?.start
        sectionLoopEnd = preset?.end
        isSectionLoopEnabled = enableIfComplete && preset?.end != nil
    }

    private func persistActiveSectionLoop() {
        guard let currentTrack else { return }
        var allLoops = storedSectionLoops()
        let key = sectionLoopTrackKey(currentTrack)
        var trackLoops = allLoops[key] ?? Array(repeating: nil, count: Self.sectionLoopSlotCount)
        if trackLoops.count < Self.sectionLoopSlotCount {
            trackLoops.append(contentsOf: Array(repeating: nil, count: Self.sectionLoopSlotCount - trackLoops.count))
        }
        trackLoops[activeSectionLoopSlot] = sectionLoopStart.map {
            StoredSectionLoop(start: $0, end: sectionLoopEnd)
        }
        if trackLoops.allSatisfy({ $0 == nil }) {
            allLoops.removeValue(forKey: key)
        } else {
            allLoops[key] = trackLoops
        }
        if let data = try? JSONEncoder().encode(allLoops) {
            UserDefaults.standard.set(data, forKey: sectionLoopStorageKey)
        }
    }

    private func storedSectionLoops() -> [String: [StoredSectionLoop?]] {
        guard let data = UserDefaults.standard.data(forKey: sectionLoopStorageKey),
              let loops = try? JSONDecoder().decode([String: [StoredSectionLoop?]].self, from: data) else {
            return [:]
        }
        return loops
    }

    private func sectionLoopTrackKey(_ track: Track) -> String {
        "\(track.rootID):\(track.relativePath)"
    }

    func dismissError() { errorMessage = nil }

    func toggleShuffle() {
        if isGlobalShuffleEnabled {
            isGlobalShuffleEnabled = false
            shuffleEnabled = true
            return
        }
        isGlobalShuffleEnabled = false
        shuffleEnabled.toggle()
        if shuffleEnabled { shuffleSeed = Int64.random(in: 1...Int64.max) }
    }

    func startGlobalShuffle() {
        shuffleEnabled = true
        isGlobalShuffleEnabled = true
        sequenceContext = nil
        sequenceCursor = nil
        shuffleSeed = Int64.random(in: 1...Int64.max)
        Task {
            do {
                guard let track = try await globalShuffleCandidate(excludingTrackID: currentTrack?.id) else {
                    errorMessage = noGlobalShuffleTracksMessage()
                    return
                }
                startPlayback(track)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(duration, seconds))
        if pitchSemitones == 0 {
            seekAVPlayer(to: target)
        } else {
            let wasPlaying = isPlaying
            do {
                try startPitchPlayback(at: target, shouldPlay: wasPlaying)
                elapsed = target
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func next() {
        Task {
            do {
                let queued = try await Task.detached(priority: .userInitiated) { try self.database.dequeueNext() }.value
                if let queued {
                    refreshQueue()
                    startPlayback(queued)
                } else {
                    loadAdjacent(direction: 1)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func previous() {
        if elapsed > 3 { seek(to: 0) } else { loadAdjacent(direction: -1) }
    }

    private func loadAdjacent(direction: Int) {
        guard let currentTrack else { return }
        let shouldShuffle = shuffleEnabled
        let shouldUseGlobalShuffle = isGlobalShuffleEnabled
        let seed = shuffleSeed
        let context = sequenceContext
        let cursor = sequenceCursor ?? currentTrack
        let shouldWrap = repeatMode == .all
        Task {
            do {
                let nextTrack: Track?
                if direction > 0, shouldUseGlobalShuffle {
                    nextTrack = try await globalShuffleCandidate(excludingTrackID: currentTrack.id)
                } else {
                    nextTrack = try await Task.detached(priority: .userInitiated) {
                        if direction > 0, shouldShuffle {
                            return try self.database.shuffleCandidates(
                                afterID: currentTrack.id,
                                seed: seed,
                                limit: 1
                            ).first ?? self.database.adjacentTrack(to: currentTrack.id, direction: direction)
                        }
                        if let context {
                            return try self.database.adjacentTrack(
                                in: context,
                                from: cursor,
                                direction: direction,
                                wraps: shouldWrap
                            )
                        }
                        return try self.database.adjacentTrack(to: currentTrack.id, direction: direction)
                    }.value
                }
                if let nextTrack {
                    if context != nil { sequenceCursor = nextTrack }
                    startPlayback(nextTrack)
                }
                else if repeatMode == .all { seek(to: 0); playActivePlayer() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func globalShuffleCandidate(excludingTrackID: Int64?) async throws -> Track? {
        let roots = try await Task.detached(priority: .userInitiated) {
            try self.database.scanRoots()
        }.value
        let connectedRootIDs = roots.compactMap { root -> Int64? in
            guard let scoped = try? SecurityScopedRoot.resolve(bookmark: root.bookmark),
                  FileManager.default.fileExists(atPath: scoped.url.path) else { return nil }
            return root.id
        }
        shuffleSeed = nextShuffleSeed(shuffleSeed)

        if !connectedRootIDs.isEmpty {
            let seed = shuffleSeed
            return try await Task.detached(priority: .userInitiated) {
                try self.database.randomTrack(
                    rootIDs: connectedRootIDs,
                    seed: seed,
                    excludingTrackID: excludingTrackID
                )
            }.value
        }

        var excluded = excludingTrackID
        while true {
            let seed = shuffleSeed
            let excludedTrackID = excluded
            let database = database
            guard let candidate = try await Task.detached(priority: .userInitiated, operation: {
                try database.randomCachedTrack(seed: seed, excludingTrackID: excludedTrackID)
            }).value else { return nil }
            if try await offlineCache.cachedPlayableURL(for: candidate) != nil {
                return candidate
            }
            try? await Task.detached(priority: .utility) {
                try self.database.removeCachedTrack(trackID: candidate.id)
            }.value
            excluded = candidate.id
            shuffleSeed = nextShuffleSeed(shuffleSeed)
        }
    }

    private func nextShuffleSeed(_ seed: Int64) -> Int64 {
        seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    private func noGlobalShuffleTracksMessage() -> String {
        let isEnglish = (try? database.setting(forKey: "app.language")) == "en"
        return isEnglish
            ? "No playable tracks are available in the connected library or local cache."
            : "接続中のライブラリまたはローカルキャッシュに再生できる曲がありません。"
    }

    private func didFinishTrack() {
        if repeatMode == .one {
            seek(to: 0)
            playActivePlayer()
        } else {
            next()
        }
    }

    func addToUpNext(_ track: Track) {
        Task {
            do {
                _ = try await Task.detached { try self.database.enqueueNext(trackID: track.id) }.value
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func playQueued(_ track: Track) {
        Task {
            do {
                try await Task.detached { try self.database.removeFromPlayQueue(trackID: track.id) }.value
                refreshQueue()
                startPlayback(track)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeFromUpNext(_ track: Track) {
        Task {
            do {
                try await Task.detached { try self.database.removeFromPlayQueue(trackID: track.id) }.value
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func clearUpNext() {
        Task {
            do {
                try await Task.detached { try self.database.clearPlayQueue() }.value
                queueOffset = 0
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    var queuePageNumber: Int { queueTotalCount == 0 ? 0 : queueOffset / queuePageSize + 1 }
    var queuePageCount: Int { queueTotalCount == 0 ? 0 : Int(ceil(Double(queueTotalCount) / Double(queuePageSize))) }
    var canGoToPreviousQueuePage: Bool { queueOffset > 0 }
    var canGoToNextQueuePage: Bool { queueOffset + upNextTracks.count < queueTotalCount }

    func previousQueuePage() {
        queueOffset = max(0, queueOffset - queuePageSize)
        refreshQueue()
    }

    func nextQueuePage() {
        guard canGoToNextQueuePage else { return }
        queueOffset += queuePageSize
        refreshQueue()
    }

    func refreshQueue() {
        let requestedOffset = queueOffset
        Task {
            do {
                let page = try await Task.detached {
                    try self.database.playQueuePage(offset: requestedOffset, limit: self.queuePageSize)
                }.value
                if page.totalCount > 0, requestedOffset >= page.totalCount {
                    queueOffset = max(0, ((page.totalCount - 1) / queuePageSize) * queuePageSize)
                    refreshQueue()
                    return
                }
                upNextTracks = page.tracks
                queueTotalCount = page.totalCount
                queueOffset = page.offset
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func releaseScope() {
        if activeScopeStarted { activeScopedURL?.stopAccessingSecurityScopedResource() }
        activeScopeStarted = false
        activeScopedURL = nil
    }

    private func playAVPlayer() {
        player.playImmediately(atRate: Float(playbackSpeed))
        isPlaying = true
    }

    private func seekAVPlayer(to seconds: Double) {
        let target = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = target.seconds
    }

    private func playActivePlayer() {
        if pitchSemitones == 0 {
            playAVPlayer()
        } else {
            guard activeAudioFile != nil else { return }
            do {
                if !audioEngine.isRunning { try audioEngine.start() }
                audioNode.play()
                isPlaying = true
            } catch {
                errorMessage = error.localizedDescription
                isPlaying = false
            }
        }
    }

    private func pauseActivePlayer() {
        if pitchSemitones == 0 {
            player.pause()
        } else {
            audioNode.pause()
        }
        isPlaying = false
    }

    private func startPitchPlayback(at seconds: Double, shouldPlay: Bool) throws {
        guard let activePlaybackURL else { throw CocoaError(.fileNoSuchFile) }
        engineGeneration = UUID()
        let generation = engineGeneration
        audioNode.stop()
        let file = try AVAudioFile(forReading: activePlaybackURL)
        activeAudioFile = file
        let sampleRate = file.processingFormat.sampleRate
        let requestedFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let startFrame = min(file.length, requestedFrame)
        engineStartFrame = startFrame
        let remainingFrames = min(Int64(UInt32.max), max(0, file.length - startFrame))
        guard remainingFrames > 0 else {
            handlePlaybackReachedEnd()
            return
        }
        timePitch.rate = Float(playbackSpeed)
        timePitch.pitch = Float(pitchSemitones * 100)
        audioNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.engineGeneration == generation,
                      self.pitchSemitones != 0 else { return }
                self.handlePlaybackReachedEnd()
            }
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
        if shouldPlay { audioNode.play() }
        isPlaying = shouldPlay
    }

    private func stopPitchPlayback() {
        engineGeneration = UUID()
        audioNode.stop()
        activeAudioFile = nil
    }

    private func updateEnginePlaybackState() {
        guard pitchSemitones != 0,
              let file = activeAudioFile,
              let nodeTime = audioNode.lastRenderTime,
              let playerTime = audioNode.playerTime(forNodeTime: nodeTime) else { return }
        let frame = engineStartFrame + AVAudioFramePosition(playerTime.sampleTime)
        let seconds = min(duration, max(0, Double(frame) / file.processingFormat.sampleRate))
        if restartSectionLoopIfNeeded(at: seconds) { return }
        elapsed = seconds
        let nodePlaying = audioNode.isPlaying
        if isPlaying != nodePlaying {
            isPlaying = nodePlaying
        }
    }

    private func updatePracticeTimerState() {
        if pitchSemitones != 0 && isPlaying {
            guard practiceTimer == nil else { return }
            practiceTimer = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateEnginePlaybackState() }
                }
        } else {
            practiceTimer?.cancel()
            practiceTimer = nil
        }
    }

    private func restartSectionLoopIfNeeded(at seconds: Double) -> Bool {
        guard isSectionLoopEnabled,
              let start = sectionLoopStart,
              let end = sectionLoopEnd,
              seconds >= end else { return false }
        seek(to: start)
        return true
    }

    private func handlePlaybackReachedEnd() {
        if isSectionLoopEnabled, let start = sectionLoopStart {
            seek(to: start)
        } else {
            didFinishTrack()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playActivePlayer() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseActivePlayer() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0
        ]
    }

    func updateCurrentTrack(title: String, artist: String, album: String, albumArtist: String, genre: String, discNumber: Int?, trackNumber: Int?) {
        guard let current = currentTrack else { return }
        let updated = Track(
            id: current.id,
            rootID: current.rootID,
            relativePath: current.relativePath,
            filename: current.filename,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            discNumber: discNumber,
            trackNumber: trackNumber,
            duration: current.duration,
            fileSize: current.fileSize,
            modifiedAt: Date(),
            format: current.format,
            bitrate: current.bitrate,
            hasArtwork: current.hasArtwork,
            isAvailable: current.isAvailable,
            addedAt: current.addedAt,
            isFavorite: current.isFavorite
        )
        self.currentTrack = updated
        updateNowPlaying()
    }

    func setCurrentTrackFavorite(_ isFavorite: Bool) {
        guard let current = currentTrack, current.isFavorite != isFavorite else { return }
        let updated = Track(
            id: current.id,
            rootID: current.rootID,
            relativePath: current.relativePath,
            filename: current.filename,
            title: current.title,
            artist: current.artist,
            album: current.album,
            albumArtist: current.albumArtist,
            genre: current.genre,
            year: current.year,
            isCompilation: current.isCompilation,
            discNumber: current.discNumber,
            trackNumber: current.trackNumber,
            duration: current.duration,
            fileSize: current.fileSize,
            modifiedAt: current.modifiedAt,
            format: current.format,
            bitrate: current.bitrate,
            hasArtwork: current.hasArtwork,
            isAvailable: current.isAvailable,
            addedAt: current.addedAt,
            isFavorite: isFavorite
        )
        self.currentTrack = updated
    }
}
