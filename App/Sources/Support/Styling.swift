import SwiftUI
import UIKit
import YafoKit

extension Color {
    /// Farbe aus `#RRGGBB`; ungültige Werte werden grau.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}

/// Initialen-Avatar eines Mitglieds; Kinder mit gestricheltem Rand.
struct MemberAvatar: View {
    @ObservedObject var member: Member
    var size: CGFloat = 26

    var body: some View {
        Text(member.initials ?? "?")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.secondary.opacity(0.15)))
            .overlay {
                if member.kind == .child {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(member.displayLabel)
    }
}

extension Member {
    /// Name, ehemalige Mitglieder mit Zusatz „(ehemalig)“.
    var displayLabel: String {
        let name = displayName ?? "?"
        return leftAt == nil ? name : String(localized: "\(name) (former)")
    }
}

extension EventCalendar {
    var displayName: String { name ?? String(localized: "Calendar") }
}
