import PhotosUI
import SwiftUI
import YafoKit

/// „Screenshot zu Termin“ in der App: Bild aus Fotos wählen, Vorschau, direkt speichern.
/// Über die Share Extension geht dasselbe aus jeder App heraus.
struct ScreenshotImportModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var pickedItem: PhotosPickerItem?
    @State private var picked: PickedImage?

    struct PickedImage: Identifiable {
        let id = UUID()
        let item: PhotosPickerItem
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $pickedItem, matching: .images,
                          preferredItemEncoding: .current)
            .onChange(of: pickedItem) { _, item in
                if let item { picked = PickedImage(item: item) }
                pickedItem = nil
            }
            .sheet(item: $picked) { picked in
                ScreenshotReviewView(
                    calendars: calendarOptions,
                    loadImage: {
                        guard let data = try? await picked.item.loadTransferable(type: Data.self) else { return nil }
                        return UIImage(data: data)
                    },
                    onSave: { suggestions, calendarID in
                        save(suggestions, calendarID: calendarID)
                        self.picked = nil
                    },
                    onCancel: { self.picked = nil }
                )
            }
    }

    private var calendarOptions: [ScreenshotReviewView.CalendarOption] {
        model.repository.calendars().compactMap { calendar in
            guard let id = calendar.id else { return nil }
            let name = calendar.family?.name.map { "\(calendar.displayName) · \($0)" } ?? calendar.displayName
            return ScreenshotReviewView.CalendarOption(id: id, name: name, colorHex: model.repository.color(of: calendar))
        }
    }

    private func save(_ suggestions: [EventSuggestion], calendarID: UUID) {
        guard let calendar = model.repository.calendars().first(where: { $0.id == calendarID }) else { return }
        model.repository.addEvents(suggestions, to: calendar, createdBy: model.creatorID(for: calendar))
        model.save()
    }
}

extension View {
    func screenshotImport(isPresented: Binding<Bool>) -> some View {
        modifier(ScreenshotImportModifier(isPresented: isPresented))
    }
}
