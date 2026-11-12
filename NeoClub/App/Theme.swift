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

    /// App-wide tint: the club's AIO blue (#0082C6), lightened so it reads on the navy backgrounds.
    static let aioTint = Color(hex: 0x4DB8F0)

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

/// Colorful page backdrop in the style of the AIO website: brand-blue gradient, honeycomb texture,
/// and either official section art or blurred cover art fading in from the top.
struct AIOBackground: View {
    var art: String?
    var artworkURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2F7BC0), .aioOcean, .aioNavy], startPoint: .top, endPoint: .bottom)
            if let honeycomb = UIImage(named: "honeycomb") {
                Image(uiImage: honeycomb)
                    .resizable(resizingMode: .tile)
                    .opacity(0.04)
                    .blendMode(.screen)
            }
            header
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var header: some View {
        // Fixed-size containers so the scaled-to-fill art can never affect layout.
        if let artworkURL {
            Color.clear
                .frame(height: 520)
                .overlay {
                    // Blurred once from a 64 px copy instead of a live 50 pt blur over the full cover.
                    BlurredArtwork(url: artworkURL, radius: 10)
                        .opacity(0.75)
                }
                .clipped()
                .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        } else if let art {
            Color.clear
                .frame(height: 360)
                .overlay { BrandImage(name: art).scaledToFill() }
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
        }
    }
}

extension View {
    /// Applies the branded backdrop behind a screen (works for ScrollView and List).
    func aioBackground(_ art: String? = nil, artworkURL: URL? = nil) -> some View {
        scrollContentBackground(.hidden)
            // The native bar's progressive blur as content scrolls under it.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AIOBackground(art: art, artworkURL: artworkURL) }
    }

    /// Translucent row background so lists sit nicely on the colorful backdrop.
    func aioRow() -> some View {
        listRowBackground(Rectangle().fill(.white.opacity(0.08)))
    }

    /// Primary call-to-action in AIO yellow (like the website's nav bar) with navy text.
    func aioPrimaryButton() -> some View {
        buttonStyle(.glassProminent)
            .tint(.aioYellow)
            .foregroundStyle(Color.aioNavy)
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
