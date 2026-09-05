import SwiftUI

/// シリーズ内の巻ごとのステータスを一覧表示・変更する画面。
/// 本棚一覧のシリーズカードをタップした先に表示される。
/// seriesKeyで参照し、viewModel.seriesCardsから毎回最新の状態を引くことで、
/// ステータス変更や既刊数の手動入力が即座に画面へ反映されるようにする。
struct SeriesDetailView: View {
    let seriesKey: String
    @ObservedObject var viewModel: ShelfViewModel
    @Binding var safariURL: IdentifiableURL?
    let bookRepository: BookRepository

    @State private var showVolumeCountEntry = false
    @State private var volumeCountInput = ""

    init(
        seriesKey: String,
        viewModel: ShelfViewModel,
        safariURL: Binding<IdentifiableURL?>,
        bookRepository: BookRepository
    ) {
        self.seriesKey = seriesKey
        self.viewModel = viewModel
        self._safariURL = safariURL
        self.bookRepository = bookRepository
    }

    private var series: SeriesProgress? {
        viewModel.seriesCards.first { $0.seriesKey == seriesKey }
    }

    var body: some View {
        Group {
            if let series {
                content(for: series)
            } else {
                ContentUnavailableView("シリーズが見つかりません", systemImage: "questionmark.circle")
            }
        }
        .alert("既刊数を入力", isPresented: $showVolumeCountEntry) {
            TextField("既刊数", text: $volumeCountInput)
                .keyboardType(.numberPad)
            Button("設定する") {
                if let series, let total = Int(volumeCountInput), total > 0 {
                    viewModel.setManualVolumeCount(for: series, total: total)
                }
                volumeCountInput = ""
            }
            Button("不明のまま", role: .cancel) {
                volumeCountInput = ""
            }
        } message: {
            Text("既刊総数がわかれば入力してください。未登録の巻を気になる本棚へ追加します。")
        }
    }

    @ViewBuilder
    private func content(for series: SeriesProgress) -> some View {
        List {
            Section {
                if let rate = series.completionRate {
                    ProgressView(value: rate)
                    Text("完結率 \(Int(rate * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        showVolumeCountEntry = true
                    } label: {
                        Text("既刊数不明（タップして入力）")
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
        let book = try? bookRepository.find(id: entry.bookID)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let book {
                    NavigationLink {
                        BookDetailView(book: book, bookRepository: bookRepository, onChange: viewModel.reload)
                    } label: {
                        Text(entry.displayLabel)
                    }
                } else {
                    Text(entry.displayLabel)
                }
                if let book, entry.unifiedStatus == .unread || entry.unifiedStatus == .reading {
                    Text("\(viewModel.elapsedDays(for: book))日経過")
                        .font(.caption)
                        .foregroundStyle(viewModel.isOverdue(book) ? .orange : .secondary)
                }
            }
            Spacer()
            // 未購入の巻は実物を持っていないため、スキャンではなくAmazonでの購入導線を明示する。
            if entry.unifiedStatus == .wishlist, let book {
                Button {
                    safariURL = IdentifiableURL(url: viewModel.openStoreSearch(for: book))
                } label: {
                    Image(systemName: "cart")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(entry.displayLabel)を購入")
                // ステータス変更ピルとの誤タップを防ぐため間隔を空ける
                .padding(.trailing, 16)
            }
            StatusPillMenu(currentStatus: entry.unifiedStatus) { newStatus in
                viewModel.changeStatus(bookID: entry.bookID, to: newStatus)
            }
        }
    }
}
