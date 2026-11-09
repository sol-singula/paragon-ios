import SwiftUI
import UIKit
import ImageIO

/// Pixel size of an image's bytes, without decoding it.
enum ImageInfo {
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }

    /// A GIF's frames as one animated UIImage; anything else as a still.
    static func image(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var total: Double = 0
        for i in 0..<min(count, 300) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            total += d < 0.02 ? 0.1 : d
        }
        return frames.isEmpty ? UIImage(data: data) : UIImage.animatedImage(with: frames, duration: total)
    }
}

/// Images by URL, kept in memory for the session.
actor ImageCache {
    static let shared = ImageCache()
    private let store = NSCache<NSURL, UIImage>()
    private var waiting: [URL: Task<UIImage?, Never>] = [:]

    /// A picture we already hold (one we just sent), so its link shows it
    /// at once instead of loading it again.
    func put(_ url: URL, _ image: UIImage) {
        store.setObject(image, forKey: url as NSURL)
    }

    func image(_ url: URL) async -> UIImage? {
        if let hit = store.object(forKey: url as NSURL) { return hit }
        if let w = waiting[url] { return await w.value }
        let t = Task<UIImage?, Never> {
            guard let r = try? await URLSession.shared.data(from: url),
                  ((r.1 as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
            return ImageInfo.image(r.0)
        }
        waiting[url] = t
        let img = await t.value
        waiting[url] = nil
        if let img { store.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// A picture from a URL that fills the frame it is given. GIFs play.
struct RemoteImage: View {
    let url: URL?
    var fill = true

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                if image.images != nil {
                    AnimatedImageView(image: image, fill: fill)
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                }
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Theme.muted)
            } else {
                ProgressView().tint(Theme.muted)
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            image = await ImageCache.shared.image(url)
            failed = image == nil
        }
    }
}

/// A UIImageView, for an animated image (SwiftUI's Image shows one frame).
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var fill = true

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.clipsToBounds = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        v.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        if v.image !== image { v.image = image; v.startAnimating() }
    }
}

/// The whole picture over everything: pinch to zoom, drag when zoomed,
/// double-tap to zoom in or back, the cross or a swipe down to close.
struct ImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(url: url, fill: false)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in scale = max(1, min(6, lastScale * v)) }
                        .onEnded { _ in lastScale = scale; if scale <= 1 { reset() } }
                        .simultaneously(with: DragGesture()
                            .onChanged { v in
                                if scale > 1 {
                                    offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                                } else {
                                    offset = CGSize(width: 0, height: max(0, v.translation.height))
                                }
                            }
                            .onEnded { v in
                                if scale > 1 { lastOffset = offset }
                                else if v.translation.height > 120 { dismiss() }
                                else { withAnimation(.snappy) { offset = .zero } }
                            })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                    }
                }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(.black.opacity(0.55)))
            }
            .padding(.trailing, 16).padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// A URL that can drive `.fullScreenCover(item:)`.
struct ViewedImage: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}
