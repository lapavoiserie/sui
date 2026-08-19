import SwiftUI
import Foundation
import AVKit
import AVFoundation

/// Recursively renders a Haxe view tree at runtime.
/// Used by `mui watch` for hot reload — the Swift host stays running
/// while the .cppia script is reloaded with new view code.
///
/// Each ViewNode maps to its SwiftUI equivalent via a switch on viewType.
/// Modifiers are applied dynamically from the modifier chain.

// MARK: - ViewNode wrapper

/// Opaque wrapper around a Haxe View pointer from the bridge.
/// A handle on a Haxe view node.
///
/// Deliberately **not** `Identifiable`: the only identity it could offer itself
/// is its pointer, and that changes on every rebuild. Identity belongs to a
/// node's *place* among its siblings, which only the parent walking them knows
/// — see `identity(at:)`.
struct ViewNode {
    let pointer: UnsafeMutableRawPointer?

    // Stable identity across rebuilds: the app tags each node with a "nodeId"
    // property (e.g. its A2UI component id). Without it, fall back to the
    // pointer — unstable across rebuilds, but such nodes carry no view state to
    // preserve. A stable id lets SwiftUI diff the tree and keep input focus/text
    // through a rebuild instead of tearing everything down.
    /// A node's identity, for SwiftUI's diffing.
    ///
    /// The pointer is **not** it. A rebuild allocates a fresh tree, so every
    /// pointer changes, so every view looks new to SwiftUI and the whole screen
    /// is torn down and put back — which is the flicker you see when a list
    /// gains a row. Rebuilding the tree is not supposed to cost that: SwiftUI
    /// will happily diff a new tree against the old one and touch only what
    /// differs, given identities that survive.
    ///
    /// So identity is **positional**, which is what
    /// [nui's contract](https://lapavoiserie.github.io/nui/#/pull-mode) says it
    /// is: `keyOf` returns null because sui's trees carry no sibling keys yet.
    /// A node that does carry an explicit `nodeId` — a protocol-fed tree, where
    /// rows genuinely move — keeps it, and gets real identity instead.
    func identity(at index: Int) -> String {
        let nid = property("nodeId")
        return nid.isEmpty ? "#\(index)" : nid
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

    // A TabView's labels and icons, which sit beside the contents rather than
    // among them.
    var tabCount: Int {
        guard let ptr = pointer else { return 0 }
        return Int(viewnode_tab_count(ptr))
    }

    func tabTitle(at index: Int) -> String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_tab_title(ptr, Int32(index)))
    }

    func tabIcon(at index: Int) -> String {
        guard let ptr = pointer else { return "" }
        return String(cString: viewnode_tab_icon(ptr, Int32(index)))
    }

    /// The cells this node displays, as Haxe worked them out.
    var valueDependencies: [String] {
        guard let ptr = pointer else { return [] }
        let raw = String(cString: viewnode_value_deps(ptr))
        if raw.isEmpty { return [] }
        return raw.split(separator: ",").map(String.init)
    }

    /// A value read as a number, for the many properties that are one.
    func number(_ key: String) -> Double? {
        Double(property(key))
    }

    /// A list of sui colours, as the source joins them: "Blue,Purple".
    func colorList(_ key: String) -> [Color] {
        let raw = property(key)
        if raw.isEmpty { return [] }
        return raw.split(separator: ",").map { suiColorValue(String($0)) }
    }

    /// The property naming the cell this control edits, if it declares one.
    ///
    /// sui spells it differently per control -- `textBinding`, `isOnBinding`,
    /// `valueBinding`, `selectionBinding`, `isoStateName` -- because the
    /// transpiler read the field, and a field can be called anything. A walker
    /// has to know the whole list; there is nowhere else it is written down.
    var bindingName: String? {
        for key in ["textBinding", "isOnBinding", "valueBinding",
                    "selectionBinding", "isoStateName"] {
            let name = property(key)
            if !name.isEmpty { return key }
        }
        return nil
    }

    /// A two-way binding for this control, whichever way it declares one.
    ///
    /// Everything crosses as a string: the cell's type is Haxe's business, and
    /// `State._applyFromSwift` parses the value back into it from the type
    /// already in the cell. A renderer that guessed types here would be a
    /// second opinion about them.
    var boundValue: Binding<String> {
        let node = self
        if let key = bindingName {
            return Binding(get: { node.stateValue(key) },
                           set: { node.setStateValue(key, $0) })
        }
        return Binding(get: { node.property("value") },
                       set: { viewnode_set_data(node.property("path"), $0) })
    }

    /// A named state's current value, for a control that binds by name.
    func stateValue(_ key: String) -> String {
        let name = property(key)
        if name.isEmpty { return "" }
        return String(cString: viewnode_state_value(name))
    }

    /// Write a named state back, after the control edited it.
    func setStateValue(_ key: String, _ value: String) {
        let name = property(key)
        if name.isEmpty { return }
        viewnode_set_state(name, value)
        // And tell the views that display this cell.
        //
        // A value arriving from a control goes in through `applyExternal`, which
        // deliberately does *not* push back to the platform: echoing it at the
        // control that produced it is the loop that fights a text field for its
        // cursor. But every *other* view showing the same cell learns nothing,
        // so a label reading the field's text stayed on the old value while the
        // field showed the new one.
        //
        // The control itself re-reads what it just wrote, which is why nothing
        // is mirrored on this side: there is only one copy, so there is nothing
        // to disagree with.
        _suiStateChanged(name)
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
        // Register on the cells this node displays. Observation records the
        // reads, so a write to one of them re-evaluates this view -- and only
        // the views that read it -- instead of the whole tree.
        let _ = SuiCells.shared.track(node.valueDependencies)
        applyModifiers(to: renderContent())
    }

    @ViewBuilder
    private func renderContent() -> some View {
        switch node.viewType {
        case "VStack":
            VStack(spacing: spacingFromProperties()) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                    DynamicView(node: child).id(child.identity(at: index))
                }
            }

        case "HStack":
            HStack(spacing: spacingFromProperties()) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                    DynamicView(node: child).id(child.identity(at: index))
                }
            }

        case "ZStack":
            ZStack {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                    DynamicView(node: child).id(child.identity(at: index))
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

        // MARK: sui containers
        //
        // Everything from here down is a type *sui itself* produces. The
        // renderer was written against a streaming protocol's vocabulary, so it
        // knew Board and Canvas but not List or Section -- the app's own views
        // reached the unknown-type branch and drew a placeholder.
        //
        // Most are pass-throughs: the container is the SwiftUI one, its content
        // is the node's children. What is *not* mechanical is where the content
        // comes from -- three of these keep it outside `children`, and
        // `sui.nui.ViewSource` is where that is corrected, not here.

        case "Form":
            Form { childViews() }

        case "Section":
            let header = node.property("header")
            if header.isEmpty {
                Section { childViews() }
            } else {
                Section(header) { childViews() }
            }

        case "List":
            List { childViews() }

        case "GroupBox":
            GroupBox(node.property("label")) {
                VStack(alignment: .leading) { childViews() }
            }

        case "DisclosureGroup":
            DisclosureGroup(node.property("label")) {
                VStack(alignment: .leading) { childViews() }
            }

        case "GeometryReader":
            GeometryReader { _ in childViews() }

        case "LazyVStack":
            LazyVStack(spacing: spacingFromProperties()) { childViews() }

        case "LazyHStack":
            LazyHStack(spacing: spacingFromProperties()) { childViews() }

        case "LazyVGrid":
            LazyVGrid(columns: flexibleGrid(count: node.property("columns")),
                      spacing: spacingFromProperties()) { childViews() }

        case "LazyHGrid":
            LazyHGrid(rows: flexibleGrid(count: node.property("rows")),
                      spacing: spacingFromProperties()) { childViews() }

        // An AdaptiveStack is a sidebar and a detail that lay out side by side
        // where there is room and stacked where there is not. `ViewThatFits`
        // says exactly that, and needs no size class to be threaded through.
        case "AdaptiveStack":
            ViewThatFits {
                HStack(alignment: .top) { childViews() }
                VStack(alignment: .leading) { childViews() }
            }

        // MARK: sui navigation

        case "NavigationStack":
            NavigationStack { childViews() }

        case "NavigationSplitView":
            NavigationSplitView {
                DynamicView(node: node.child(at: 0))
            } detail: {
                DynamicView(node: node.child(at: 1))
            }

        case "NavigationLink":
            NavigationLink(node.property("label")) {
                DynamicView(node: node.child(at: 0))
            }

        // The selection lives outside the tree, because the tree is replaced.
        //
        // A TabView with no `selection:` keeps its own, tied to the view's
        // identity -- and a structural write hands SwiftUI a new root with a new
        // id, so the whole hierarchy is recreated and the selection goes back to
        // the first tab. Touching a control sent you to tab one.
        case "TabView":
            // Read the selection *here*, in the body, so Observation records the
            // dependency. Reading it only inside the binding's getter registers
            // nothing -- that closure runs outside body evaluation -- so the
            // TabView never learned the selection had changed and tapping a tab
            // did nothing at all.
            let selectedTab = SuiTabs.shared.index
            TabView(selection: Binding(
                get: { selectedTab },
                set: { SuiTabs.shared.index = $0 }
            )) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                    DynamicView(node: child)
                        .tag(index)
                        .tabItem {
                            // An empty systemImage is not "no icon" to SwiftUI:
                            // it is an SF Symbol that does not exist, and the
                            // tab renders as the unsupported-view placeholder.
                            // `mui` passes "" for every tab, having no icon in
                            // its own vocabulary.
                            let icon = node.tabIcon(at: index)
                            if icon.isEmpty {
                                Text(node.tabTitle(at: index))
                            } else {
                                Label(node.tabTitle(at: index), systemImage: icon)
                            }
                        }
                }
            }

        // A CommandMenu belongs to a Scene's `.commands`, not to a view tree --
        // there is no place in a rendered hierarchy where it *is* the menu bar.
        // Drawn as the menu it most resembles, so its items stay reachable
        // rather than vanishing; on macOS a real app gets the menu bar from the
        // static path.
        case "CommandMenu", "Menu":
            Menu(node.property("label")) { childViews() }

        // MARK: sui controls
        //
        // A sui control declares its binding as a **name** -- `new
        // TextField("Name", "userName")` -- because the transpiler turned that
        // into `$appState.userName`. The streaming protocol instead carries the
        // current `value` plus a `path` to send edits to. Both are here: the
        // sui shape when a binding name is present, the protocol shape
        // otherwise, so neither renderer's apps regress.

        case "SecureField":
            SuiTextField(node: node, secure: true)

        case "TextEditor":
            SuiTextEditor(node: node)

        case "Stepper":
            SuiStepper(node: node)

        case "Picker":
            SuiPicker(node: node)

        case "ColorPicker":
            SuiColorPicker(node: node)

        case "DatePicker", "IsoDatePicker", "IsoTimePicker":
            SuiDatePicker(node: node, timeOnly: node.viewType == "IsoTimePicker")

        // Read-only: a Gauge shows a value, it does not take one.
        case "Gauge":
            let lo = node.number("minValue") ?? 0
            let hi = node.number("maxValue") ?? 1
            Gauge(value: Double(node.boundValue.wrappedValue) ?? lo, in: lo...max(hi, lo + 0.0001)) {
                Text(node.property("label"))
            }

        case "Label":
            Label(node.property("title"), systemImage: node.property("systemImage"))

        case "Link":
            if let url = URL(string: node.property("url")) {
                Link(node.property("label"), destination: url)
            } else {
                Text(node.property("label"))
            }

        case "ShareLink":
            let item = node.property("item")
            let shareLabel = node.property("label")
            if shareLabel.isEmpty {
                ShareLink(item: item)
            } else {
                ShareLink(item: item) { Text(shareLabel) }
            }

        case "ContentUnavailableView":
            ContentUnavailableView {
                Label(node.property("title"), systemImage: node.property("systemImage"))
            } description: {
                Text(node.property("description"))
            }

        // MARK: sui shapes and gradients

        case "Rectangle":
            Rectangle()

        case "Circle":
            Circle()

        case "Capsule":
            Capsule()

        case "Ellipse":
            Ellipse()

        case "LinearGradient":
            LinearGradient(colors: node.colorList("colors"),
                           startPoint: unitPoint(node.property("startPoint"), fallback: .top),
                           endPoint: unitPoint(node.property("endPoint"), fallback: .bottom))

        case "RadialGradient":
            RadialGradient(colors: node.colorList("colors"),
                           center: unitPoint(node.property("center"), fallback: .center),
                           startRadius: node.number("startRadius") ?? 0,
                           endRadius: node.number("endRadius") ?? 100)

        case "AngularGradient":
            AngularGradient(colors: node.colorList("colors"),
                            center: unitPoint(node.property("center"), fallback: .center))

        case "Divider":
            Divider()

        case "Toggle", "CheckBox":
            if node.bindingName != nil {
                SuiToggle(node: node)
            } else {
                DynamicCheckBox(node: node)
            }

        case "TextField":
            if node.bindingName != nil {
                SuiTextField(node: node, secure: false)
            } else {
                DynamicTextField(node: node)
            }

        case "Canvas":
            DynamicCanvas(node: node)

        case "Board":
            DynamicBoard(node: node)

        case "Slider":
            if node.bindingName != nil {
                SuiSlider(node: node)
            } else {
                DynamicSlider(node: node)
            }

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
                    ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                        DynamicView(node: child).id(child.identity(at: index))
                    }
                }
            }

        default:
            // Unknown view type — render children if any
            if node.childCount > 0 {
                VStack {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                        DynamicView(node: child).id(child.identity(at: index))
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

            // The source describes a `ColorValue` by its constructor -- `Red`,
            // or `Custom(#7c3aed)` with its parameter. Both were dropped here,
            // with a comment saying the mapping was missing; every colour an
            // app set went nowhere, in silence.
            case "ForegroundColor":
                result = AnyView(result.foregroundStyle(suiColorValue(node.modifierString(at: i))))

            case "Background":
                result = AnyView(result.background(suiColorValue(node.modifierString(at: i))))

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

    /// The node's children, as the content of a container.
    @ViewBuilder
    private func childViews() -> some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
            DynamicView(node: child).id(child.identity(at: index))
        }
    }

    /// Equal-width columns (or equal-height rows) for a Lazy*Grid.
    private func flexibleGrid(count: String) -> [GridItem] {
        let n = max(1, Int(count) ?? 1)
        return Array(repeating: GridItem(.flexible()), count: n)
    }

    /// sui names gradient anchors as strings ("top", "bottomTrailing", …).
    private func unitPoint(_ name: String, fallback: UnitPoint) -> UnitPoint {
        switch name.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        case "center": return .center
        case "topleading": return .topLeading
        case "toptrailing": return .topTrailing
        case "bottomleading": return .bottomLeading
        case "bottomtrailing": return .bottomTrailing
        default: return fallback
        }
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
                VideoPlayer(player: player)
                    .frame(minHeight: 220)
                    .onAppear {
                        // iOS won't start playback without an active playback
                        // audio session — macOS doesn't require it.
                        #if os(iOS)
                        try? AVAudioSession.sharedInstance().setCategory(.playback)
                        try? AVAudioSession.sharedInstance().setActive(true)
                        #endif
                        player.play()
                    }
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


// MARK: - Frame dumps
//
// A way to see what the renderer drew on a machine that refuses every outside
// capture. macOS has no equivalent of `simctl io screenshot` or `adb screencap`:
// `screencapture` wants Screen Recording, AppleScript wants Accessibility, and
// idb's macOS companion answers "takeScreenshot: is not implemented". An app,
// though, may rasterise itself.
//
//     SUI_FRAME_DUMP=/tmp/frames  ./MyApp.app/Contents/MacOS/MyApp
//
// writes frame-0000.png at launch and one more after every state write, naming
// each on stderr. Unset, nothing here runs and nothing is allocated.
//
// What it proves, and what it does not: `ImageRenderer` rasterises the SwiftUI
// hierarchy -- the same `DynamicView`, built by the same renderer, from the same
// live tree -- but it does not read the composited window. It shows that the
// renderer produced the right pixels, not that the window server showed them.
// `cacheDisplay(in:to:)` would read the window's backing store and is the wrong
// tool here: SwiftUI does not draw into its hosting view's store, so it returns
// a blank sheet.
#if canImport(AppKit)
import AppKit

private var _suiFrameCount = 0

/// Files written so far, capped so a long run cannot fill a disk.
private let _suiFrameLimit = 200

@MainActor
private func _suiDumpFrame() {
    guard let dir = ProcessInfo.processInfo.environment["SUI_FRAME_DUMP"] else { return }
    if _suiFrameCount >= _suiFrameLimit {
        if _suiFrameCount == _suiFrameLimit {
            _suiFrameCount += 1
            FileHandle.standardError.write(
                "[sui] frame dump stopped at \(_suiFrameLimit) files\n".data(using: .utf8)!)
        }
        return
    }

    let content = DynamicView(node: ViewNode(pointer: viewnode_get_root()))
        .frame(width: 460, alignment: .leading)
        .padding(24)
        .background(Color(nsColor: .textBackgroundColor))

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }

    let name = String(format: "frame-%04d.png", _suiFrameCount)
    _suiFrameCount += 1
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    do {
        try png.write(to: url)
        FileHandle.standardError.write("[sui] \(name)\n".data(using: .utf8)!)
    } catch {
        FileHandle.standardError.write(
            "[sui] could not write \(url.path): \(error)\n".data(using: .utf8)!)
    }
}

/// After SwiftUI has settled, not while it is still applying the change.
@MainActor
private func _suiDumpFrameSoon() {
    guard ProcessInfo.processInfo.environment["SUI_FRAME_DUMP"] != nil else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _suiDumpFrame() }
}
#else
@MainActor private func _suiDumpFrameSoon() {}
#endif

/// Which tab is showing, kept where a tree rebuild cannot reach it.
///
/// One selection for the whole app, as on `aui`. A second TabView would share
/// it; nothing in the vocabulary makes that likely, and the alternative -- a
/// selection per node -- has nowhere stable to live, since a node's identity is
/// its pointer and that changes on every rebuild.
@Observable
final class SuiTabs {
    static let shared = SuiTabs()
    var index = 0
}

/// One observable per state cell, so a write can reach the views that display
/// that cell and no others.
///
/// A dictionary would not do: Observation tracks *properties*, so a store
/// holding `[String: Int]` invalidates every reader of the dictionary on any
/// change — which is the whole-tree behaviour this exists to replace. One object
/// per cell gives one dependency per cell.
///
/// The value itself is not mirrored here. It stays in Haxe, and a view that has
/// been invalidated reads it back through the bridge: two copies of a value are
/// two things that can disagree, and the version counter is enough to say
/// "ask again".
@Observable
final class SuiCell {
    var version: Int = 0
}

final class SuiCells {
    static let shared = SuiCells()
    private var cells: [String: SuiCell] = [:]

    func cell(_ name: String) -> SuiCell {
        if let existing = cells[name] { return existing }
        let made = SuiCell()
        cells[name] = made
        return made
    }

    /// Read the cells a node displays, so SwiftUI records the dependency.
    ///
    /// Called from a view's `body`: Observation notices the reads and
    /// invalidates that view alone when one of them is bumped. The returned sum
    /// is what makes the reads real — an access the compiler can discard
    /// registers nothing.
    @discardableResult
    func track(_ names: [String]) -> Int {
        var seen = 0
        for name in names { seen &+= cell(name).version }
        return seen
    }

    func bump(_ name: String) {
        cell(name).version &+= 1
    }
}

/// Rebuild the tree when the Haxe app writes a state, and tell the view.
///
/// A C function pointer, so it has to be a free function: it is handed to
/// `viewnode_observe_state` and called from wherever `State.set()` ran. The
/// rebuild is hopped onto the main thread, where every other traversal happens.
///
/// Coalesced: one `body()` per turn of the run loop, not one per write. A
/// handler that writes three states in a row asked for one new tree, not three.
private var _suiRebuildPending = false

private func _suiStateDidChange(_ key: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?) {
    _suiStateChanged(key.map { String(cString: $0) } ?? "")
}

/// What a changed cell costs, whichever side changed it.
///
/// A cell that shapes the tree -- a ForEach's list, a condition -- needs a new
/// tree. A cell that is merely displayed does not: bumping it invalidates the
/// views that read it, and they ask Haxe for the value again. Haxe decides
/// which is which; it is the only side that can see where the cell was read.
private func _suiStateChanged(_ name: String) {
    DispatchQueue.main.async {
        if viewnode_is_structural(name) == 0 {
            SuiCells.shared.bump(name)
            _suiDumpFrameSoon()
            return
        }

        if _suiRebuildPending { return }
        _suiRebuildPending = true
        DispatchQueue.main.async {
            _suiRebuildPending = false
            viewnode_rebuild()
            NotificationCenter.default.post(name: .viewTreeDidReload, object: nil)
            _suiDumpFrameSoon()
        }
    }
}

struct HotReloadRootView: View {
    @State private var reloadCount = 0

    // Pump the app's poll delegate on the main thread (drains the WS queue).
    private let pollTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Boot the runtime before the first body evaluation reads the view tree,
    // then listen for the app's own state writes.
    init() {
        _ = _suiRuntimeBooted
        viewnode_observe_state(_suiStateDidChange)
    }

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
            // Constant: there is one root, and it stays the root. Keying it on
            // the node meant a new tree replaced the whole hierarchy.
            .id("sui-root")
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
            .onAppear { _suiDumpFrameSoon() }
    }
}

/// A declared surface root, rendered by its stable id — the generated macOS
/// `Settings` scene draws a `@:surface(Preferences)` declaration through this,
/// live, as a second root.
///
/// No poll timer here, deliberately: the Primary's HotReloadRootView owns the
/// 100 ms poll, and a second timer would pump Haxe's event loop twice per
/// tick. Every root rebuilds together on a structural write (they share the
/// app's one lifetime pass), so riding the same tree-reload notification is
/// not a shortcut — it is the actual contract.
///
/// A missing root draws nothing: that is the degradation contract, never an
/// error on screen.
struct DynamicSurfaceView: View {
    let surfaceId: String
    @State private var reloadCount = 0

    var body: some View {
        // Read reloadCount so a reload re-evaluates body — not as identity;
        // the stable id below lets SwiftUI diff instead of tearing down.
        let _ = reloadCount
        let accent = Color(suiHex: String(cString: viewnode_theme_accent()))
        Group {
            if let root = viewnode_root_for(surfaceId) {
                DynamicView(node: ViewNode(pointer: root))
                    .id("sui-root-\(surfaceId)")
                    .tint(accent)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewTreeDidReload)) { _ in
            withAnimation { reloadCount += 1 }
        }
    }
}

// MARK: - sui controls
//
// Each takes its value through `node.boundValue`, so none of them knows whether
// the app named a cell or the protocol sent a path. They keep no local mirror:
// a write rebuilds the tree, and the next read comes from the cell -- a mirror
// would be a second copy of the value, free to disagree with it.

struct SuiTextField: View {
    let node: ViewNode
    let secure: Bool

    var body: some View {
        let placeholder = node.property("placeholder")
        Group {
            if secure {
                SecureField(placeholder, text: node.boundValue)
            } else {
                TextField(placeholder, text: node.boundValue)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct SuiTextEditor: View {
    let node: ViewNode

    var body: some View {
        TextEditor(text: node.boundValue)
    }
}

struct SuiToggle: View {
    let node: ViewNode

    var body: some View {
        Toggle(node.property("label"), isOn: Binding(
            get: { node.boundValue.wrappedValue == "true" },
            set: { node.boundValue.wrappedValue = $0 ? "true" : "false" }
        ))
    }
}

struct SuiSlider: View {
    let node: ViewNode

    var body: some View {
        let lo = node.number("rangeMin") ?? 0
        let hi = node.number("rangeMax") ?? 1
        Slider(value: Binding(
            get: { Double(node.boundValue.wrappedValue) ?? lo },
            set: { node.boundValue.wrappedValue = String($0) }
        ), in: lo...max(hi, lo + 0.0001))
    }
}

struct SuiStepper: View {
    let node: ViewNode

    var body: some View {
        let lo = Int(node.number("minValue") ?? 0)
        let hi = Int(node.number("maxValue") ?? 100)
        Stepper(node.property("label"), value: Binding(
            get: { Int(node.boundValue.wrappedValue) ?? lo },
            set: { node.boundValue.wrappedValue = String($0) }
        ), in: lo...max(hi, lo))
    }
}

/// A Picker whose options are its children.
///
/// The transpiler read a `.tag(...)` modifier off each option to know what a
/// row *selects*; nothing carries that here, so a row's own text is both what
/// it shows and what it stores. That is what the common case writes anyway --
/// `new Text(name).tag(name)` -- and it is stated rather than silently assumed.
struct SuiPicker: View {
    let node: ViewNode

    var body: some View {
        Picker(node.property("label"), selection: node.boundValue) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                Text(child.textContent).tag(child.textContent)
            }
        }
    }
}

struct SuiColorPicker: View {
    let node: ViewNode

    var body: some View {
        ColorPicker(node.property("label"), selection: Binding(
            get: { Color(suiHex: node.boundValue.wrappedValue) ?? .accentColor },
            set: { node.boundValue.wrappedValue = $0.suiHexString } 
        ))
    }
}

/// A date picker over a cell holding an ISO-8601 string.
///
/// sui has three of these and they differ only in what they let you touch, so
/// they share one view: the value crosses as text either way, and a date that
/// cannot be parsed falls back to now rather than to 1970 -- a control opening
/// on the Unix epoch reads as broken, not as empty.
struct SuiDatePicker: View {
    let node: ViewNode
    let timeOnly: Bool

    var body: some View {
        DatePicker(node.property("label"), selection: Binding(
            get: { ViewNode.isoFormatter.date(from: node.boundValue.wrappedValue) ?? Date() },
            set: { node.boundValue.wrappedValue = ViewNode.isoFormatter.string(from: $0) }
        ), displayedComponents: timeOnly ? [.hourAndMinute] : [.date])
    }
}

extension ViewNode {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension Color {
    /// The hex a ColorPicker writes back, in the form `Color(suiHex:)` reads.
    var suiHexString: String {
        #if canImport(AppKit)
        let native = NSColor(self).usingColorSpace(.sRGB)
        let r = native?.redComponent ?? 0, g = native?.greenComponent ?? 0, b = native?.blueComponent ?? 0
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

/// A sui `ColorValue`, by the name `sui.nui.ViewSource` gives it.
///
/// Constructors, not hex: `Red`, `Primary`, and `Custom(#7c3aed)` carrying its
/// parameter. This is the app's own palette; `suiThemeColor` above maps the
/// *protocol's* tokens (`surface`, `onPrimary`), which are a different set with
/// different names, and conflating them would answer both questions wrongly.
func suiColorValue(_ raw: String) -> Color {
    let name = raw.trimmingCharacters(in: .whitespaces)
    if name.hasPrefix("Custom(") && name.hasSuffix(")") {
        let hex = String(name.dropFirst("Custom(".count).dropLast())
        return Color(suiHex: hex) ?? .primary
    }
    switch name {
    case "Primary":   return .primary
    case "Secondary": return .secondary
    case "Accent":    return .accentColor
    case "Red":       return .red
    case "Orange":    return .orange
    case "Yellow":    return .yellow
    case "Green":     return .green
    case "Blue":      return .blue
    case "Purple":    return .purple
    case "Pink":      return .pink
    case "White":     return .white
    case "Black":     return .black
    case "Gray":      return .gray
    case "Clear":     return .clear
    default:          return .primary
    }
}

extension Notification.Name {
    static let viewTreeDidReload = Notification.Name("viewTreeDidReload")
}
