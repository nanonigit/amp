import Foundation
import MassiveMusicCore
import SwiftUI

struct ShazamResultSheet: View {
    @ObservedObject var model: LibraryViewModel
    let result: ShazamRecognitionResult

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(model.appearance.palette.accent)
                Text(model.text("Shazamで楽曲を特定しました", "Identified by Shazam"))
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.text("曲名:", "Title:")).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(result.metadata.title).bold()
                }
                HStack {
                    Text(model.text("アーティスト:", "Artist:")).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(result.metadata.artist).bold()
                }
                if let album = result.metadata.album, !album.isEmpty {
                    HStack {
                        Text(model.text("アルバム:", "Album:")).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(album)
                    }
                }
                if let genre = result.metadata.genre, !genre.isEmpty {
                    HStack {
                        Text(model.text("ジャンル:", "Genre:")).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(genre)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(model.text("キャンセル", "Cancel")) {
                    model.shazamRecognitionResult = nil
                }
                Spacer()
                Button(model.text("この情報で更新", "Apply Metadata")) {
                    Task { await model.applyShazamMetadata(for: result.track, metadata: result.metadata) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
