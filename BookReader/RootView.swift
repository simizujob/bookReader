import SwiftUI

/// 買う前チェック / 本棚（積読リスト＋気になる本棚 統合）の2タブ構成。
struct RootView: View {
    let bookRepository: BookRepository
    @State private var selection: Tab = .preCheck

    enum Tab {
        case preCheck, shelf
    }

    var body: some View {
        TabView(selection: $selection) {
            PreCheckView(bookRepository: bookRepository)
                .tabItem { Label("買う前チェック", systemImage: "barcode.viewfinder") }
                .tag(Tab.preCheck)

            ShelfView(bookRepository: bookRepository)
                .tabItem { Label("本棚", systemImage: "books.vertical") }
                .tag(Tab.shelf)
        }
        .onOpenURL { url in
            if url.host == "precheck" {
                selection = .preCheck
            }
        }
    }
}
