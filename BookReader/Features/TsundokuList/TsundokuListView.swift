import SwiftUI

struct TsundokuListView: View {
    @StateObject private var viewModel: TsundokuListViewModel
    @State private var showScanRegister = false
    private let bookRepository: BookRepository
    private let adService: AdServing

    init(bookRepository: BookRepository, adService: AdServing = AdService()) {
        self.bookRepository = bookRepository
        self.adService = adService
        _viewModel = StateObject(wrappedValue: TsundokuListViewModel(bookRepository: bookRepository))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("状態", selection: $viewModel.segment) {
                    Text("未読").tag(ReadStatus.unread)
                    Text("読書中").tag(ReadStatus.reading)
                    Text("読了").tag(ReadStatus.finished)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: viewModel.segment) { _, _ in viewModel.reload() }

                List {
                    ForEach(viewModel.books) { book in
                        NavigationLink {
                            BookDetailView(book: book, bookRepository: bookRepository, onChange: viewModel.reload)
                        } label: {
                            row(for: book)
                        }
                    }
                }
                .listStyle(.plain)

                // F-07: 積読リストにはバナー広告を表示する（気になる本棚は非表示）
                adService.bannerView()
                    .frame(height: 50)
            }
            .navigationTitle("積読リスト（\(viewModel.books.count)冊）")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanRegister = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("本棚に登録")
                }
            }
            .sheet(isPresented: $showScanRegister) {
                ScanRegisterView(bookRepository: bookRepository, onFinished: viewModel.reload)
            }
            .onAppear { viewModel.onAppear() }
            .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func row(for book: Book) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.body)
                Text("\(viewModel.elapsedDays(for: book))日経過")
                    .font(.caption)
                    .foregroundStyle(viewModel.isOverdue(book) ? .orange : .secondary)
            }
            Spacer()
            if viewModel.segment != .finished {
                Button {
                    viewModel.markAsFinished(book)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
