import SwiftUI

/// AIO Club brand palette, taken from the official app's color constants.
extension Color {
    static let aioNavy = Color(hex: 0x1C3872)
    static let aioDeepNavy = Color(hex: 0x143776)
    static let aioBlue = Color(hex: 0x0082C6)
    static let aioOcean = Color(hex: 0x005E9A)
    static let aioSky = Color(hex: 0x9ED8F0)
    static let aioYellow = Color(hex: 0xF9D548)
    static let aioRed = Color(hex: 0xD80000)

    /// Tint that stays legible on both light and dark backgrounds.
    static let aioTint = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(Color.aioSky) : UIColor(Color.aioBlue) })

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Official AIO typefaces: Jacoby for display, Univers for text.
extension Font {
    static func jacoby(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("JacobyICGBlack", size: size, relativeTo: style)
    }

    static func univers(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Univers", size: size, relativeTo: style)
    }

    static func universBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Univers-Bold", size: size, relativeTo: style)
    }
}

/// Section header in the Apple Music style, set in Univers Bold.
struct ShelfHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.universBold(22, relativeTo: .title2))
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .font(.univers(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// Bundled brand image (club logo, hero art) loaded from the app bundle by file name.
struct BrandImage: View {
    let name: String
    var body: some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image).resizable()
        } else {
            Color.aioNavy
        }
    }
}

extension URL {
    /// Builds a URL from API strings, which sometimes contain unescaped spaces.
    static func aio(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        if let url = URL(string: string) { return url }
        return URL(string: string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? string)
    }
}

extension Int {
    /// Formats milliseconds as "26 min" or "1 hr 5 min".
    var msDurationText: String {
        let minutes = Swift.max(1, self / 60_000)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}
