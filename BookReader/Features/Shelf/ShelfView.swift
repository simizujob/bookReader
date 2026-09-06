import SwiftUI

struct ShelfView: View {
    @StateObject private var viewModel: ShelfViewModel
    @State private var showScanRegister = false
    @State private var safariURL: IdentifiableURL?
    private let bookRepository: BookRepository
    private let adService: AdServing

    init(bookRepository: BookRepository, adService: AdServing = AdService()) {
        self.bookRepository = bookRepository
        self.adService = adService
        let calculator = SeriesProgressCalculator(
            bookRepository: bookRepository,
            metadataCache: CoreDataSeriesMetadataCache(context: PersistenceController.shared.container.viewContext)
        )
        _viewModel = StateObject(wrappedValue: ShelfViewModel(bookRepository: bookRepository, calculator: calculator))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if !viewModel.displayedItems.isEmpty {
                        Text("持っている本は右上の「＋」から登録できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(viewModel.displayedItems) { item in
                        row(for: item)
                            .listRowBackground(Color("CardSurface"))
                    }
                    if viewModel.displayedItems.isEmpty {
                        ContentUnavailableView {
                            Label(
                                viewModel.searchText.isEmpty ? "本棚は空です" : "見つかりませんでした",
                                systemImage: "books.vertical"
                            )
                        } description: {
                            Text(
                                viewModel.searchText.isEmpty
                                    ? "「買う前チェック」タブでバーコードを読み取るか、下のボタンから持っている本を登録できます。"
                                    : "検索条件を変えてお試しください。"
                            )
                        } actions: {
                            if viewModel.searchText.isEmpty {
                                Button {
                                    showScanRegister = true
                                } label: {
                                    Label("本を登録する", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color("AppBackground"))
                .refreshable { await viewModel.refreshSeriesVolumeCounts() }
                .searchable(text: $viewModel.searchText, prompt: "タイトル・シリーズ名で検索")

                // F-07: 本棚画面にはバナー広告を表示する（買う前チェックの判定結果画面は非表示）
                adService.bannerView()
                    .frame(height: 50)
            }
            .navigationTitle("本棚")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("並び替え", selection: $viewModel.sortOption) {
                            ForEach(ShelfSortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label("並び替え", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("並び替え")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanRegister = true
                    } label: {
                        Label("登録", systemImage: "plus")
                            .foregroundStyle(Color("AppBackground"))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("本棚に登録")
                }
            }
            .sheet(isPresented: $showScanRegister) {
                ScanRegisterView(bookRepository: bookRepository, onFinished: {
                    viewModel.reload()
                    Task { await viewModel.refreshSeriesVolumeCounts() }
                })
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
            }
            .onAppear { viewModel.onAppear() }
            .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(for item: ShelfItem) -> some View {
        switch item {
        case .book(let book):
            bookRow(book)
        case .series(let series):
            NavigationLink {
                SeriesDetailView(
                    seriesKey: series.seriesKey,
                    viewModel: viewModel,
                    safariURL: $safariURL,
                    bookRepository: bookRepository
                )
            } label: {
                seriesSummaryRow(series)
            }
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack {
            NavigationLink {
                BookDetailView(book: book, bookRepository: bookRepository, onChange: viewModel.reload)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.body)
                    if book.unifiedStatus == .unread || book.unifiedStatus == .reading {
                        Text("\(viewModel.elapsedDays(for: book))日経過")
                            .font(.caption)
                            .foregroundStyle(viewModel.isOverdue(book) ? .orange : .secondary)
                    }
                }
            }
            Spacer()
            // 未購入の単行本は実物を持っていないため、Amazonでの購入導線を明示する。
            if book.unifiedStatus == .wishlist {
                Button {
                    safariURL = IdentifiableURL(url: viewModel.openStoreSearch(for: book))
                } label: {
                    Image(systemName: "cart.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("購入")
                // ステータス変更ピルとの誤タップを防ぐため間隔を空ける
                .padding(.trailing, 16)
            }
            StatusPillMenu(currentStatus: book.unifiedStatus) { newStatus in
                viewModel.changeStatus(bookID: book.id, to: newStatus)
            }
        }
    }

    private func seriesSummaryRow(_ series: SeriesProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(series.seriesName).font(.headline)
                Spacer()
                if let rate = series.completionRate {
                    Text("\(Int(rate * 100))%").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("既刊数不明").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let total = series.totalVolumes {
                SeriesStackedProgressBar(statusCounts: series.statusCounts, total: total)
            }

            if series.isNearCompletion {
                Text("🎉 あと少しで完結")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 6) {
                ForEach(series.statusCounts, id: \.status) { entry in
                    Text("\(entry.status.label)\(entry.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(StatusPillMenu.color(for: entry.status).opacity(0.15))
                        .foregroundStyle(StatusPillMenu.color(for: entry.status))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }
}
