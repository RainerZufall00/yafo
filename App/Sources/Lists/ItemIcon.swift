import SwiftUI
import UIKit

/// Gezeichnete Artikelgrafik (Asset `item-<icon>`, einfarbig, folgt `foregroundStyle`).
/// Fehlt sie, steht das Emoji da.
struct ItemIcon: View {
    let icon: String
    let emoji: String

    var body: some View {
        let name = "item-\(icon)"
        if UIImage(named: name) != nil {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            GeometryReader { geometry in
                Text(emoji)
                    .font(.system(size: geometry.size.height * 0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
        }
    }
}
