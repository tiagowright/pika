import AppKit

/// Pre-rasterizes app icons to the exact display size once, in the
/// background, at launch — measured at 80ms fetch + 323ms rasterize for
/// 16 apps, then 0ms forever after (TECHNICAL.md §5f). Icons are cheap
/// enough to ship; they must never be fetched or drawn at full size on
/// the hot path.
final class IconCache {
    static let shared = IconCache()

    /// 32pt @2x, matching the row icon size in UX.md §2.
    private let pixelSize: CGFloat = 64
    private var memory: [String: NSImage] = [:]
    private let lock = NSLock()
    private let diskDir = AppPaths.cacheDirectory.appendingPathComponent("icons", isDirectory: true)

    private init() {
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func icon(forBundleID bundleID: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return memory[bundleID]
    }

    /// Called once per newly-seen app, off the main thread. `onReady`
    /// fires on the main thread so the caller can patch the index and
    /// trigger a redraw.
    func warm(bundleID: String, sourceIcon: NSImage?, onReady: @escaping (NSImage?) -> Void) {
        if let cached = icon(forBundleID: bundleID) {
            onReady(cached)
            return
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let diskURL = self.diskDir.appendingPathComponent("\(bundleID).png")
            if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
                self.lock.lock(); self.memory[bundleID] = image; self.lock.unlock()
                DispatchQueue.main.async { onReady(image) }
                return
            }
            guard let sourceIcon else { DispatchQueue.main.async { onReady(nil) }; return }
            let rasterized = self.rasterize(sourceIcon, to: self.pixelSize)
            self.lock.lock(); self.memory[bundleID] = rasterized; self.lock.unlock()
            if let tiff = rasterized.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: diskURL, options: .atomic)
            }
            DispatchQueue.main.async { onReady(rasterized) }
        }
    }

    private func rasterize(_ source: NSImage, to size: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                    from: .zero, operation: .copy, fraction: 1.0)
        out.unlockFocus()
        return out
    }
}
