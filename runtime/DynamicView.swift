import SwiftUI
import Foundation
import AVKit

/// Recursively renders a Haxe view tree at runtime.
/// Used by `mui watch` for hot reload — the Swift host stays running
/// while the .cppia script is reloaded with new view code.
///
/// Each ViewNode maps to its SwiftUI equivalent via a switch on viewType.
/// Modifiers are applied dynamically from the modifier chain.

// MARK: - ViewNode wrapper

/// Opaque wrapper around a Haxe View pointer from the bridge.
struct ViewNode: Identifiable {
    let pointer: UnsafeMutableRawPointer?

    // Stable identity across rebuilds: the app tags each node with a "nodeId"
    // property (e.g. its A2UI component id). Without it, fall back to the
    // pointer — unstable across rebuilds, but such nodes carry no view state to
    // preserve. A stable id lets SwiftUI diff the tree and keep input focus/text
    // through a rebuild instead of tearing everything down.
    var id: String {
        let nid = property("nodeId")
        if !nid.isEmpty { return nid }
        if let p = pointer { return "ptr-\(UInt(bitPattern: p))" }
        return "nil"
    }

    var viewType: String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_get_type(ptr))
    }

    var childCount: Int {
        guard let ptr = pointer else { return 0 }
        return Int(viewnode_child_count(ptr))
    }

    func child(at index: Int) -> ViewNode {
        guard let ptr = pointer else { return ViewNode(pointer: nil) }
        return ViewNode(pointer: viewnode_get_child(ptr, Int32(index)))
    }

    var children: [ViewNode] {
        (0..<childCount).map { child(at: $0) }
    }

    var textContent: String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_get_text(ptr))
    }

    var buttonLabel: String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_get_button_label(ptr))
    }

    var buttonActionId: Int32 {
        guard let ptr = pointer else { return -1 }
        return viewnode_get_button_action_id(ptr)
    }

    func invokeAction() {
        guard let ptr = pointer else { return }
        viewnode_invoke_action(ptr)
    }

    func property(_ key: String) -> String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_get_property(ptr, key))
    }

    var modifierCount: Int {
        guard let ptr = pointer else { return 0 }
        return Int(viewnode_modifier_count(ptr))
    }

    func modifierType(at index: Int) -> String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_modifier_type(ptr, Int32(index)))
    }

    func modifierFloat(at index: Int, param: Int = 0) -> Double {
        guard let ptr = pointer else { return 0 }
        return viewnode_modifier_float(ptr, Int32(index), Int32(param))
    }

    func modifierString(at index: Int, param: Int = 0) -> String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_modifier_string(ptr, Int32(index), Int32(param)))
    }
}

// MARK: - Dynamic SwiftUI Renderer

/// Renders a ViewNode as a SwiftUI view, recursively processing children.
struct DynamicView: View {
    let node: ViewNode

    var body: some View {
        applyModifiers(to: renderContent())
    }

    @ViewBuilder
    private func renderContent() -> some View {
        switch node.viewType {
        case "VStack":
            VStack(spacing: spacingFromProperties()) {
                ForEach(node.children) { child in
                    DynamicView(node: child)
                }
            }

        case "HStack":
            HStack(spacing: spacingFromProperties()) {
                ForEach(node.children) { child in
                    DynamicView(node: child)
                }
            }

        case "ZStack":
            ZStack {
                ForEach(node.children) { child in
                    DynamicView(node: child)
                }
            }

        case "Text":
            Text(node.textContent)

        case "Button":
            Button(node.buttonLabel) {
                node.invokeAction()
            }

        case "Spacer":
            Spacer()

        case "Divider":
            Divider()

        case "Toggle", "CheckBox":
            DynamicCheckBox(node: node)

        case "TextField":
            DynamicTextField(node: node)

        case "Canvas":
            DynamicCanvas(node: node)

        case "Board":
            DynamicBoard(node: node)

        case "Slider":
            DynamicSlider(node: node)

        case "ChoicePicker":
            DynamicPicker(node: node)

        case "Tabs":
            DynamicTabs(node: node)

        case "Modal":
            DynamicModal(node: node)

        case "Icon":
            // A2UI icon name, interpreted as an SF Symbol (best effort). Icons
            // carry no colour prop, so they take the theme accent (a brand
            // element) — `.tint` only reaches interactive controls, not Images.
            Image(systemName: node.property("name"))
                .foregroundStyle(Color(suiHex: String(cString: viewnode_theme_accent())) ?? .primary)

        case "Video":
            DynamicVideo(node: node)

        case "Image":
            let url = node.property("url")
            if !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            } else {
                let name = node.property("systemName")
                if !name.isEmpty {
                    Image(systemName: name)
                } else {
                    Image(node.property("name"))
                }
            }

        case "ProgressView":
            ProgressView()

        case "ScrollView":
            ScrollView {
                VStack {
                    ForEach(node.children) { child in
                        DynamicView(node: child)
                    }
                }
            }

        default:
            // Unknown view type — render children if any
            if node.childCount > 0 {
                VStack {
                    ForEach(node.children) { child in
                        DynamicView(node: child)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Modifier application

    private func applyModifiers<V: View>(to view: V) -> AnyView {
        var result: AnyView = AnyView(view)

        for i in 0..<node.modifierCount {
            let modType = node.modifierType(at: i)

            switch modType {
            case "Padding":
                let value = node.modifierFloat(at: i)
                result = value > 0 ? AnyView(result.padding(CGFloat(value))) : AnyView(result.padding())

            case "PaddingDefault":
                result = AnyView(result.padding())

            case "Font":
                // sui's Font(FontStyle) — param 0 is the FontStyle enum name.
                let font: Font
                switch node.modifierString(at: i, param: 0) {
                case "LargeTitle":   font = .largeTitle
                case "Title":        font = .title
                case "Title2":       font = .title2
                case "Title3":       font = .title3
                case "Headline":     font = .headline
                case "Subheadline":  font = .subheadline
                case "Body":         font = .body
                case "Callout":      font = .callout
                case "Footnote":     font = .footnote
                case "Caption":      font = .caption
                case "Caption2":     font = .caption2
                default:             font = .body
                }
                result = AnyView(result.font(font))

            case "Bold":
                result = AnyView(result.bold())

            case "Italic":
                result = AnyView(result.italic())

            case "ForegroundColor":
                // Would need color enum mapping from bridge
                break

            case "Background":
                break

            case "Opacity":
                let value = node.modifierFloat(at: i)
                result = AnyView(result.opacity(value))

            case "CornerRadius":
                let value = node.modifierFloat(at: i)
                result = AnyView(result.cornerRadius(CGFloat(value)))

            case "Disabled":
                result = AnyView(result.disabled(true))

            case "NavigationTitle":
                // Would need string param from bridge
                break

            default:
                break
            }
        }

        return result
    }

    private func spacingFromProperties() -> CGFloat? {
        let spacing = node.property("spacing")
        if let val = Double(spacing), val > 0 {
            return CGFloat(val)
        }
        return nil
    }
}

// MARK: - Editable inputs

/// An editable text input. Its @State survives rebuilds (the node carries a
/// stable id), so typing stays smooth; each edit writes back through the data
/// bridge, and any bound mirror text re-renders on the next poll.
struct DynamicTextField: View {
    let node: ViewNode
    @State private var text: String

    init(node: ViewNode) {
        self.node = node
        _text = State(initialValue: node.property("value"))
    }

    var body: some View {
        let label = node.property("label")
        return TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                viewnode_set_data(node.property("path"), newValue)
            }
    }
}

/// An editable checkbox (rendered as a Toggle). Same stable-id contract.
struct DynamicCheckBox: View {
    let node: ViewNode
    @State private var on: Bool

    init(node: ViewNode) {
        self.node = node
        _on = State(initialValue: node.property("value") == "true")
    }

    var body: some View {
        Toggle(node.property("label"), isOn: $on)
            .onChange(of: on) { _, newValue in
                viewnode_set_data(node.property("path"), newValue ? "true" : "false")
            }
    }
}

/// An editable slider bound to a numeric data-model value (label + min/max).
struct DynamicSlider: View {
    let node: ViewNode
    @State private var value: Double

    init(node: ViewNode) {
        self.node = node
        _value = State(initialValue: Double(node.property("value")) ?? 0)
    }

    var body: some View {
        let lo = Double(node.property("min")) ?? 0
        let hi = Double(node.property("max")) ?? 100
        let label = node.property("label")
        return VStack(alignment: .leading, spacing: 2) {
            if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
            Slider(value: $value, in: lo...Swift.max(hi, lo + 0.0001))
                .onChange(of: value) { _, v in
                    // Whole numbers write without a trailing ".0".
                    let s = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
                    viewnode_set_data(node.property("path"), s)
                }
        }
    }
}

/// A choice picker bound to an Array<String> of selected values. A single-select
/// (mutuallyExclusive) surface renders as a native Picker; multipleSelection as
/// a checkable Menu. Edits write the new array back through the data bridge.
struct DynamicPicker: View {
    let node: ViewNode
    @State private var selected: [String]

    init(node: ViewNode) {
        self.node = node
        _selected = State(initialValue: parseStringArray(node.property("selected")))
    }

    var body: some View {
        let options = parsePickerOptions(node.property("options"))
        let label = node.property("label")
        return Group {
            if node.property("variant") == "multipleSelection" {
                Menu {
                    ForEach(options, id: \.value) { opt in
                        Button { toggle(opt.value) } label: {
                            Label(opt.label, systemImage: selected.contains(opt.value) ? "checkmark" : "")
                        }
                    }
                } label: {
                    let names = options.filter { selected.contains($0.value) }.map(\.label)
                    Text(names.isEmpty ? label : names.joined(separator: ", "))
                }
            } else {
                Picker(label, selection: singleSelection) {
                    ForEach(options, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
            }
        }
    }

    private var singleSelection: Binding<String> {
        Binding(get: { selected.first ?? "" }, set: { selected = [$0]; write() })
    }

    private func toggle(_ value: String) {
        if let i = selected.firstIndex(of: value) { selected.remove(at: i) } else { selected.append(value) }
        write()
    }

    private func write() {
        let json = (try? JSONSerialization.data(withJSONObject: selected))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        viewnode_set_data(node.property("path"), json)
    }
}

private func parsePickerOptions(_ json: String) -> [(label: String, value: String)] {
    guard let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
    return arr.map { (
        label: ($0["label"] as? String) ?? ($0["value"] as? String) ?? "",
        value: ($0["value"] as? String) ?? ""
    ) }
}

private func parseStringArray(_ json: String) -> [String] {
    guard let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else { return [] }
    return arr.compactMap { $0 as? String }
}

/// Tabs — the tab contents are this node's children; the titles are a parallel
/// JSON array on the "titles" property.
struct DynamicTabs: View {
    let node: ViewNode
    @State private var selection = 0

    var body: some View {
        let titles = parseStringArray(node.property("titles"))
        let children = node.children
        return TabView(selection: $selection) {
            ForEach(Array(children.enumerated()), id: \.offset) { idx, child in
                DynamicView(node: child)
                    .tabItem { Text(idx < titles.count ? titles[idx] : "Tab \(idx + 1)") }
                    .tag(idx)
            }
        }
    }
}

/// Modal — child[0] is the trigger, child[1] the content. Tapping the trigger
/// presents the content in a sheet.
struct DynamicModal: View {
    let node: ViewNode
    @State private var presented = false

    var body: some View {
        let children = node.children
        let trigger = children.first ?? ViewNode(pointer: nil)
        let content = children.count > 1 ? children[1] : ViewNode(pointer: nil)
        // The trigger renders as-is; a clear overlay on top captures the tap and
        // opens the modal (A2UI: the trigger opens it). This avoids nesting the
        // trigger — often itself a Button — inside another control.
        return DynamicView(node: trigger)
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { presented = true }
            )
            .sheet(isPresented: $presented) {
                VStack(spacing: 16) {
                    DynamicView(node: content)
                    Button("Close") { presented = false }
                }
                .padding()
            }
    }
}

/// Video — an AVKit player over the A2UI url. The player is held in @State so
/// playback survives re-renders (the node keeps a stable id).
struct DynamicVideo: View {
    let node: ViewNode
    @State private var player: AVPlayer?

    init(node: ViewNode) {
        self.node = node
        if let u = URL(string: node.property("url")) {
            _player = State(initialValue: AVPlayer(url: u))
        }
    }

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player).frame(minHeight: 220)
            } else {
                Text("Vidéo indisponible").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Board (drag-and-drop)

/// Board — the behaviour axis. Lanes are columns; cards (each tagged with a
/// lane) are draggable between them. Only the drop returns to the app, as the
/// onDrop action with a {card, lane, index} context; the app moves the card and
/// re-renders. lanes/cards/dropAction arrive as JSON on properties.
private struct BoardLane: Identifiable { let id: String; let title: String }
private struct BoardCard: Identifiable { let id: String; let label: String; let lane: String }

struct DynamicBoard: View {
    let node: ViewNode
    // Shared namespace so a card matched by id animates (FLIP) as it moves from
    // one lane's stack to another's when the app re-renders after a drop.
    @Namespace private var ns

    var body: some View {
        let lanes = parseBoardLanes(node.property("lanes"))
        let cards = parseBoardCards(node.property("cards"))
        let dropAction = node.property("dropAction")
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(lanes) { lane in
                    laneView(lane, cards: cards.filter { $0.lane == lane.id }, dropAction: dropAction)
                }
            }
            .padding(8)
        }
    }

    private func laneView(_ lane: BoardLane, cards: [BoardCard], dropAction: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lane.title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            ForEach(cards) { card in
                Text(card.label)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                    .matchedGeometryEffect(id: card.id, in: ns)
                    .draggable(card.id)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 190, alignment: .top)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
        .dropDestination(for: String.self) { items, _ in
            guard let cardId = items.first else { return false }
            let extra: [String: Any] = ["card": cardId, "lane": lane.id, "index": cards.count]
            let json = (try? JSONSerialization.data(withJSONObject: extra))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            viewnode_fire_action(dropAction, json)
            return true
        }
    }
}

private func parseObjArray(_ json: String) -> [[String: Any]] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] ?? []
}
private func parseBoardLanes(_ json: String) -> [BoardLane] {
    parseObjArray(json).map { BoardLane(id: $0["id"] as? String ?? "", title: $0["title"] as? String ?? "") }
}
private func parseBoardCards(_ json: String) -> [BoardCard] {
    parseObjArray(json).map {
        BoardCard(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", lane: $0["lane"] as? String ?? "")
    }
}

// MARK: - Canvas drawing

/// Interprets an A2UI Canvas spec — `{viewBox, ops, fit}`, delivered as JSON on
/// the "canvas" property — into native SwiftUI drawing. One interpreter renders
/// every Canvas-based component (gauges, sparklines, charts): the drawing logic
/// lives once, server-side, and each op is replayed here through a GraphicsContext.
struct DynamicCanvas: View {
    let node: ViewNode

    var body: some View {
        let json = node.property("canvas")
        let spec = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        return Canvas { ctx, size in
            guard let spec = spec,
                  let vb = spec["viewBox"] as? [String: Any],
                  let vw = cnum(vb["w"]), let vh = cnum(vb["h"]), vw > 0, vh > 0
            else { return }
            let sx: CGFloat, sy: CGFloat
            switch spec["fit"] as? String {
            case "stretch": sx = size.width / vw; sy = size.height / vh
            case "cover":   let s = max(size.width / vw, size.height / vh); sx = s; sy = s
            default:        let s = min(size.width / vw, size.height / vh); sx = s; sy = s // contain
            }
            // viewBox → allocated box: uniform (or stretch) scale, centered.
            let t = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                      tx: (size.width - vw * sx) / 2,
                                      ty: (size.height - vh * sy) / 2)
            // Semantic colour tokens resolved from the surface theme.
            let theme = spec["theme"] as? [String: Any] ?? [:]
            for op in (spec["ops"] as? [[String: Any]] ?? []) {
                drawCanvasOp(op, &ctx, t, theme)
            }
        }
    }
}

private func cnum(_ v: Any?) -> CGFloat? {
    if let n = v as? NSNumber { return CGFloat(n.doubleValue) }
    return nil
}
private func cf(_ op: [String: Any], _ k: String, _ d: CGFloat = 0) -> CGFloat { cnum(op[k]) ?? d }
private func cscale(_ t: CGAffineTransform) -> CGFloat { sqrt(abs(t.a * t.d - t.b * t.c)) }

// A colour is a hex "#RRGGBB" or a semantic token. A token first resolves to a
// surface-theme override (hex), then falls back to an adaptive system colour so
// untethered drawings still track light/dark.
private func canvasColor(_ op: [String: Any], _ key: String, _ theme: [String: Any]) -> Color? {
    guard let s = op[key] as? String, !s.isEmpty else { return nil }
    if s.hasPrefix("#") { return Color(suiHex: s) }
    if let hex = theme[s] as? String, hex.hasPrefix("#") { return Color(suiHex: hex) }
    switch s {
    case "primary":   return .accentColor
    case "onPrimary": return .white
    case "surface":   return Color(white: 0.5).opacity(0.12)
    case "onSurface": return .primary
    case "border":    return .gray.opacity(0.5)
    case "muted":     return .secondary
    default:          return .primary
    }
}

private func canvasStroke(_ op: [String: Any], _ t: CGAffineTransform) -> StrokeStyle {
    let cap: CGLineCap
    switch op["cap"] as? String {
    case "round":  cap = .round
    case "square": cap = .square
    default:       cap = .butt
    }
    return StrokeStyle(lineWidth: cf(op, "strokeWidth", 1) * cscale(t), lineCap: cap)
}

private func paintCanvas(_ ctx: inout GraphicsContext, _ path: Path, _ op: [String: Any], _ t: CGAffineTransform, _ theme: [String: Any]) {
    ctx.opacity = Double(cf(op, "opacity", 1))
    if let fill = canvasColor(op, "fill", theme) { ctx.fill(path, with: .color(fill)) }
    if let stroke = canvasColor(op, "stroke", theme) { ctx.stroke(path, with: .color(stroke), style: canvasStroke(op, t)) }
    ctx.opacity = 1
}

// Coordinates are in viewBox space; each op's Path is built there then mapped to
// screen with `t` (so lines stay crisp and arcs stay circular under affine).
private func drawCanvasOp(_ op: [String: Any], _ ctx: inout GraphicsContext, _ t: CGAffineTransform, _ theme: [String: Any]) {
    switch op["op"] as? String {
    case "rect":
        let r = CGRect(x: cf(op, "x"), y: cf(op, "y"), width: cf(op, "w"), height: cf(op, "h"))
        let rx = cf(op, "rx")
        paintCanvas(&ctx, (rx > 0 ? Path(roundedRect: r, cornerRadius: rx) : Path(r)).applying(t), op, t, theme)

    case "line":
        var p = Path()
        p.move(to: CGPoint(x: cf(op, "x1"), y: cf(op, "y1")))
        p.addLine(to: CGPoint(x: cf(op, "x2"), y: cf(op, "y2")))
        paintCanvas(&ctx, p.applying(t), op, t, theme)

    case "circle":
        let r = cf(op, "r")
        let rect = CGRect(x: cf(op, "cx") - r, y: cf(op, "cy") - r, width: 2 * r, height: 2 * r)
        paintCanvas(&ctx, Path(ellipseIn: rect).applying(t), op, t, theme)

    case "ellipse":
        let rx = cf(op, "rx"), ry = cf(op, "ry")
        let rect = CGRect(x: cf(op, "cx") - rx, y: cf(op, "cy") - ry, width: 2 * rx, height: 2 * ry)
        paintCanvas(&ctx, Path(ellipseIn: rect).applying(t), op, t, theme)

    case "arc":
        // A2UI: degrees, 0° at 3 o'clock, clockwise positive.
        let c = CGPoint(x: cf(op, "cx"), y: cf(op, "cy"))
        let close = op["close"] as? Bool ?? false
        var p = Path()
        if close { p.move(to: c) }
        p.addArc(center: c, radius: cf(op, "r"),
                 startAngle: .degrees(cf(op, "start")), endAngle: .degrees(cf(op, "end")),
                 clockwise: false)
        if close { p.closeSubpath() }
        paintCanvas(&ctx, p.applying(t), op, t, theme)

    case "polyline":
        let pts = op["points"] as? [[Any]] ?? []
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let x = cnum(pt.first) ?? 0
            let y = cnum(pt.count > 1 ? pt[1] : nil) ?? 0
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        if op["closed"] as? Bool ?? false { p.closeSubpath() }
        paintCanvas(&ctx, p.applying(t), op, t, theme)

    case "text":
        let size = cf(op, "size", 12) * cscale(t)
        let weight: Font.Weight = cf(op, "weight", 400) >= 600 ? .bold : .regular
        var text = Text(op["text"] as? String ?? "").font(.system(size: size, weight: weight))
        if let fill = canvasColor(op, "fill", theme) { text = text.foregroundColor(fill) }
        let anchor: UnitPoint
        switch op["anchor"] as? String {
        case "middle": anchor = .center
        case "end":    anchor = .trailing
        default:       anchor = .leading
        }
        ctx.draw(text, at: CGPoint(x: cf(op, "x"), y: cf(op, "y")).applying(t), anchor: anchor)

    case "group":
        var gt = CGAffineTransform.identity
        if let tr = op["translate"] as? [Any], tr.count >= 2 {
            gt = gt.translatedBy(x: cnum(tr[0]) ?? 0, y: cnum(tr[1]) ?? 0)
        }
        if let rot = cnum(op["rotate"]) { gt = gt.rotated(by: rot * .pi / 180) }
        if let sc = cnum(op["scale"]) { gt = gt.scaledBy(x: sc, y: sc) }
        let child = gt.concatenating(t)
        for sub in (op["ops"] as? [[String: Any]] ?? []) { drawCanvasOp(sub, &ctx, child, theme) }

    default:
        break
    }
}

// MARK: - Hot Reload Root View

/// The root view used in hot reload mode.
/// Watches for .cppia file changes and triggers re-render.
// Boots the hxcpp runtime + registers the app exactly once, before the first
// view-tree traversal. A global `let` is initialised lazily and thread-safely
// on first access (Swift dispatch_once semantics), so referencing it at the
// top of `body` guarantees `viewnode_get_root()` sees an initialised runtime.
private let _suiRuntimeBooted: Bool = {
    viewnode_boot()
    return true
}()

struct HotReloadRootView: View {
    @State private var reloadCount = 0

    // Pump the app's poll delegate on the main thread (drains the WS queue).
    private let pollTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Boot the runtime before the first body evaluation reads the view tree.
    init() { _ = _suiRuntimeBooted }

    var body: some View {
        // Read reloadCount so a poll-driven bump re-evaluates body (re-reads the
        // tree) — but do NOT use it as identity. The tree keeps a stable id, so
        // SwiftUI diffs it and preserves input focus/text across rebuilds
        // instead of tearing everything down every time.
        let _ = reloadCount
        let root = ViewNode(pointer: viewnode_get_root())
        // Tint native controls with the theme accent (surface primaryColor).
        let accent = Color(suiHex: String(cString: viewnode_theme_accent()))
        DynamicView(node: root)
            .id(root.id)
            .tint(accent)
            .onReceive(pollTimer) { _ in
                // Animate tree updates: with stable node identities, SwiftUI
                // interpolates layout changes (a card moving lanes, a list
                // reordering) instead of snapping.
                if viewnode_poll() != 0 { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { reloadCount += 1 } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .viewTreeDidReload)) { _ in
                withAnimation { reloadCount += 1 }
            }
    }
}

extension Notification.Name {
    static let viewTreeDidReload = Notification.Name("viewTreeDidReload")
}
