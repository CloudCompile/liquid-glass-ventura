import Foundation
import LiquidGlassCore

// liquidglass-render — renders the demo scenes with the core's software
// pipeline and writes PNGs. This is the tool that produces the checked-in
// screenshots, so every image in docs/screenshots is a real render of the
// shipping optical model rather than a mock-up.
//
// Usage:
//   liquidglass-render --scene hero --out docs/screenshots/hero.png
//   liquidglass-render --list
//   liquidglass-render --all --out-dir docs/screenshots

struct RenderError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

let scenes = DemoScenes.all

func usage() {
    print("""
    liquidglass-render — Liquid Glass reference renderer

    USAGE:
      liquidglass-render --list
      liquidglass-render --scene <name> --out <path.png> [--scale <n>]
      liquidglass-render --all --out-dir <dir> [--scale <n>]

    SCENES:
    \(scenes.map { "  \($0.name.padding(toLength: 18, withPad: " ", startingAt: 0))\($0.summary)" }.joined(separator: "\n"))
    """)
}

func parseOptions() -> [String: String] {
    var options: [String: String] = [:]
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        if arg.hasPrefix("--") {
            let key = String(arg.dropFirst(2))
            if let next = args.first, !next.hasPrefix("--") {
                options[key] = next
                args.removeFirst()
            } else {
                options[key] = "true"
            }
        }
    }
    return options
}

let options = parseOptions()

// Cross-check modes. `--crosscheck-configs` emits the case list, which the
// verification script injects into the reference harness so both sides render
// the same thing; `--crosscheck` emits this port's sampled pixels for the diff.
if options["crosscheck-configs"] != nil {
    print(CrossCheck.configsJSON())
    exit(0)
}

if options["crosscheck"] != nil {
    print(CrossCheck.samplesJSON())
    exit(0)
}

if options["list"] != nil {
    for scene in scenes {
        print("\(scene.name)\t\(scene.summary)")
    }
    exit(0)
}

if options["help"] != nil || options["h"] != nil {
    usage()
    exit(0)
}

let scale = options["scale"].flatMap(Double.init) ?? 2

func renderScene(_ scene: DemoScene, to url: URL) throws {
    let image = scene.render(scale: scale)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try PNGEncoder.write(image, to: url)
    let size = "\(image.width)x\(image.height)"
    print("rendered \(scene.name) -> \(url.path) (\(size) px)")
}

do {
    if let outDir = options["out-dir"] {
        for scene in scenes {
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(scene.name).png")
            try renderScene(scene, to: url)
        }
    } else if let name = options["scene"] {
        guard let scene = scenes.first(where: { $0.name == name }) else {
            throw RenderError(message: "unknown scene '\(name)'. Use --list to see the available scenes.")
        }
        let out = options["out"] ?? "\(name).png"
        try renderScene(scene, to: URL(fileURLWithPath: out))
    } else {
        usage()
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
