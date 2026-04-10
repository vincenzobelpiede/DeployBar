import SwiftUI

// MARK: - Appearance preference

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"
    var id: String { rawValue }
}

// MARK: - Semantic colors

/// Adaptive semantic colors for DeployBar.
/// Dark values match the original hard-coded palette; light values are
/// designed to feel native on macOS while keeping the same accent hierarchy.
enum Theme {

    // ── Backgrounds ──────────────────────────────────────────────────

    /// Main popover / window background.
    static let background = Color("background")
    /// Card / row surface.
    static let surface = Color("surface")
    /// Code block / log background.
    static let codeBackground = Color("codeBackground")

    // ── Foreground / text ────────────────────────────────────────────

    /// Primary text.
    static let textPrimary = Color("textPrimary")
    /// Secondary / label text.
    static let textSecondary = Color("textSecondary")
    /// Tertiary / muted text.
    static let textTertiary = Color("textTertiary")
    /// Disabled text.
    static let textDisabled = Color("textDisabled")

    // ── Borders & dividers ───────────────────────────────────────────

    static let divider = Color("dividerColor")

    // ── Accent colors (fixed across modes) ───────────────────────────

    static let accent      = Color(red: 0.13, green: 0.77, blue: 0.37)   // green
    static let accentBlue  = Color(red: 0.23, green: 0.51, blue: 0.96)   // blue
    static let warning     = Color(red: 0.96, green: 0.62, blue: 0.04)   // orange
    static let error       = Color(red: 0.94, green: 0.27, blue: 0.27)   // red

    /// Text color on top of accent button (always black).
    static let accentLabel = Color.black
}
