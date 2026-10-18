import SwiftUI

/// Shared visual contract of the 18 October PubChat mobile design boards.
/// Functional capabilities are still controlled by the backend and feature flags.
enum PubChatDesign {
    static let primary = Color(red: 96/255, green: 69/255, blue: 246/255)
    static let deepIndigo = Color(red: 52/255, green: 33/255, blue: 164/255)
    static let cyan = Color(red: 6/255, green: 199/255, blue: 236/255)
    static let background = Color(red: 247/255, green: 248/255, blue: 254/255)
    static let ink = Color(red: 17/255, green: 25/255, blue: 54/255)
    static let secondaryInk = Color(red: 100/255, green: 113/255, blue: 142/255)
    static let border = Color(red: 231/255, green: 234/255, blue: 246/255)
    static let danger = Color(red: 240/255, green: 68/255, blue: 97/255)
    static let success = Color(red: 22/255, green: 164/255, blue: 108/255)
    static let darkBackground = Color(red: 15/255, green: 20/255, blue: 38/255)
    static let darkSurface = Color(red: 25/255, green: 31/255, blue: 53/255)
    static let brandGradient = LinearGradient(
        colors: [primary, Color(red: 125/255, green: 93/255, blue: 255/255), cyan],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct PubChatLoadingView: View {
    var body: some View {
        ZStack {
            PubChatDesign.background.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(PubChatDesign.brandGradient)
                        .frame(width: 92, height: 92)
                    Text("P").font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("PubChat").font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(PubChatDesign.ink)
                Text("Люди. Сообщества. Больше возможностей.")
                    .font(.subheadline).foregroundStyle(PubChatDesign.secondaryInk)
                    .multilineTextAlignment(.center)
                ProgressView("Восстанавливаем сеанс…")
                    .tint(PubChatDesign.primary)
                    .padding(.top, 12)
            }
            .padding(28)
        }
    }
}

struct PubChatStateCard: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(PubChatDesign.primary)
                .frame(width: 86, height: 86)
                .background(PubChatDesign.primary.opacity(0.08), in: Circle())
            Text(title).font(.title3.bold()).foregroundStyle(PubChatDesign.ink)
            Text(message).font(.subheadline).foregroundStyle(PubChatDesign.secondaryInk)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent).tint(PubChatDesign.primary)
                    .frame(minHeight: 44)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }
}