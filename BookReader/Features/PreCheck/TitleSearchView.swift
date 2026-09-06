import SwiftUI

/// タイトル検索で買う前チェックする入り口（Amazonを開いていない場合の代替手段）。
/// 候補を選ぶとISBNが確定し、onSelectで買う前チェック本体（PreCheckViewModel.judge）へ渡す。
struct TitleSearchView: View {
    @StateObject private var viewModel = TitleSearchViewModel()
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isSearching {
                    ProgressView()
                } else if viewModel.hasSearched && viewModel.candidates.isEmpty {
                    Text("見つかりませんでした").foregroundStyle(.secondary)
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
                viewModel.search(searchText)
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
