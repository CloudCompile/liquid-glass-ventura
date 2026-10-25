import Foundation

/// A byte-for-byte reproduction of the reference web library's render pipeline.
///
/// The Swift port is validated by rendering these cases with both
/// implementations and comparing sampled pixels. The case list is the single
/// source of truth: `liquidglass-render --crosscheck-configs` emits it as JSON
/// and `scripts/verify-crosscheck.sh` injects that JSON into the reference
/// page, so the two sides can never drift.
///
/// Each case gets its own 400x300 root with exactly one panel, so a
/// neighbouring panel's shadow can never leak into the crop and skew the
/// comparison.
public enum CrossCheck {

    /// Root size in CSS points, per case.
    public static let rootSize = LGSize(width: 400, height: 300)

    /// One comparison case.
    public struct Case: Sendable {
        public let name: String
        /// Panel frame in root coordinates.
        public let frame: LGRect
        public let config: GlassConfig
        /// Whether the port must match the reference pixel for pixel. `false`
        /// marks a case that documents a deliberate divergence, e.g. the
        /// textbook straight-alpha mode.
        public let expectsParity: Bool

        public init(name: String, frame: LGRect, config: GlassConfig, expectsParity: Bool = true) {
            self.name = name
            self.frame = frame
            self.config = config
            self.expectsParity = expectsParity
        }
    }

    /// Cases chosen to exercise every branch of the shader.
    public static let cases: [Case] = [
        Case(name: "default", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: .standard),
        Case(name: "specular", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            edgeHighlight: 0.25, specular: 1.0, fresnel: 0.6
        )),
        Case(name: "blur", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            blurAmount: 0.6
        )),
        Case(name: "tint", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            saturation: 0.5, tintStrength: 0.6, brightness: 0.15
        )),
        Case(name: "chroma", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            chromAberration: 0.5, distortion: 0.35
        )),
        Case(name: "dome", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            refraction: 0.9, cornerRadius: 60, zRadius: 60, shadowOpacity: 0.35, shadowSpread: 16, bevelMode: .dome
        )),
        Case(name: "shadow", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            shadowOpacity: 0.8, shadowSpread: 30, shadowOffsetY: 12
        )),
        Case(name: "opacity", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            opacity: 0.6
        )),
        Case(name: "sharp", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            refraction: 0, cornerRadius: 12, zRadius: 12, shadowOpacity: 0
        )),
        Case(name: "small-pill", frame: LGRect(x: 120, y: 110, width: 90, height: 44), config: GlassConfig(
            blurAmount: 0.2, refraction: 0.5, cornerRadius: 22, zRadius: 40, shadowOpacity: 0.4
        )),
        // Documents the divergence between faithful reference compositing and
        // textbook straight alpha; not expected to match.
        Case(name: "no-ref-alpha", frame: LGRect(x: 100, y: 80, width: 200, height: 120), config: GlassConfig(
            opacity: 0.6, referenceAlphaCompositing: false
        ), expectsParity: false),
    ]

    /// The backdrop every case samples: a red/green gradient, a blue base, and
    /// a 32-pixel checkerboard offset. Drawn with 2D canvas in the reference
    /// harness, reproduced exactly here.
    public static func backdrop() -> RGBAImage {
        let w = Int(rootSize.width)
        let h = Int(rootSize.height)
        var image = RGBAImage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let check = ((x >> 5) + (y >> 5)) % 2 == 0 ? 40 : 0
                image.setColor(x: x, y: y, RGBAColor(
                    r: Double(x) / 399.0,
                    g: Double(y) / 299.0,
                    b: Double(90 + check) / 255.0,
                    a: 1
                ))
            }
        }
        return image
    }

    /// Render one case and return the shaded panel plus its canvas size.
    public static func renderPanel(_ testCase: Case) -> (image: RGBAImage, canvasSize: LGSize) {
        let pad = glassShadowPad
        let pixelFrame = testCase.frame.roundedToPixels(scale: 1)
        let paddedFrame = LGRect(
            x: pixelFrame.x - pad,
            y: pixelFrame.y - pad,
            width: pixelFrame.width + pad * 2,
            height: pixelFrame.height + pad * 2
        )
        let crop = backdrop().cropped(to: paddedFrame, outOfBounds: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let shaded = SoftwareGlassRenderer(backdrop: crop)
            .renderPanel(config: testCase.config, size: testCase.frame.size, scale: 1)
        // With the faithful flag on, the browser will read the panel back as
        // `rgb * alpha, alpha²`, so convert before sampling.
        let comparable = testCase.config.referenceAlphaCompositing ? referenceCanvas(shaded) : shaded
        return (comparable, LGSize(width: paddedFrame.width, height: paddedFrame.height))
    }

    /// Normalized sample points: the panel interior and corners, then a
    /// vertical walk through the top edge where the shadow ramp and the
    /// anti-aliased mask live.
    public static let samplePoints: [(fx: Double, fy: Double)] = {
        var points: [(fx: Double, fy: Double)] = [
            (0.5, 0.5), (0.1, 0.5), (0.9, 0.5), (0.5, 0.1), (0.5, 0.9),
            (0.2, 0.2), (0.8, 0.8), (0.25, 0.75),
        ]
        var fy = 0.02
        while fy <= 0.3001 {
            points.append((0.5, (fy * 1000).rounded() / 1000))
            fy += 0.01
        }
        return points
    }()

    /// Convert a shaded panel into the exact bytes the reference library's
    /// canvas holds.
    ///
    /// The web library renders into a WebGL canvas declared
    /// `premultipliedAlpha: false`, but blends with
    /// `blendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)`. The canvas therefore ends
    /// up holding `rgb * alpha` in the colour channels and `alpha²` in the
    /// alpha channel, and the browser reads those bytes back as straight
    /// values. This is what `getImageData` returns from the reference, so it is
    /// what the port must be compared against.
    public static func referenceCanvas(_ panel: RGBAImage) -> RGBAImage {
        var out = panel
        for y in 0..<panel.height {
            for x in 0..<panel.width {
                let c = panel.color(x: x, y: y)
                out.setColor(x: x, y: y, RGBAColor(r: c.r * c.a, g: c.g * c.a, b: c.b * c.a, a: c.a * c.a))
            }
        }
        return out
    }

    /// Sample every case, returning the canvas size and `[fx, fy, r, g, b, a]`
    /// rows with 0...255 channel values.
    public static func samples() -> [(name: String, parity: Bool, canvasSize: LGSize, rows: [[Int]])] {
        cases.map { testCase in
            let (image, canvasSize) = renderPanel(testCase)
            let rows = samplePoints.map { point -> [Int] in
                let x = Int((point.fx * (canvasSize.width - 1)).rounded())
                let y = Int((point.fy * (canvasSize.height - 1)).rounded())
                let c = image.color(x: x, y: y)
                return [
                    Int((point.fx * 100).rounded()),
                    Int((point.fy * 100).rounded()),
                    Int((c.r * 255).rounded()),
                    Int((c.g * 255).rounded()),
                    Int((c.b * 255).rounded()),
                    Int((c.a * 255).rounded()),
                ]
            }
            return (testCase.name, testCase.expectsParity, canvasSize, rows)
        }
    }

    /// The case list as JSON, for the reference harness to consume.
    public static func configsJSON() -> String {
        let entries = cases.map { testCase -> String in
            let fields: [String] = [
                "\"name\":\"\(testCase.name)\"",
                "\"frame\":[\(testCase.frame.x),\(testCase.frame.y),\(testCase.frame.width),\(testCase.frame.height)]",
                "\"parity\":\(testCase.expectsParity)",
                "\"config\":{\(configFields(testCase.config))}",
            ]
            return "{" + fields.joined(separator: ",") + "}"
        }
        return "{\"root\":[\(rootSize.width),\(rootSize.height)],\"cases\":[" + entries.joined(separator: ",") + "]}"
    }

    private static func configFields(_ c: GlassConfig) -> String {
        var fields: [String] = [
            "\"blurAmount\":\(num(c.blurAmount))",
            "\"refraction\":\(num(c.refraction))",
            "\"chromAberration\":\(num(c.chromAberration))",
            "\"edgeHighlight\":\(num(c.edgeHighlight))",
            "\"specular\":\(num(c.specular))",
            "\"fresnel\":\(num(c.fresnel))",
            "\"distortion\":\(num(c.distortion))",
            "\"cornerRadius\":\(num(c.cornerRadius))",
            "\"zRadius\":\(num(c.zRadius))",
            "\"opacity\":\(num(c.opacity))",
            "\"saturation\":\(num(c.saturation))",
            "\"tintStrength\":\(num(c.tintStrength))",
            "\"brightness\":\(num(c.brightness))",
            "\"shadowOpacity\":\(num(c.shadowOpacity))",
            "\"shadowSpread\":\(num(c.shadowSpread))",
            "\"shadowOffsetY\":\(num(c.shadowOffsetY))",
            "\"floating\":\(c.floating)",
            "\"button\":\(c.button)",
            "\"bevelMode\":\(c.bevelMode.rawValue)",
        ]
        if let tint = c.tintColor {
            fields.append("\"tintColor\":[\(num(tint.r)),\(num(tint.g)),\(num(tint.b))]")
        }
        return fields.joined(separator: ",")
    }

    private static func num(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// Sampled results as JSON, matching the shape the reference harness emits.
    public static func samplesJSON() -> String {
        let entries = samples().map { entry -> String in
            let rows = entry.rows.map { "[" + $0.map(String.init).joined(separator: ",") + "]" }
            return "{\"name\":\"\(entry.name)\",\"parity\":\(entry.parity),\"canvas\":{\"w\":\(Int(entry.canvasSize.width)),\"h\":\(Int(entry.canvasSize.height))},\"samples\":["
                + rows.joined(separator: ",") + "]}"
        }
        return "{\"cases\":[" + entries.joined(separator: ",") + "]}"
    }
}
