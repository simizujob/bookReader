import SwiftUI

/// シリーズの既刊総数に対する内訳（読了/読書中/未読/未購入）を積み上げ棒グラフで表示する。
/// 単一の完結率バーだと「所持しているが積んだまま」なのか「まだ買っていない」のかが
/// 見分けられなかったため、ステータスごとに色分けして表示する。
struct SeriesStackedProgressBar: View {
    let statusCounts: [(status: UnifiedStatus, count: Int)]
    let total: Int

    /// 読了側から積むことで「進捗」が左側に見えるようにする。未購入は最後（右端）。
    private static let displayOrder: [UnifiedStatus] = [.finished, .reading, .unread, .wishlist]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Self.displayOrder, id: \.self) { status in
                    let count = countsByStatus[status] ?? 0
                    if count > 0 {
                        Self.barColor(for: status)
                            .frame(width: geometry.size.width * fraction(for: count))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    /// バー上の色。読了/読書中/未読は進捗（達成度）を表すためステータスピルと同じ鮮やかな色を
    /// 使うが、未購入は「まだ何もしていない」状態であり同じ鮮やかさだと進捗のように見えて
    /// 紛らわしいため、バーの上だけグレーで表現する（ピル自体の色はStatusPillMenu.color(for:)の
    /// ままタップ可能な要素として区別できるようにする）。
    private static func barColor(for status: UnifiedStatus) -> Color {
        status == .wishlist ? Color.secondary.opacity(0.35) : StatusPillMenu.color(for: status)
    }

    private var countsByStatus: [UnifiedStatus: Int] {
        Dictionary(uniqueKeysWithValues: statusCounts.map { ($0.status, $0.count) })
    }

    private func fraction(for count: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(count) / CGFloat(total)
    }

    private var accessibilityDescription: String {
        Self.displayOrder
            .compactMap { status -> String? in
                guard let count = countsByStatus[status], count > 0 else { return nil }
                return "\(status.label)\(count)"
            }
            .joined(separator: "、")
    }
}
