import Foundation

/// The CSS properties that decide painting order for a child of a glass root.
///
/// The reference library re-implements the stacking-context spec so the
/// composited scene matches what the browser paints. The Apple port needs the
/// same ordering for its own scene assembly, so the rules live here where they
/// can be unit tested.
public struct StackingTraits: Equatable, Sendable {
    /// A non-static `position` participates in z-ordering.
    public var positionIsStatic: Bool
    /// An explicit `z-index` on a flex/grid item creates a context.
    public var isFlexOrGridItemWithZIndex: Bool
    /// `opacity < 1`.
    public var hasOpacity: Bool
    /// `transform`, `filter`, `perspective`, `clip-path`, `mix-blend-mode`,
    /// `backdrop-filter`, `mask-image`, `isolation: isolate`, or a matching
    /// `will-change` entry.
    public var hasIsolatingProperty: Bool
    /// `contain: layout | paint | strict | content`.
    public var hasContainment: Bool
    /// The raw `z-index`; `nil` behaves as `auto` (0 for ordering purposes).
    public var zIndex: Int?
    /// DOM order among siblings.
    public var domIndex: Int

    public init(
        positionIsStatic: Bool = true,
        isFlexOrGridItemWithZIndex: Bool = false,
        hasOpacity: Bool = false,
        hasIsolatingProperty: Bool = false,
        hasContainment: Bool = false,
        zIndex: Int? = nil,
        domIndex: Int = 0
    ) {
        self.positionIsStatic = positionIsStatic
        self.isFlexOrGridItemWithZIndex = isFlexOrGridItemWithZIndex
        self.hasOpacity = hasOpacity
        self.hasIsolatingProperty = hasIsolatingProperty
        self.hasContainment = hasContainment
        self.zIndex = zIndex
        self.domIndex = domIndex
    }

    /// Whether this child forms a stacking context, i.e. whether its z-index
    /// participates in painting order.
    public var formsStackingContext: Bool {
        if !positionIsStatic { return true }
        if isFlexOrGridItemWithZIndex { return true }
        if hasOpacity { return true }
        if hasIsolatingProperty { return true }
        if hasContainment { return true }
        return false
    }

    /// The effective z-index used for ordering. Non-context elements sort
    /// below every context element, regardless of their declared z-index.
    public var effectiveZIndex: Int { zIndex ?? 0 }
}

/// Compute painting order for the children of a glass root.
///
/// Elements that do not form a stacking context paint first, in DOM order.
/// Elements that do paint afterwards, sorted by z-index and then DOM order —
/// the same two-pass rule the CSS spec uses for a single stacking level.
public func paintingOrder(_ traits: [StackingTraits]) -> [Int] {
    let indexed = traits.enumerated().map { (index: $0.offset, traits: $0.element) }
    let sorted = indexed.sorted { a, b in
        let aContext = a.traits.formsStackingContext
        let bContext = b.traits.formsStackingContext
        if !aContext && bContext { return true }
        if aContext && !bContext { return false }
        if aContext && bContext && a.traits.effectiveZIndex != b.traits.effectiveZIndex {
            return a.traits.effectiveZIndex < b.traits.effectiveZIndex
        }
        return a.traits.domIndex < b.traits.domIndex
    }
    return sorted.map(\.index)
}
