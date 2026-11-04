import CoreLocation
import MapKit
import SwiftUI
import YafoKit

/// Ortsfeld im Termin-Editor: freier Text, beim Tippen Vorschläge aus Apple Maps.
/// Wer einen Vorschlag wählt, bekommt Name und Adresse plus Koordinaten (`geo`);
/// wer den Text danach von Hand ändert, verliert die Koordinaten wieder.
/// Läuft auch in der Share Extension (darum ohne `UIApplication`).
struct LocationField: View {
    @Binding var location: String
    @Binding var geo: String?
    /// Vorschläge gleich zeigen, ohne dass jemand ins Feld tippt, z. B. für einen erkannten Ort.
    var suggestsInitially = false

    @State private var completer = LocationCompleter()
    @State private var resolving = false
    /// Text, zu dem `geo` gehört; weicht das Feld davon ab, gilt `geo` nicht mehr.
    @State private var resolvedText: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Location", text: $location)
                .focused($focused)
                .textContentType(.location)
            if resolving {
                ProgressView()
            } else if geo != nil {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Location on map")
            }
        }
        .onAppear {
            if geo != nil {
                resolvedText = location
            } else if suggestsInitially {
                completer.query = location
            }
        }
        .onChange(of: location) {
            if location != resolvedText { geo = nil }
            completer.query = focused && geo == nil ? location : ""
        }
        .onChange(of: focused) {
            completer.query = focused && geo == nil ? location : ""
        }
        .onChange(of: geo) {
            // Von außen gefunden (Adresse im Screenshot): Vorschläge braucht es dann nicht mehr.
            if geo != nil, resolvedText != location {
                resolvedText = location
                completer.query = ""
            }
        }

        ForEach(completer.results.prefix(5), id: \.self) { result in
            Button {
                Task { await choose(result) }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func choose(_ result: MKLocalSearchCompletion) async {
        let text = result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
        resolvedText = text
        location = text
        completer.query = ""
        focused = false
        resolving = true
        defer { resolving = false }
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start()
        // Nur übernehmen, wenn inzwischen nichts anderes getippt wurde.
        if location == text, let coordinate = response?.mapItems.first?.location.coordinate {
            geo = GeoPoint(coordinate).text
        }
    }
}

extension LocationField {
    /// Koordinaten für eine vollständige Adresse („Schillerstraße 12, 10625 Berlin“), sonst `nil`.
    /// Bloße Namen wie „Aula“ sind zu mehrdeutig, dafür gibt es die Vorschläge zum Antippen.
    static func resolveAddress(_ text: String) async -> String? {
        let looksLikeAddress = text.range(of: #"\b\d{4,5}\b|\p{L}(str\.|straße|strasse|weg|platz|allee|gasse|ring|damm)\s*\d"#,
                                          options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: #"\d+\s+\p{L}+\s+(street|st|road|rd|avenue|ave|lane|drive)\b"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
        guard looksLikeAddress else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first.map { GeoPoint($0.location.coordinate).text }
    }
}

/// Liefert Vorschläge für Orte und Adressen, während getippt wird.
@Observable
final class LocationCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.count < 2 {
                completer.cancel()
                results = []
            } else if trimmed != completer.queryFragment {
                completer.queryFragment = trimmed
            }
        }
    }

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Der Completer ruft auf dem Main Thread zurück; gelesen wird der eigene.
        MainActor.assumeIsolated { self.results = query.isEmpty ? [] : self.completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { self.results = [] }
    }
}

/// Koordinaten als Text „Breite,Länge“, so wie sie in `Event.geo` stehen.
struct GeoPoint {
    let coordinate: CLLocationCoordinate2D

    init(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }

    init?(_ text: String?) {
        let parts = text?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let parts, parts.count == 2, (-90...90).contains(parts[0]), (-180...180).contains(parts[1]) else {
            return nil
        }
        coordinate = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    var text: String {
        String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"),
               coordinate.latitude, coordinate.longitude)
    }
}
