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
    let id = UUID()

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

        case "Toggle":
            // Toggle requires state binding — simplified for now
            Text("[Toggle: \(node.property("label"))]")

        case "TextField":
            // TextField requires state binding — simplified for now
            Text("[TextField: \(node.property("placeholder"))]")

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
        let root = ViewNode(pointer: viewnode_get_root())
        DynamicView(node: root)
            .id(reloadCount) // force re-render on reload
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
