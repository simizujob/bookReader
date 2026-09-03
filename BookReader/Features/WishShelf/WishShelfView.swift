import SwiftUI

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct WishShelfView: View {
    @StateObject private var viewModel: WishShelfViewModel
    @State private var safariURL: IdentifiableURL?

    init(bookRepository: BookRepository) {
        let calculator = SeriesProgressCalculator(
            bookRepository: bookRepository,
            metadataCache: CoreDataSeriesMetadataCache(context: PersistenceController.shared.container.viewContext)
        )
        _viewModel = StateObject(wrappedValue: WishShelfViewModel(calculator: calculator))
    }

    var body: some View {
        NavigationStack {
            List(viewModel.seriesCards) { series in
                seriesCard(series)
            }
            .listStyle(.plain)
            .navigationTitle("気になる本棚")
            .onAppear { viewModel.onAppear() }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
            }
            .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func seriesCard(_ series: SeriesProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(series.seriesName).font(.headline)
                Spacer()
                if let rate = series.completionRate {
                    Text("\(series.ownedVolumes.count)/\(series.ownedVolumes.count + (series.missingVolumes?.count ?? 0))巻")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(rate * 100))%").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("既刊数不明").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let rate = series.completionRate {
                ProgressView(value: rate)
            }

            if series.isNearCompletion {
                Text("🎉 あと少しで完結")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let next = series.nextVolumeToBuy {
                Button("\(next)巻を探す") {
                    safariURL = IdentifiableURL(url: viewModel.openStoreSearch(for: series))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}
