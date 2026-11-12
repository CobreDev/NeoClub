import CoreImage
import ImageIO
import SwiftUI
import UIKit

/// Shared artwork loader: a large on-disk HTTP cache, decoding scaled down to the size actually shown (a 150 pt card
/// doesn't decode a 1400 px cover), and an in-memory cache of the decoded images so covers appear instantly when they
/// come back on screen. Also makes the soft blurred backgrounds from a tiny copy of the art, once, instead of
/// blurring a full-size image on every frame.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]
    private let context = CIContext(options: [.cacheIntermediates: false])

    private init() {
        memory.totalCostLimit = 120 * 1024 * 1024
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork")
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024, directory: dir)
        // Artwork URLs don't change content, so a cached copy is always good.
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Decode sizes, in pixels: the smallest bucket that covers what's on screen.
    static let buckets = [128, 256, 512, 1024, 2048]
    static func bucket(forPixels pixels: CGFloat) -> Int { buckets.first { CGFloat($0) >= pixels } ?? 2048 }

    private func key(_ url: URL, _ pixels: Int) -> NSString { "\(pixels)|\(url.absoluteString)" as NSString }

    /// An already-decoded image at least this big, if there is one (instant, for drawing without a placeholder).
    func cached(_ url: URL, pixels: Int) -> UIImage? {
        for b in Self.buckets where b >= pixels {
            if let image = memory.object(forKey: key(url, b)) { return image }
        }
        return nil
    }

    /// The image decoded to fit `pixels` on its longer side.
    func image(_ url: URL, pixels: Int) async -> UIImage? {
        if let hit = cached(url, pixels: pixels) { return hit }
        let k = key(url, pixels)
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = inFlight[k] { return running }
            let t = Task.detached(priority: .userInitiated) { [session] () -> UIImage? in
                guard let (data, response) = try? await session.data(from: url),
                      ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
                return Self.downsample(data, pixels: pixels)
            }
            inFlight[k] = t
            return t
        }
        let image = await task.value
        lock.withLock { inFlight[k] = nil }
        if let image { memory.setObject(image, forKey: k, cost: Self.cost(image)) }
        return image
    }

    private static func cost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// Decodes straight to the target size (ImageIO thumbnails never hold the full-size bitmap).
    static func downsample(_ data: Data, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Blurred backgrounds

    /// A soft, blurred version of the art for full-screen backgrounds: blurred once at 64 px, then drawn scaled up
    /// (which stays smooth), rather than a live blur over a full-size image. `radius` is in the 64 px image's pixels.
    func blurred(_ url: URL, radius: Double, saturation: Double = 1) async -> UIImage? {
        let k = "blur|\(radius)|\(saturation)|\(url.absoluteString)" as NSString
        if let hit = memory.object(forKey: k) { return hit }
        guard let small = await image(url, pixels: 64)?.cgImage else { return nil }
        let result: UIImage? = await Task.detached(priority: .userInitiated) { [context] in
            let input = CIImage(cgImage: small)
            var output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
            if saturation != 1 {
                output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
            }
            guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let result { memory.setObject(result, forKey: k, cost: Self.cost(result)) }
        return result
    }

    func cachedBlurred(_ url: URL, radius: Double, saturation: Double = 1) -> UIImage? {
        memory.object(forKey: "blur|\(radius)|\(saturation)|\(url.absoluteString)" as NSString)
    }
}

/// `AsyncImage` replacement backed by `ImagePipeline`: decodes at the size it's drawn, keeps decoded images in
/// memory, and shows a cached image immediately (no placeholder flash) when one exists.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    /// Decode size in pixels; measured from the view's size when nil.
    var pixels: Int?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var size: CGSize = .zero
    @State private var loaded: (url: URL, image: UIImage)?

    private var wantedPixels: Int {
        pixels ?? ImagePipeline.bucket(forPixels: max(size.width, size.height) * displayScale)
    }

    var body: some View {
        let shown: UIImage? = url.flatMap { url in
            if let loaded, loaded.url == url { return loaded.image }
            return ImagePipeline.shared.cached(url, pixels: wantedPixels)
        }
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: "\(url?.absoluteString ?? "")|\(wantedPixels)|\(size == .zero && pixels == nil)") {
            guard let url, pixels != nil || size != .zero else { return }
            if let hit = ImagePipeline.shared.cached(url, pixels: wantedPixels) {
                loaded = (url, hit)
                return
            }
            guard let image = await ImagePipeline.shared.image(url, pixels: wantedPixels), !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { loaded = (url, image) }
        }
    }
}

/// A full-screen soft background made from the art (see `ImagePipeline.blurred`).
struct BlurredArtwork: View {
    let url: URL?
    var radius: Double = 7
    var saturation: Double = 1

    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        // A new URL for the same art (e.g. the restored episode's details replacing its saved copy) keeps showing
        // the last backdrop until the new one is ready, rather than dropping to the plain fill for a moment.
        let shown: UIImage? = url.flatMap { url in
            if let loaded, loaded.url == url { return loaded.image }
            return ImagePipeline.shared.cachedBlurred(url, radius: radius, saturation: saturation)
        } ?? loaded?.image
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().interpolation(.high).scaledToFill()
            }
        }
        .task(id: url) {
            guard let url else { return }
            guard let image = await ImagePipeline.shared.blurred(url, radius: radius, saturation: saturation),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { loaded = (url, image) }
        }
    }
}
