import SwiftUI
import MessageUI

/// シリーズ内の巻ごとのステータスを一覧表示・変更する画面。
/// 本棚一覧のシリーズカードをタップした先に表示される。
/// seriesKeyで参照し、viewModel.seriesCardsから毎回最新の状態を引くことで、
/// ステータス変更や既刊数の手動入力が即座に画面へ反映されるようにする。
struct SeriesDetailView: View {
    let seriesKey: String
    @ObservedObject var viewModel: ShelfViewModel
    @Binding var safariURL: IdentifiableURL?
    let bookRepository: BookRepository
    @Environment(\.dismiss) private var dismiss

    @State private var showVolumeCountEntry = false
    @State private var volumeCountInput = ""
    @State private var showDeleteConfirm = false
    @State private var showMailCompose = false
    @State private var showMailUnavailableAlert = false

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
                if let rate = series.completionRate, let total = series.totalVolumes {
                    SeriesStackedProgressBar(statusCounts: series.statusCounts, total: total)
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
            .listRowBackground(Color("CardSurface"))

            Section("巻ごとのステータス") {
                ForEach(series.volumes) { entry in
                    volumeRow(entry)
                }
            }
            .listRowBackground(Color("CardSurface"))

            Section {
                Button("シリーズの不具合を報告") {
                    if MFMailComposeViewController.canSendMail() {
                        showMailCompose = true
                    } else {
                        showMailUnavailableAlert = true
                    }
                }
            }
            .listRowBackground(Color("CardSurface"))

            Section {
                Button("シリーズを削除する", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
            .listRowBackground(Color("CardSurface"))
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground"))
        .navigationTitle(series.seriesName)
        .alert("メールが設定されていません", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("不具合報告の送信にはメールアプリの設定が必要です。設定アプリからメールアカウントを追加してください。")
        }
        .sheet(isPresented: $showMailCompose) {
            let report = BugReportComposer.report(for: series)
            MailComposeView(
                recipient: BugReportComposer.recipientEmail,
                subject: report.subject,
                body: report.body,
                onFinish: { showMailCompose = false }
            )
        }
        .confirmationDialog(
            "「\(series.seriesName)」を削除しますか？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                viewModel.deleteSeries(series)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("シリーズ内の全ての巻（\(series.volumes.count)件）が削除されます。この操作は取り消せません。")
        }
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
                    Image(systemName: "cart.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
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
