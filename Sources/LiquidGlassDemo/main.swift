#if os(macOS)
import SwiftUI
import AppKit
import LiquidGlass
import LiquidGlassCore

/// A SwiftUI playground for the ported material.
///
/// Run it on any macOS from Ventura up: on macOS 26 and later the system
/// material is available, and on earlier systems every surface is drawn by the
/// ported optical model.
@main
struct LiquidGlassDemoApp: App {
    var body: some Scene {
        WindowGroup("Liquid Glass") {
            PlaygroundView()
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct PlaygroundView: View {
    @State private var refraction = 0.62
    @State private var blur = 0.30
    @State private var chroma = 0.05
    @State private var specular = 0.35
    @State private var radius = 18.0
    @State private var bevelMode = GlassBevelMode.biconvex
    @State private var shape: ShapeChoice = .capsule

    enum ShapeChoice: String, CaseIterable, Identifiable {
        case capsule = "Capsule"
        case rounded = "Rounded"
        case circle = "Circle"
        var id: String { rawValue }
    }

    private var glassShape: GlassShape {
        switch shape {
        case .capsule: return .capsule
        case .rounded: return .rect(cornerRadius: radius)
        case .circle: return .circle
        }
    }

    /// The optics the sliders currently describe, starting from the regular
    /// material so the defaults stay the ones the system would use.
    private var sliderConfig: GlassConfig {
        var config = GlassConfig.materialRegular
        config.refraction = refraction
        config.blurAmount = blur
        config.chromAberration = chroma
        config.specular = specular
        config.bevelMode = bevelMode
        if case .rect(let corner) = glassShape {
            config.cornerRadius = corner
        }
        return config
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                stage
                controls.frame(width: 270)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Stage

    private var stage: some View {
        VStack(spacing: 26) {
            Spacer()

            Text("LIQUID GLASS")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .liquidGlass(.clear, in: glassShape)

            HStack(spacing: 18) {
                Button("Cancel") {}
                    .buttonStyle(.liquidGlass)
                Button("Confirm") {}
                    .buttonStyle(.liquidGlassProminent)
                Button("Clear") {}
                    .buttonStyle(.liquidGlassClear)
            }

            HStack(spacing: 18) {
                ForEach(["scribble.variable", "eraser.fill", "paintbrush.fill"], id: \.self) { name in
                    Image(systemName: name)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .liquidGlass(.regular.interactive(), in: .circle)
                }
            }

            // The surfaces the sliders drive: a wide panel of the raw config,
            // and a merged pair inside a container.
            Text("Slider-driven optics")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 320, height: 92)
                .liquidGlass(config: sliderConfig, in: glassShape)

            // The chips are 18 pt apart and the container merges anything
            // closer than its `spacing`, so these two draw as one panel.
            GlassEffectContainer(spacing: 26) {
                HStack(spacing: 18) {
                    chip("Sub", "In")
                    chip("Blur", "Strength")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }

    private func chip(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).opacity(0.7)
        }
        .frame(width: 118, height: 66)
        .liquidGlass(.regular, in: glassShape)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optics").font(.headline)
            slider("Refraction", $refraction, 0...1.2)
            slider("Blur", $blur, 0...1)
            slider("Chromatic", $chroma, 0...0.3)
            slider("Specular", $specular, 0...1)
            slider("Radius", $radius, 0...80)

            Picker("Shape", selection: $shape) {
                ForEach(ShapeChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Bevel", selection: $bevelMode) {
                Text("Biconvex").tag(GlassBevelMode.biconvex)
                Text("Dome").tag(GlassBevelMode.dome)
            }
            .pickerStyle(.segmented)

            Spacer()

            Text("On macOS 13–15 every surface is drawn by the ported optical model. On macOS 26 and later the system material takes over.")
                .font(.caption2)
                .opacity(0.6)
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .opacity(0.6)
            }
            Slider(value: value, in: range)
        }
    }
}

/// A Ventura-style mesh gradient behind the glass, so refraction is visible.
struct MeshGradientBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.12, blue: 0.28),
                        Color(red: 0.35, green: 0.12, blue: 0.36),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(red: 0.96, green: 0.45, blue: 0.30).opacity(0.85))
                    .frame(width: size.width * 0.6)
                    .blur(radius: 90)
                    .offset(x: -size.width * 0.22, y: -size.height * 0.25)
                Circle()
                    .fill(Color(red: 0.20, green: 0.72, blue: 0.85).opacity(0.8))
                    .frame(width: size.width * 0.55)
                    .blur(radius: 100)
                    .offset(x: size.width * 0.25, y: size.height * 0.22)
                Circle()
                    .fill(Color(red: 0.55, green: 0.30, blue: 0.85).opacity(0.7))
                    .frame(width: size.width * 0.5)
                    .blur(radius: 110)
                    .offset(x: size.width * 0.18, y: -size.height * 0.28)
                GridOverlay()
            }
        }
    }
}

/// Thin lines under the glass make the refraction obvious.
private struct GridOverlay: View {
    var body: some View {
        Canvas { context, canvasSize in
            let step: CGFloat = 34
            var path = Path()
            var x: CGFloat = 0
            while x <= canvasSize.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= canvasSize.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
        }
    }
}
#endif
