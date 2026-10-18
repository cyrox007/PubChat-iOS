import SwiftUI

/// PubChat visual baseline — 2026-10-18.
/// Semantic palette shared with Android MaterialTheme and Web --ui-* tokens.
enum PubChatDesign {
    static let primary = Color(red: 99/255, green: 71/255, blue: 245/255)
    static let primaryDark = Color(red: 154/255, green: 134/255, blue: 255/255)
    static let cyan = Color(red: 18/255, green: 188/255, blue: 213/255)
    static let background = Color(red: 246/255, green: 247/255, blue: 255/255)
    static let darkBackground = Color(red: 13/255, green: 17/255, blue: 37/255)
    static let textSecondary = Color(red: 105/255, green: 115/255, blue: 143/255)
    static let danger = Color(red: 223/255, green: 75/255, blue: 100/255)

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 113/255, green: 73/255, blue: 255/255),
            Color(red: 77/255, green: 84/255, blue: 247/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PubChatPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(.white)
            .background(PubChatDesign.heroGradient, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "\(title), загрузка" : title)
    }
}

struct PubChatLoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle().fill(.quaternary).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary).frame(height: 13)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary).frame(width: 160, height: 11)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(20)
        .accessibilityLabel("Загрузка данных")
    }
}

struct PubChatEmptyView: View {
    let title: String
    let details: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(details))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PubChatBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(PubChatDesign.heroGradient)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 88, height: 88)
        .accessibilityLabel("PubChat")
    }
}
