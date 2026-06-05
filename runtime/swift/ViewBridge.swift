import SwiftUI

/// Protocol for generated views that bridge to Haxe state.
/// In Phase 2+, this connects SwiftUI views to Haxe/C++ state via the bridge.
protocol HaxeView: View {
    func haxeOnAppear()
    func haxeOnDisappear()
}

extension HaxeView {
    func haxeOnAppear() {}
    func haxeOnDisappear() {}
}

/// `Color(suiHex:)` — parses "#RRGGBB", "RRGGBB", 3-digit shorthand
/// `#RGB`, or 8-digit `#RRGGBBAA` with an alpha channel. Use the
/// alpha form (`"#00000000"`) when you want a state-driven colour
/// that conditionally renders nothing — empty/invalid strings fall
/// back via the nil-coalescing operator the macro emits:
/// `Color(suiHex: appState.x) ?? .primary`.
///
/// Used by sui's foregroundHex / backgroundHex modifiers — codegen
/// emits the optional-fallback expression so user state values that
/// aren't well-formed hex don't crash the SwiftUI body.
extension Color {
    init?(suiHex: String) {
        var s = suiHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        let len = s.count
        guard (len == 6 || len == 8),
              let v = UInt64(s, radix: 16)
        else { return nil }
        if len == 8 {
            let r = Double((v >> 24) & 0xFF) / 255.0
            let g = Double((v >> 16) & 0xFF) / 255.0
            let b = Double((v >> 8) & 0xFF) / 255.0
            let a = Double(v & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        } else {
            let r = Double((v >> 16) & 0xFF) / 255.0
            let g = Double((v >> 8) & 0xFF) / 255.0
            let b = Double(v & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        }
    }
}
