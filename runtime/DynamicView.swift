import SwiftUI

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

        case "Image":
            let name = node.property("systemName")
            if !name.isEmpty {
                Image(systemName: name)
            } else {
                Image(node.property("name"))
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
        DynamicView(node: root)
            .id(root.id)
            .onReceive(pollTimer) { _ in
                if viewnode_poll() != 0 { reloadCount += 1 }
            }
            .onReceive(NotificationCenter.default.publisher(for: .viewTreeDidReload)) { _ in
                reloadCount += 1
            }
    }
}

extension Notification.Name {
    static let viewTreeDidReload = Notification.Name("viewTreeDidReload")
}
