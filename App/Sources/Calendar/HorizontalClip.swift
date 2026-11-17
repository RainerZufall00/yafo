import SwiftUI

extension View {
    /// Schneidet links und rechts am eigenen Rahmen ab, oben und unten nicht.
    ///
    /// Seitlich blätternde Scroll-Ansichten zeichnen bis unter seitliche Systemleisten. Wo das System
    /// Uhrzeit, Leisten und Tabs als Streifen an den Rand legt (iPhone Duo zugeklappt, iPhone quer),
    /// schaut dort sonst die nächste Seite hervor. Oben und unten darf der Inhalt weiter unter die
    /// Leisten laufen.
    func clipsHorizontally() -> some View {
        mask {
            Rectangle().padding(.vertical, -10_000)
        }
    }
}
