import AppKit
import SwiftUI

/// SparkPlug's colours. Text and backgrounds use the system's own colours so dark mode works;
/// the accents (indigo, the focus yellow) are the brand's.
enum Theme {
    static let accent = Color(hex: "#5b5fe6")
    static let focus = Color(hex: "#ffd84d")
    static let focusInk = Color(hex: "#2a2300")
    static let focusEdge = Color(hex: "#f0c419")
    static let now = Color(hex: "#ff3b30")

    static let taskFill = Color.dynamic(light: "#f3f3ff", dark: "#2a2b4d")
    static let taskInk = Color.dynamic(light: "#3135b0", dark: "#c4c6ff")
    static let taskEdge = Color.dynamic(light: "#a5a7f3", dark: "#6d70e0")
    static let chipFill = Color.dynamic(light: "#efefff", dark: "#30315a")
    static let chipInk = Color.dynamic(light: "#3a3dba", dark: "#c4c6ff")
    static let ring = Color.dynamic(light: "#c7c7cc", dark: "#5a5a60")
    static let hover = Color.dynamic(light: "#f5f5f7", dark: "#2c2c30")
    static let rule = Color.dynamic(light: "#ececee", dark: "#38383c")
    static let hourLine = Color.dynamic(light: "#efeff1", dark: "#323236")
    static let todayColumn = Color.dynamic(light: "#fafaff", dark: "#1f1f2b")
    static let secondary = Color.dynamic(light: "#86868b", dark: "#98989d")
    static let tertiary = Color.dynamic(light: "#8e8e93", dark: "#8e8e93")
    static let sectionLabel = Color.primary.opacity(0.45)

    /// An event's fill: its calendar's colour, washed out (light) or dimmed (dark).
    static func eventFill(_ hex: String) -> Color {
        let c = NSColor(hex: hex)
        return Color(
            nsColor: NSColor(name: nil) { ap in
                ap.isDark ? c.blended(withFraction: 0.68, of: .black)! : c.blended(withFraction: 0.88, of: .white)!
            })
    }

    /// An event's text: its calendar's colour, darkened (light) or lightened (dark).
    static func eventInk(_ hex: String) -> Color {
        let c = NSColor(hex: hex)
        return Color(
            nsColor: NSColor(name: nil) { ap in
                ap.isDark ? c.blended(withFraction: 0.55, of: .white)! : c.blended(withFraction: 0.4, of: .black)!
            })
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x8e8e93
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }

    static func dynamic(light: String, dark: String) -> Color {
        let l = NSColor(hex: light), d = NSColor(hex: dark)
        return Color(nsColor: NSColor(name: nil) { $0.isDark ? d : l })
    }
}

/// SparkPlug's bolt, from the logo (a 24×24 drawing).
struct Bolt: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(13, 3), (13, 10), (19, 10), (11, 21), (11, 14), (5, 14)]
        let sx = rect.width / 24, sy = rect.height / 24
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + pts[0].0 * sx, y: rect.minY + pts[0].1 * sy))
        for (x, y) in pts.dropFirst() { p.addLine(to: CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)) }
        p.closeSubpath()
        return p
    }
}

/// The round checkbox in task rows.
struct Ring: View {
    var done: Bool
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            Circle().strokeBorder(done ? Theme.accent : Theme.ring, lineWidth: 1.5)
                .background(Circle().fill(done ? Theme.accent : .clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
