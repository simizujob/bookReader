import SwiftUI

/// 基本設計書2.1: 常設タブ3つ（買う前チェック／積読リスト／気になる本棚）。
struct RootView: View {
    let bookRepository: BookRepository
    @State private var selection: Tab = .preCheck

    enum Tab {
        case preCheck, tsundokuList, wishShelf
    }

    var body: some View {
        TabView(selection: $selection) {
            PreCheckView(bookRepository: bookRepository)
                .tabItem { Label("買う前チェック", systemImage: "barcode.viewfinder") }
                .tag(Tab.preCheck)

            TsundokuListView(bookRepository: bookRepository)
                .tabItem { Label("積読リスト", systemImage: "books.vertical") }
                .tag(Tab.tsundokuList)

            WishShelfView(bookRepository: bookRepository)
                .tabItem { Label("気になる本棚", systemImage: "bookmark") }
                .tag(Tab.wishShelf)
        }
        .onOpenURL { url in
            if url.host == "precheck" {
                selection = .preCheck
            }
        }
    }
}
