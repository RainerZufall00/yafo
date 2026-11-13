import SwiftUI

/// Bedienung der App, umschaltbar unter „Familie“ und nur auf diesem Gerät gespeichert.
/// - `tabs`: Tab-Leiste unten, Monate seitlich blättern (Standard).
/// - `swipe`: ohne Tab-Leiste; der Kalender blättert Monate nach oben und unten wie bei Apple,
///   links daneben liegen die Todos, rechts die Einkaufsliste.
/// In beiden öffnet ein Knopf oben rechts „Familie“ (`familyButton()`).
enum InterfaceStyle: String, CaseIterable, Identifiable {
    case tabs
    case swipe

    static let storageKey = "interfaceStyle"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .tabs: "Tabs"
        case .swipe: "Swipe"
        }
    }
}

/// Seitenanzeige im Wisch-Modus: zeigt, wo man ist, und wechselt per Tippen
/// (auch für VoiceOver, das Wischen zwischen Seiten nicht ohne Weiteres kann).
struct PageSwitcher: View {
    @Binding var tab: AppTab

    /// Platz, den die Seiten unten für die Anzeige freihalten.
    static let height: CGFloat = 52

    var body: some View {
        HStack(spacing: 2) {
            item(.todos, title: "To-dos", systemImage: "checklist")
            item(.calendar, title: "Calendar", systemImage: "calendar")
            item(.shopping, title: "Shopping", systemImage: "cart")
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 4)
    }

    private func item(_ page: AppTab, title: LocalizedStringKey, systemImage: String) -> some View {
        let isSelected = tab == page
        return Button {
            withAnimation(.snappy) { tab = page }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                if isSelected {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, isSelected ? 14 : 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Knopf „Familie“ oben rechts auf Kalender, Einkauf und Todos, öffnet die Einstellungen als Blatt.
/// Fehlt in einer Familie das eigene Profil, zeigt das Symbol ein Ausrufezeichen.
private struct FamilyButton: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Family", systemImage: model.familiesNeedingProfile.isEmpty
                           ? "person.3" : "person.crop.circle.badge.exclamationmark") { showing = true }
                }
            }
            .sheet(isPresented: $showing) {
                FamilyView(onDone: { showing = false })
            }
    }
}

extension View {
    /// Knopf „Familie“ oben rechts, in beiden Bedienungen.
    func familyButton() -> some View {
        modifier(FamilyButton())
    }
}
