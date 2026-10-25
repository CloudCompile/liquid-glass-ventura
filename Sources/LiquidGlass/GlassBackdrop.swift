#if os(macOS)
import AppKit
import CoreGraphics
import LiquidGlassCore

/// Bridges AppKit bitmaps to the core's `RGBAImage` and back.
enum GlassBitmap {

    /// Snapshot `rect` (in `view`'s own coordinate space) of what is currently
    /// drawn there, excluding `excluding` and its subtree.
    ///
    /// This is what gives the port a real backdrop to refract: the same pixels
    /// the user sees behind the panel. The glass view is hidden for the
    /// duration of the capture so it does not sample itself.
    static func capture(behind view: NSView, rect: CGRect, excluding: NSView?, scale: CGFloat) -> RGBAImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let wasHidden = excluding?.isHidden
        excluding?.isHidden = true
        defer { excluding?.isHidden = wasHidden ?? false }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        rep.size = rect.size
        view.cacheDisplay(in: rect, to: rep)

        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        // Normalise to a known layout so the byte order is predictable.
        guard let srgb = NSColorSpace.sRGB.cgColorSpace else { return nil }
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }

        guard let cgImage = rep.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // `premultipliedLast` is RGBA with premultiplied alpha; the core works
        // in straight alpha, so undo the premultiplication.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[i + 3]
            if alpha == 0 || alpha == 255 { continue }
            let a = Double(alpha) / 255
            for channel in 0..<3 {
                pixels[i + channel] = UInt8(min(255, Double(pixels[i + channel]) / a + 0.5))
            }
        }

        return RGBAImage(width: pixelWidth, height: pixelHeight, pixels: pixels)
    }

    /// Convert a core image back into a `CGImage` for drawing.
    static func cgImage(from image: RGBAImage) -> CGImage? {
        guard !image.isEmpty else { return nil }
        // Straight alpha in, premultiplied out, because that is what the
        // compositor expects.
        var pixels = image.pixels
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            if a >= 1 { continue }
            for channel in 0..<3 {
                pixels[i + channel] = UInt8(min(255, Double(pixels[i + channel]) * a + 0.5))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// Where a glass surface takes its backdrop from.
///
/// The ported optical model needs the pixels behind the panel to refract them.
/// Getting those pixels differs by host, so the caller picks the source that
/// matches where the glass is being used.
public enum GlassBackdrop {
    /// Let the system draw the blurred backdrop with `NSVisualEffectView`, and
    /// composite the ported highlights, tint, and shadow on top.
    ///
    /// This is the default because it needs no snapshot and cannot pick up
    /// content drawn in front of the glass. The refraction of fine detail is
    /// approximated rather than exact, since the true backdrop is never read
    /// back.
    case nativeBlur

    /// Refract a specific image, such as the desktop wallpaper. This is the
    /// exact reference behaviour: every pixel behind the panel is sampled.
    case image(CGImage)

    /// Refract a flat colour. Useful for previews and tests.
    case color(RGBColor)

    /// Refract a live AppKit view's contents.
    ///
    /// Correct only when the glass is drawn behind that view, which is the
    /// normal AppKit arrangement. Do not pass a view that contains the glass.
    case view(NSView)
}

extension RGBAImage {
    /// Draw a `CGImage` into a straight-alpha buffer of the requested size,
    /// scaling it to fill (aspect-fill) exactly as the reference library's
    /// background cover mode does.
    convenience init?(cgImage: CGImage, width: Int, height: Int) {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            // Aspect-fill: scale so the image covers the box, then centre it.
            let imageAspect = Double(cgImage.width) / Double(cgImage.height)
            let boxAspect = Double(width) / Double(height)
            var drawWidth = Double(width)
            var drawHeight = Double(height)
            if imageAspect > boxAspect {
                drawWidth = Double(height) * imageAspect
            } else {
                drawHeight = Double(width) / imageAspect
            }
            let rect = CGRect(
                x: (Double(width) - drawWidth) / 2,
                y: (Double(height) - drawHeight) / 2,
                width: drawWidth,
                height: drawHeight
            )
            context.interpolationQuality = .high
            context.draw(cgImage, in: rect)
            return true
        }
        guard drawn else { return nil }

        // Undo the premultiplication so the core sees straight alpha.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[i + 3]
            if alpha == 0 || alpha == 255 { continue }
            let a = Double(alpha) / 255
            for channel in 0..<3 {
                pixels[i + channel] = UInt8(min(255, Double(pixels[i + channel]) / a + 0.5))
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}

#endif
