import Foundation
import MassiveMusicCore
import SwiftUI

struct IdleListeningInsightsView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    @State private var hoveredTrackID: Int64? = nil
    @State private var hoveredPeriodID: String? = nil
    @State private var selectedPeriodID: String? = nil
    @State private var selectedGenre: String? = nil
    @State private var currentTime = Date()

    private var insights: ListeningInsights { model.listeningInsights }
    private var palette: AppearancePalette { model.appearance.palette }
    private var isDark: Bool { model.appearance.isDark }

    private var currentPeriodKey: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        switch hour {
        case 5...11: return "morning"
        case 12...16: return "afternoon"
        case 17...21: return "evening"
        default: return "night"
        }
    }

    private var activePeriodID: String {
        selectedPeriodID ?? currentPeriodKey
    }

    private var currentPeriodTitle: String {
        switch currentPeriodKey {
        case "morning": return model.text("朝の気分", "Morning Vibe")
        case "afternoon": return model.text("昼の気分", "Afternoon Vibe")
        case "evening": return model.text("夕・夜の気分", "Evening Vibe")
        default: return model.text("深夜の気分", "Late Night Vibe")
        }
    }

    private var currentPeriodIcon: String {
        switch currentPeriodKey {
        case "morning": return "sun.horizon.fill"
        case "afternoon": return "sun.max.fill"
        case "evening": return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Header with App Logo and Status
                headerView

                // 2. Smart Quick Play Buttons
                quickPlaySection

                // 3. Time of Day Listening Clock (Biorhythm) with Ranking
                timeOfDaySection

                // 4. Heavy Rotation (Top Played Tracks)
                if !insights.topTracks.isEmpty {
                    topTracksSection
                }

                // 5. Genre Breakdown Bar with Ranking
                if !insights.topGenres.isEmpty {
                    genreBreakdownSection
                }

                // 6. Rediscovery (Forgotten gems)
                if let gem = insights.rediscoveryTracks.first {
                    rediscoverySection(track: gem)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onAppear {
            currentTime = Date()
            model.loadListeningInsights()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { newDate in
            let oldKey = currentPeriodKey
            currentTime = newDate
            if oldKey != currentPeriodKey {
                model.loadListeningInsights()
            }
        }
    }

    private func vibeDisplayTitle(_ period: String) -> String {
        switch period {
        case "morning": return model.text("朝 (05:00〜12:00)", "Morning (05:00–12:00)")
        case "afternoon": return model.text("昼 (12:00〜17:00)", "Afternoon (12:00–17:00)")
        case "evening": return model.text("夕・夜 (17:00〜22:00)", "Evening (17:00–22:00)")
        default: return model.text("深夜 (22:00〜05:00)", "Night (22:00–05:00)")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.text("リスニング・インサイト", "Listening Insights"))
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Text(model.text("あなたの音楽バイオリズムと統計", "Your music habits & biorhythm"))
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            Text(model.text("再生停止中", "Not Playing"))
                .font(.caption2.bold())
                .foregroundStyle(palette.tertiaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(palette.elevated, in: Capsule())
                .overlay(Capsule().stroke(palette.divider, lineWidth: 1))
        }
        .padding(.bottom, 2)
    }

    // MARK: - Quick Play
    private var quickPlaySection: some View {
        VStack(spacing: 8) {
            Button {
                if let first = insights.currentVibeTracks.first {
                    player.play(first)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: currentPeriodIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.text("いまの時間帯の曲を再生", "Play Current Vibe"))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text(currentPeriodTitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [palette.accent, palette.accent.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .shadow(color: palette.accent.opacity(isDark ? 0.35 : 0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            if !insights.rediscoveryTracks.isEmpty {
                Button {
                    if let track = insights.rediscoveryTracks.first {
                        player.play(track)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(palette.accent)
                        Text(model.text("お気に入りリバイバル", "Favorite Revival"))
                            .font(.caption.bold())
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        Text(model.text("最近聴いていない曲", "Not heard recently"))
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Listening Clock (Time of Day Biorhythm)
    private var timeOfDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.text("時間帯別バイオリズム", "Listening Clock"), systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                if selectedPeriodID != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriodID = nil
                        }
                    } label: {
                        Text(model.text("現在に戻す", "Reset to Now"))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(model.text("タップで時間帯を切替", "Tap to switch"))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryText)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(insights.timeOfDayVibes) { vibe in
                    let isCurrent = vibe.period == currentPeriodKey
                    let isSelected = activePeriodID == vibe.period
                    let isHovered = hoveredPeriodID == vibe.period

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedPeriodID == vibe.period {
                                selectedPeriodID = nil
                            } else if vibe.period == currentPeriodKey {
                                selectedPeriodID = nil
                            } else {
                                selectedPeriodID = vibe.period
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: vibe.icon)
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? palette.accent : (isCurrent ? palette.accent : palette.secondaryText))
                                Text(vibeDisplayTitle(vibe.period))
                                    .font(.caption2.bold())
                                    .foregroundStyle(isSelected ? palette.accent : (isCurrent ? palette.accent : palette.primaryText))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if isCurrent {
                                    Text(model.text("現在", "Now"))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(palette.accent)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(palette.accent.opacity(0.15), in: Capsule())
                                }
                            }

                            HStack {
                                Text(vibe.topGenre)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if vibe.playCount > 0 {
                                    Text("\(vibe.playCount)")
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundStyle(palette.tertiaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isSelected ? palette.accent.opacity(isDark ? 0.15 : 0.08) : palette.elevated,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? palette.accent : (isCurrent ? palette.accent.opacity(0.6) : (isHovered ? palette.divider.opacity(1.5) : palette.divider)),
                                    lineWidth: isSelected ? 1.5 : (isCurrent ? 1.2 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(model.text("\(vibeDisplayTitle(vibe.period))に聴いた曲ランキングを表示", "View ranking for \(vibeDisplayTitle(vibe.period))"))
                    .onHover { h in hoveredPeriodID = h ? vibe.period : nil }
                }
            }

            // Period Top Tracks Ranking List
            if let selectedPeriod = insights.timeOfDayVibes.first(where: { $0.period == activePeriodID }) {
                periodRankingView(for: selectedPeriod)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func periodRankingView(for vibe: ListeningInsights.TimeOfDayVibe) -> some View {
        let tracks = vibe.topTracks
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: vibe.icon)
                        .font(.caption.bold())
                        .foregroundStyle(palette.accent)
                    Text(model.text("\(vibeDisplayTitle(vibe.period))のランキング", "\(vibeDisplayTitle(vibe.period)) Rankings"))
                        .font(.caption.bold())
                        .foregroundStyle(palette.primaryText)
                }

                Spacer()

                if !tracks.isEmpty {
                    Button {
                        if let first = tracks.first {
                            player.play(first.track)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text(model.text("全曲再生", "Play All"))
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            if tracks.isEmpty {
                Text(model.text("この時間帯の再生履歴はまだありません", "No listening history for this period yet"))
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryText)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(tracks.prefix(8).enumerated()), id: \.element.id) { index, item in
                        let isHovered = hoveredTrackID == item.track.id
                        Button {
                            player.play(item.track)
                        } label: {
                            HStack(spacing: 8) {
                                // Rank Number
                                ZStack {
                                    if index == 0 {
                                        Circle().fill(Color.yellow.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("1").font(.caption2.bold()).foregroundStyle(Color.yellow)
                                    } else if index == 1 {
                                        Circle().fill(Color.gray.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("2").font(.caption2.bold()).foregroundStyle(palette.secondaryText)
                                    } else if index == 2 {
                                        Circle().fill(Color.brown.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("3").font(.caption2.bold()).foregroundStyle(Color.orange)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(palette.tertiaryText)
                                            .frame(width: 18)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.track.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(isHovered ? palette.accent : palette.primaryText)
                                        .lineLimit(1)
                                    Text(item.track.artist)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if isHovered {
                                    Image(systemName: "play.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(palette.accent)
                                } else {
                                    Text(model.text("\(item.playCount)回", "\(item.playCount) plays"))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(palette.tertiaryText)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                isHovered ? palette.elevated : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { h in hoveredTrackID = h ? item.track.id : nil }
                    }
                }
                .padding(6)
                .background(palette.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.divider.opacity(0.6), lineWidth: 1))
            }
        }
    }

    // MARK: - Top Tracks
    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.text("よく聴いている曲", "Top Played Tracks"), systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(palette.secondaryText)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(insights.topTracks.prefix(4)) { item in
                    let isHovered = hoveredTrackID == item.track.id
                    Button {
                        player.play(item.track)
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(palette.elevated)
                                    .frame(width: 28, height: 28)
                                Image(systemName: isHovered ? "play.fill" : "music.note")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isHovered ? palette.accent : palette.secondaryText)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.track.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                Text(item.track.artist)
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Text("\(item.playCount)")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent.opacity(isDark ? 0.15 : 0.10), in: Capsule())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            isHovered ? palette.elevated : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in hoveredTrackID = h ? item.track.id : nil }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.divider, lineWidth: 1))
        }
    }

    // MARK: - Genre Breakdown
    private var genreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.text("ジャンル構成比", "Top Genres"), systemImage: "chart.pie.fill")
                    .font(.caption.bold())
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(model.text("タップで曲を表示", "Tap to view songs"))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tertiaryText)
            }

            VStack(spacing: 8) {
                // Multi-color Segmented Progress Bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(insights.topGenres.enumerated()), id: \.element.id) { index, slice in
                            let width = max(4, geo.size.width * CGFloat(slice.percentage))
                            let isSelected = selectedGenre == slice.genre
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedGenre = (selectedGenre == slice.genre) ? nil : slice.genre
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(genreColor(index: index))
                                    .opacity(selectedGenre == nil || isSelected ? 1.0 : 0.35)
                                    .frame(width: width, height: isSelected ? 10 : 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 10)

                // Tags
                FlowLayout(spacing: 6) {
                    ForEach(Array(insights.topGenres.enumerated()), id: \.element.id) { index, slice in
                        let isSelected = selectedGenre == slice.genre
                        let color = genreColor(index: index)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedGenre = (selectedGenre == slice.genre) ? nil : slice.genre
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 6, height: 6)
                                Text("\(slice.genre) \(Int((slice.percentage * 100).rounded()))%")
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? color : palette.primaryText)
                                if isSelected {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(color)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                isSelected ? color.opacity(isDark ? 0.18 : 0.1) : palette.elevated,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected ? color : palette.divider, lineWidth: isSelected ? 1.2 : 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(model.text("\(slice.genre)のよく聴く曲ランキングを表示", "View top tracks for \(slice.genre)"))
                    }
                }

                // Genre Top Tracks List
                if let genreName = selectedGenre,
                   let selectedSlice = insights.topGenres.first(where: { $0.genre == genreName }) {
                    genreRankingView(for: selectedSlice)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .background(palette.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.divider, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func genreRankingView(for slice: ListeningInsights.GenreSlice) -> some View {
        let tracks = slice.topTracks
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)

            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.caption.bold())
                        .foregroundStyle(palette.accent)
                    Text(model.text("\(slice.genre) の人気曲", "\(slice.genre) Top Tracks"))
                        .font(.caption.bold())
                        .foregroundStyle(palette.primaryText)
                }

                Spacer()

                if !tracks.isEmpty {
                    Button {
                        if let first = tracks.first {
                            player.play(first.track)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text(model.text("全曲再生", "Play All"))
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if tracks.isEmpty {
                Text(model.text("このジャンルの曲がありません", "No tracks for this genre"))
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryText)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(tracks.prefix(6).enumerated()), id: \.element.id) { index, item in
                        let isHovered = hoveredTrackID == item.track.id
                        Button {
                            player.play(item.track)
                        } label: {
                            HStack(spacing: 8) {
                                // Rank Number
                                ZStack {
                                    if index == 0 {
                                        Circle().fill(Color.yellow.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("1").font(.caption2.bold()).foregroundStyle(Color.yellow)
                                    } else if index == 1 {
                                        Circle().fill(Color.gray.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("2").font(.caption2.bold()).foregroundStyle(palette.secondaryText)
                                    } else if index == 2 {
                                        Circle().fill(Color.brown.opacity(0.2)).frame(width: 18, height: 18)
                                        Text("3").font(.caption2.bold()).foregroundStyle(Color.orange)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(palette.tertiaryText)
                                            .frame(width: 18)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.track.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(isHovered ? palette.accent : palette.primaryText)
                                        .lineLimit(1)
                                    Text(item.track.artist)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if isHovered {
                                    Image(systemName: "play.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(palette.accent)
                                } else {
                                    Text(model.text("\(item.playCount)回", "\(item.playCount) plays"))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(palette.tertiaryText)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                isHovered ? palette.elevated : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { h in hoveredTrackID = h ? item.track.id : nil }
                    }
                }
                .padding(4)
                .background(palette.elevated.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: - Rediscovery
    private func rediscoverySection(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.text("久しぶりに聴く名曲", "Rediscover a Favorite"), systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(palette.secondaryText)
                Spacer()
            }

            Button {
                player.play(track)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Text("\(track.artist) • \(track.album)")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.elevated, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func genreColor(index: Int) -> Color {
        let colors: [Color] = [
            palette.accent,
            Color.blue,
            Color.purple,
            Color.teal,
            Color.orange,
            Color.pink
        ]
        return colors[index % colors.count]
    }
}

// MARK: - FlowLayout helper for genre tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

