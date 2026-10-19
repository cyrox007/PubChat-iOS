import SwiftUI
import UIKit

/// Shared visual contract of the 18 October PubChat mobile design boards.
/// Functional capabilities are still controlled by the backend and feature flags.
enum PubChatDesign {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let primary = adaptive(
        light: UIColor(red: 99/255, green: 71/255, blue: 245/255, alpha: 1),
        dark: UIColor(red: 154/255, green: 134/255, blue: 255/255, alpha: 1)
    )
    static let deepIndigo = Color(red: 52/255, green: 33/255, blue: 164/255)
    static let cyan = adaptive(
        light: UIColor(red: 18/255, green: 188/255, blue: 213/255, alpha: 1),
        dark: UIColor(red: 84/255, green: 215/255, blue: 233/255, alpha: 1)
    )
    static let background = adaptive(
        light: UIColor(red: 246/255, green: 247/255, blue: 255/255, alpha: 1),
        dark: UIColor(red: 13/255, green: 17/255, blue: 37/255, alpha: 1)
    )
    static let surface = adaptive(
        light: .white,
        dark: UIColor(red: 23/255, green: 29/255, blue: 52/255, alpha: 1)
    )
    static let ink = adaptive(
        light: UIColor(red: 24/255, green: 32/255, blue: 61/255, alpha: 1),
        dark: UIColor(red: 245/255, green: 246/255, blue: 255/255, alpha: 1)
    )
    static let secondaryInk = adaptive(
        light: UIColor(red: 105/255, green: 115/255, blue: 143/255, alpha: 1),
        dark: UIColor(red: 180/255, green: 191/255, blue: 219/255, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor(red: 226/255, green: 230/255, blue: 245/255, alpha: 1),
        dark: UIColor(red: 52/255, green: 61/255, blue: 89/255, alpha: 1)
    )
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
        .background(PubChatDesign.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}