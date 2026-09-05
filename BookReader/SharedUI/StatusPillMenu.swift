import SwiftUI

/// ステータス（未購入/未読/読書中/読了）の表示とワンタップメニューによる変更を提供する共通部品。
/// ピルをタップ→メニューから選択、の2タップでステータス変更が完了する。
struct StatusPillMenu: View {
    let currentStatus: UnifiedStatus
    let onChange: (UnifiedStatus) -> Void

    var body: some View {
        Menu {
            ForEach(UnifiedStatus.allCases, id: \.self) { status in
                Button {
                    onChange(status)
                } label: {
                    if status == currentStatus {
                        Label(status.label, systemImage: "checkmark")
                    } else {
                        Text(status.label)
                    }
                }
            }
        } label: {
            Text(currentStatus.label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Self.color(for: currentStatus).opacity(0.15))
                .foregroundStyle(Self.color(for: currentStatus))
                .clipShape(Capsule())
        }
        .accessibilityLabel("ステータス: \(currentStatus.label)")
    }

    static func color(for status: UnifiedStatus) -> Color {
        switch status {
        case .wishlist: return .blue
        case .unread: return .orange
        case .reading: return .purple
        case .finished: return .green
        }
    }
}
