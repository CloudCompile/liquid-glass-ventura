import Foundation

/// Groups glass surfaces that are close enough together to be drawn as one
/// piece of material.
///
/// This mirrors what the system `GlassEffectContainer` does on macOS 26 and
/// later: surfaces within `spacing` of each other blend into a single panel
/// instead of reading as separate controls. The grouping lives here, in the
/// platform-free core, so it can be tested without a Mac.
public enum GlassClusterer {

    /// Group surface frames into clusters.
    ///
    /// Two frames join when the gap between them is *smaller* than `spacing`:
    /// each is grown by `spacing / 2` and the grown rectangles must overlap. A
    /// gap of exactly `spacing` is the boundary and does not merge, so the rule
    /// is "closer together than `spacing`" rather than "at most `spacing`".
    /// Overlapping frames always merge, including when `spacing` is zero.
    ///
    /// The relation is transitive: a chain of nearby surfaces becomes one
    /// cluster, even when the two ends are far apart.
    ///
    /// - Returns: one array of indices per cluster, in the order the clusters
    ///   were first seen. Every input index appears exactly once.
    public static func clusters(frames: [LGRect], spacing: Double) -> [[Int]] {
        guard !frames.isEmpty else { return [] }
        let growth = max(spacing, 0) / 2

        // Union-find over the surface indices.
        var parent = Array(0..<frames.count)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            // Path compression, so a long chain stays near-constant time.
            var cursor = index
            while parent[cursor] != root {
                let next = parent[cursor]
                parent[cursor] = root
                cursor = next
            }
            return root
        }

        for i in 0..<frames.count {
            let a = frames[i].insetBy(dx: -growth, dy: -growth)
            for j in (i + 1)..<frames.count {
                let b = frames[j].insetBy(dx: -growth, dy: -growth)
                if a.intersects(b) {
                    let ra = find(i), rb = find(j)
                    if ra != rb { parent[rb] = ra }
                }
            }
        }

        var order: [Int] = []
        var grouped: [Int: [Int]] = [:]
        for index in 0..<frames.count {
            let root = find(index)
            if grouped[root] == nil { order.append(root) }
            grouped[root, default: []].append(index)
        }
        return order.compactMap { grouped[$0] }
    }

    /// The bounding box of a group of frames.
    public static func bounds(of frames: [LGRect], indices: [Int]) -> LGRect {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for index in indices where frames.indices.contains(index) {
            let frame = frames[index]
            minX = Swift.min(minX, frame.minX)
            minY = Swift.min(minY, frame.minY)
            maxX = Swift.max(maxX, frame.maxX)
            maxY = Swift.max(maxY, frame.maxY)
        }
        guard minX <= maxX, minY <= maxY else { return LGRect(x: 0, y: 0, width: 0, height: 0) }
        return LGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
