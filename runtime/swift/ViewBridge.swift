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

/// `Color(suiHex:)` — parses "#RRGGBB", "RRGGBB" or 3-digit shorthand.
/// Returns `nil` for invalid input so call sites can fall back via the
/// nil-coalescing operator: `Color(suiHex: appState.calendarColor) ?? .primary`.
///
/// Used by sui's foregroundHex / backgroundHex modifiers — codegen emits
/// the optional-fallback expression so user state values that aren't
/// well-formed hex don't crash the SwiftUI body.
extension Color {
    init?(suiHex: String) {
        var s = suiHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6,
              let v = UInt32(s, radix: 16)
        else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
