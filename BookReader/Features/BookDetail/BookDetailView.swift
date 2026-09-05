import SwiftUI
import MessageUI

struct BookDetailView: View {
    @StateObject private var viewModel: BookDetailViewModel
    @Environment(\.dismiss) private var dismiss
    private let onChange: () -> Void
    private let book: Book

    @State private var showMailCompose = false
    @State private var showMailUnavailableAlert = false

    init(book: Book, bookRepository: BookRepository, onChange: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: BookDetailViewModel(book: book, bookRepository: bookRepository))
        self.onChange = onChange
        self.book = book
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("タイトル", text: $viewModel.editableTitle)
                TextField("シリーズ名", text: $viewModel.editableSeriesName)
                TextField(
                    "巻数",
                    value: $viewModel.editableVolumeNumber,
                    format: .number
                )
                .keyboardType(.numberPad)
            }

            Section("ステータス") {
                Picker("所持ステータス", selection: $viewModel.editableStatus) {
                    Text("所持").tag(OwnershipStatus.owned)
                    Text("気になる").tag(OwnershipStatus.wishlist)
                }
                Picker("既読ステータス", selection: $viewModel.editableReadStatus) {
                    Text("未読").tag(ReadStatus.unread)
                    Text("読書中").tag(ReadStatus.reading)
                    Text("読了").tag(ReadStatus.finished)
                }
            }

            Section {
                Button("不具合を報告") {
                    if MFMailComposeViewController.canSendMail() {
                        showMailCompose = true
                    } else {
                        showMailUnavailableAlert = true
                    }
                }
            }

            Section {
                Button("削除する", role: .destructive) {
                    viewModel.showDeleteConfirm = true
                }
            }
        }
        .navigationTitle("本の詳細")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    if viewModel.save() {
                        onChange()
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            "この本を削除しますか？",
            isPresented: $viewModel.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                viewModel.delete()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onChange(of: viewModel.didDelete) { _, didDelete in
            if didDelete {
                onChange()
                dismiss()
            }
        }
        .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("メールが設定されていません", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("不具合報告の送信にはメールアプリの設定が必要です。設定アプリからメールアカウントを追加してください。")
        }
        .sheet(isPresented: $showMailCompose) {
            let report = BugReportComposer.report(for: book)
            MailComposeView(
                recipient: BugReportComposer.recipientEmail,
                subject: report.subject,
                body: report.body,
                onFinish: { showMailCompose = false }
            )
        }
    }
}
