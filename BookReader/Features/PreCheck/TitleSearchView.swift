import SwiftUI

/// タイトル検索で買う前チェックする入り口（Amazonを開いていない場合の代替手段）。
/// 候補を選ぶとISBNが確定し、onSelectで買う前チェック本体（PreCheckViewModel.judge）へ渡す。
/// 入力を止めてしばらく経つと自動で検索する（ライブ検索）。改行キーで即座に検索することもできる。
struct TitleSearchView: View {
    @StateObject private var viewModel = TitleSearchViewModel()
    @State private var searchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isSearching {
                    ProgressView()
                } else if viewModel.searchFailed {
                    Text("検索に失敗しました。通信環境をご確認のうえもう一度お試しください")
                        .foregroundStyle(.red)
                } else if viewModel.hasSearched && viewModel.candidates.isEmpty {
                    Text("見つかりませんでした").foregroundStyle(.secondary)
                } else if !viewModel.hasSearched {
                    Text("本のタイトルを入力してください").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.candidates) { candidate in
                        Button {
                            onSelect(candidate.isbn)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(candidate.title).foregroundStyle(.primary)
                                    if let volumeLabel = candidate.volumeLabel {
                                        Text(volumeLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                                if let creator = candidate.creator {
                                    Text(creator).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "タイトルで検索")
            .onSubmit(of: .search) {
                debounceTask?.cancel()
                viewModel.search(searchText)
            }
            .onChange(of: searchText) { _, newValue in
                debounceTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    viewModel.reset()
                    return
                }
                // 入力のたびに毎回検索すると無駄が多いため、入力が少し止まってから検索する。
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    viewModel.search(newValue)
                }
            }
            .navigationTitle("タイトルで検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
