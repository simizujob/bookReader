import SwiftUI

/// シリーズ内の巻ごとのステータスを一覧表示・変更する画面。
/// 本棚一覧のシリーズカードをタップした先に表示される。
struct SeriesDetailView: View {
    let series: SeriesProgress
    @ObservedObject var viewModel: ShelfViewModel
    @Binding var safariURL: IdentifiableURL?
    let bookRepository: BookRepository

    init(
        series: SeriesProgress,
        viewModel: ShelfViewModel,
        safariURL: Binding<IdentifiableURL?>,
        bookRepository: BookRepository
    ) {
        self.series = series
        self.viewModel = viewModel
        self._safariURL = safariURL
        self.bookRepository = bookRepository
    }

    var body: some View {
        List {
            Section {
                if let rate = series.completionRate {
                    ProgressView(value: rate)
                    Text("完結率 \(Int(rate * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("既刊数不明").font(.subheadline).foregroundStyle(.secondary)
                }

                if series.isNearCompletion {
                    Text("🎉 あと少しで完結")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if let next = series.nextVolumeToBuy {
                    Button("\(next)巻を探す") {
                        safariURL = IdentifiableURL(url: viewModel.openStoreSearch(for: series))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("巻ごとのステータス") {
                ForEach(series.volumes) { entry in
                    volumeRow(entry)
                }
            }
        }
        .navigationTitle(series.seriesName)
    }

    private func volumeRow(_ entry: SeriesVolumeEntry) -> some View {
        HStack {
            if let book = try? bookRepository.find(id: entry.bookID) {
                NavigationLink {
                    BookDetailView(book: book, bookRepository: bookRepository, onChange: viewModel.reload)
                } label: {
                    Text("\(entry.volumeNumber)巻")
                }
            } else {
                Text("\(entry.volumeNumber)巻")
            }
            Spacer()
            StatusPillMenu(currentStatus: entry.unifiedStatus) { newStatus in
                viewModel.changeStatus(bookID: entry.bookID, to: newStatus)
            }
        }
    }
}
