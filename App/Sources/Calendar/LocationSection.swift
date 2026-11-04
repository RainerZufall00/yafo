import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Ort im Termin-Detail: mit Koordinaten als kleine Karte, sonst als Text; beides öffnet Apple Maps.
struct LocationSection: View {
    let location: String
    let geo: GeoPoint?

    var body: some View {
        if let geo {
            Map(initialPosition: .region(MKCoordinateRegion(center: geo.coordinate, latitudinalMeters: 600,
                                                            longitudinalMeters: 600)),
                interactionModes: []) {
                Marker(location, coordinate: geo.coordinate)
                    .tint(.red)
            }
            .frame(height: 150)
            .listRowInsets(EdgeInsets())
            .onTapGesture(perform: openInMaps)
            .accessibilityHidden(true)
        }
        Button(action: openInMaps) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(location)
                        .foregroundStyle(.primary)
                    Text("Open in Maps")
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }

    private func openInMaps() {
        if let geo {
            let item = MKMapItem(location: CLLocation(latitude: geo.coordinate.latitude,
                                                      longitude: geo.coordinate.longitude), address: nil)
            item.name = location.components(separatedBy: ", ").first ?? location
            item.openInMaps()
        } else if let url = URL(string: "maps://?q=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }
}
