// Setzt die Rohaufnahmen aus dem Simulator zu App-Store-Bildern zusammen: Überschrift, Unterzeile, Gerät mit Rahmen –
// je Sprache (de-DE, en-US) für iPhone 6,9", iPhone 6,3" und iPad 13". Dazu ein Werbebild im Querformat (Promo/) und die
// „Creative Assets“ für App Store Connect (Creative/): Kopfzeile der Produktseite (21:9) und Bild für Suchergebnisse (3:2).
// Aufruf (im Repo-Wurzelverzeichnis): swift AppStore/Tools/compose-screenshots.swift AppStore/Screenshots/raw AppStore/Screenshots
// Die Rohaufnahmen entstehen mit AppStore/Tools/capture-screenshots.sh (raw/de, raw/en).
// Mit „duo“ als drittem Argument nur die Bilder fürs iPhone Duo (aus capture-duo-screenshots.sh).
// Vorlage: dasselbe Skript in Auslese; Farben aus dem App-Icon (Tools/AppIcon/build.swift).

import AppKit
import SwiftUI

let arguments = CommandLine.arguments
let rawDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "AppStore/Screenshots/raw")
let outputDirectory = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "AppStore/Screenshots")
let onlyDuo = arguments.count > 3 && arguments[3] == "duo"

// MARK: - Marke

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Grün und Gelb aus dem App-Icon „Familie vor dem Y“.
enum Brand {
    static let green = Color(hex: 0x1D7A4F)
    static let greenDark = Color(hex: 0x0F4A2F)
    static let yellow = Color(hex: 0xFFD84D)
    static let mint = Color(hex: 0xF3FAF5)
    static let mintDeep = Color(hex: 0xDDF0E4)
    static let ink = Color(hex: 0x0C2E1E)
}

enum Theme {
    case light
    case dark
}

// MARK: - Geräte

struct Device {
    let folder: String
    let canvas: CGSize
    let screenWidth: CGFloat
    let cornerRadius: CGFloat
    let bezel: CGFloat
    let headlineSize: CGFloat
    let sublineSize: CGFloat
    let textTop: CGFloat
    let textWidth: CGFloat

    /// iPhone 6,9" (1320 × 2868).
    static let iPhone = Device(folder: "iPhone-6.9", canvas: CGSize(width: 1320, height: 2868), screenWidth: 1030,
                               cornerRadius: 150, bezel: 24, headlineSize: 128, sublineSize: 52,
                               textTop: 190, textWidth: 1160)
    /// iPhone 6,1"/6,3" (1206 × 2622) – dasselbe Layout, verkleinert; fast dasselbe Seitenverhältnis wie 6,9".
    static let iPhoneCompact = iPhone.scaled(folder: "iPhone-6.3", to: CGSize(width: 1206, height: 2622))
    /// iPad 13" (2064 × 2752) – gilt im App Store auch für alle kleineren iPads.
    static let iPad = Device(folder: "iPad-13", canvas: CGSize(width: 2064, height: 2752), screenWidth: 1600,
                             cornerRadius: 56, bezel: 34, headlineSize: 132, sublineSize: 54,
                             textTop: 180, textWidth: 1700)

    /// iPhone Duo, äußeres Display (1398 × 2034).
    static let duoOuter = Device(folder: "iPhone-Duo-aussen", canvas: CGSize(width: 1398, height: 2034), screenWidth: 1110,
                                 cornerRadius: 96, bezel: 22, headlineSize: 100, sublineSize: 42,
                                 textTop: 120, textWidth: 1240)
    /// iPhone Duo, inneres Display (2007 × 2853).
    static let duoInner = Device(folder: "iPhone-Duo-innen", canvas: CGSize(width: 2007, height: 2853), screenWidth: 1580,
                                 cornerRadius: 96, bezel: 34, headlineSize: 128, sublineSize: 52,
                                 textTop: 180, textWidth: 1700)

    func scaled(folder: String, to canvas: CGSize) -> Device {
        let factor = canvas.width / self.canvas.width
        return Device(folder: folder, canvas: canvas, screenWidth: screenWidth * factor, cornerRadius: cornerRadius * factor,
                      bezel: bezel * factor, headlineSize: headlineSize * factor, sublineSize: sublineSize * factor,
                      textTop: textTop * factor, textWidth: textWidth * factor)
    }
}

// MARK: - Layout

struct Shot {
    let raw: String
    let output: String
    let headline: String
    let subline: String
    let theme: Theme
}

struct Poster: View {
    let device: Device
    let shot: Shot
    let screenshot: NSImage

    var body: some View {
        let isDark = shot.theme == .dark
        ZStack(alignment: .top) {
            background(isDark: isDark)

            // Das Gerät folgt dem Text – egal, ob die Überschrift ein- oder zweizeilig ist.
            VStack(spacing: device.sublineSize * 1.6) {
            VStack(spacing: device.sublineSize * 0.55) {
                Text(shot.headline)
                    .font(.system(size: device.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(isDark ? Brand.mint : Brand.ink)
                    .lineSpacing(-device.headlineSize * 0.08)
                Text(shot.subline)
                    .font(.system(size: device.sublineSize, weight: .medium))
                    .foregroundStyle(isDark ? Brand.yellow : Brand.green)
                    .lineSpacing(device.sublineSize * 0.12)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: device.textWidth)

            framedScreen
            }
            .padding(.top, device.textTop)
        }
        .frame(width: device.canvas.width, height: device.canvas.height, alignment: .top)
        .clipped()
    }

    private func background(isDark: Bool) -> some View {
        ZStack {
            if isDark {
                LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Brand.mint, Brand.mintDeep], startPoint: .top, endPoint: .bottom)
            }
            // Drei Kreise wie die Köpfe im App-Icon, angeschnitten am Rand.
            Circle()
                .fill(Brand.yellow.opacity(isDark ? 0.22 : 0.28))
                .frame(width: device.canvas.width * 0.55)
                .offset(x: device.canvas.width * 0.42, y: -device.canvas.height * 0.36)
            Circle()
                .fill(Brand.yellow.opacity(isDark ? 0.14 : 0.18))
                .frame(width: device.canvas.width * 0.3)
                .offset(x: -device.canvas.width * 0.46, y: -device.canvas.height * 0.2)
            Circle()
                .fill((isDark ? Brand.yellow : Brand.green).opacity(isDark ? 0.10 : 0.06))
                .frame(width: device.canvas.width * 0.7)
                .offset(x: -device.canvas.width * 0.38, y: device.canvas.height * 0.4)
        }
    }

    private var framedScreen: some View {
        FramedScreen(screenshot: screenshot, width: device.screenWidth, cornerRadius: device.cornerRadius, bezel: device.bezel)
    }
}

/// Bildschirmaufnahme in einem schlichten Geräterahmen.
struct FramedScreen: View {
    let screenshot: NSImage
    let width: CGFloat
    let cornerRadius: CGFloat
    let bezel: CGFloat

    var body: some View {
        let height = width * screenshot.size.height / screenshot.size.width
        return Image(nsImage: screenshot)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .padding(bezel)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius + bezel, style: .continuous)
                    .fill(Color(hex: 0x141416))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + bezel, style: .continuous)
                    .strokeBorder(Color(hex: 0x4A4A50), lineWidth: bezel * 0.22)
            )
            .shadow(color: Brand.ink.opacity(0.35), radius: 60, y: 30)
    }
}

/// Querformat für Website, Social Media und Presse: Icon, Name, Claim und zwei iPhones.
struct Banner: View {
    static let size = CGSize(width: 1920, height: 1080)

    let icon: NSImage
    let front: NSImage
    let back: NSImage
    let claim: String
    let facts: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Brand.yellow.opacity(0.2))
                .frame(width: 900)
                .offset(x: 1250, y: -420)
            Circle()
                .fill(Brand.yellow.opacity(0.1))
                .frame(width: 520)
                .offset(x: -200, y: 720)

            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 168, height: 168)
                    .clipShape(.rect(cornerRadius: 38, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                Text("yafo")
                    .font(.system(size: 132, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.mint)
                    .padding(.top, 48)
                Text(claim)
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.yellow)
                    .fixedSize()
                    .padding(.top, 8)
                Text(facts)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Brand.mint.opacity(0.8))
                    .lineSpacing(8)
                    .fixedSize()
                    .padding(.top, 40)
            }
            .padding(.leading, 140)
            .padding(.top, 150)

            FramedScreen(screenshot: back, width: 400, cornerRadius: 58, bezel: 11)
                .rotationEffect(.degrees(6))
                .offset(x: 1420, y: 150)
            FramedScreen(screenshot: front, width: 420, cornerRadius: 60, bezel: 12)
                .rotationEffect(.degrees(-4))
                .offset(x: 1030, y: 210)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
    }
}

/// Kopfzeile der Produktseite – 21:9, 3840 × 1646. Apple beschneidet je nach Gerät stark; der sichere Bereich liegt
/// mittig (laut Apples Vorlage etwa 1646 × 661). Dort steht nur der Claim, die iPhones links und rechts sind Dekoration.
struct HeaderArt: View {
    static let size = CGSize(width: 3840, height: 1646)

    let left: NSImage
    let right: NSImage
    let first: String
    let second: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Brand.yellow.opacity(0.18))
                .frame(width: 1500)
                .offset(x: 1500, y: -700)
            Circle()
                .fill(Brand.yellow.opacity(0.1))
                .frame(width: 900)
                .offset(x: -1650, y: 650)

            FramedScreen(screenshot: left, width: 660, cornerRadius: 96, bezel: 18)
                .rotationEffect(.degrees(-8))
                .offset(x: -1330, y: 260)
            FramedScreen(screenshot: right, width: 660, cornerRadius: 96, bezel: 18)
                .rotationEffect(.degrees(8))
                .offset(x: 1330, y: 260)

            VStack(spacing: 10) {
                Text(first).foregroundStyle(Brand.mint)
                Text(second).foregroundStyle(Brand.yellow)
            }
            .font(.system(size: 168, weight: .bold, design: .rounded))
            .fixedSize()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }
}

/// Bild für die App-Store-Suche – 3:2, 3840 × 2560. „State the obvious“: links, was die App ist, rechts die App selbst.
/// Der sichere Bereich liegt mittig (laut Apples Vorlage etwa 2168 × 1030).
struct SearchArt: View {
    static let size = CGSize(width: 3840, height: 2560)

    let front: NSImage
    let back: NSImage
    let kicker: String
    let headline: String
    let subline: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Brand.mint, Brand.mintDeep], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Brand.yellow.opacity(0.3))
                .frame(width: 1800)
                .offset(x: 2500, y: -700)
            Circle()
                .fill(Brand.green.opacity(0.06))
                .frame(width: 1400)
                .offset(x: -500, y: 1600)

            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .font(.system(size: 76, weight: .bold))
                    .tracking(10)
                    .foregroundStyle(Brand.green)
                Text(headline)
                    .font(.system(size: 196, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .lineSpacing(-10)
                    .padding(.top, 30)
                Text(subline)
                    .font(.system(size: 96, weight: .medium))
                    .foregroundStyle(Brand.green)
                    .padding(.top, 50)
            }
            .fixedSize()
            .frame(width: 1250, alignment: .leading)
            .offset(x: 860, y: 790)

            FramedScreen(screenshot: back, width: 720, cornerRadius: 106, bezel: 20)
                .rotationEffect(.degrees(6))
                .offset(x: 2930, y: 380)
            FramedScreen(screenshot: front, width: 780, cornerRadius: 114, bezel: 22)
                .rotationEffect(.degrees(-4))
                .offset(x: 2290, y: 560)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - Inhalte

struct Language {
    /// Ordner der Rohaufnahmen (raw/de, raw/en).
    let raw: String
    /// App-Store-Sprache, zugleich Ausgabeordner.
    let locale: String
    let iPhone: [Shot]
    let iPad: [Shot]
    /// Fürs iPhone Duo: außen und innen je fünf.
    let duoOuter: [Shot]
    let duoInner: [Shot]
    let claim: String
    let facts: String
    /// Kopfzeile: zwei kurze Zeilen. Suchergebnisse: Stichwort, Titel, Unterzeile.
    let header: (String, String)
    let search: (kicker: String, headline: String, subline: String)
}

/// Motive, gemeinsam für iPhone und iPad. Auf dem iPad steht die Unterzeile in einer Zeile.
struct Motif {
    let raw: String
    let output: String
    let headline: String
    let subline: String
    let theme: Theme

    /// `wide`: Unterzeile in einer Zeile (iPad, Duo innen).
    func shot(prefix: String, wide: Bool = false) -> Shot {
        Shot(raw: "\(prefix)-\(raw)", output: output, headline: headline,
             subline: wide ? subline.replacingOccurrences(of: "\n", with: " ") : subline, theme: theme)
    }
}

func language(raw: String, locale: String, motifs: [Motif], duoOuter: [String], duoInner: [String], claim: String,
              facts: String, header: (String, String), search: (kicker: String, headline: String, subline: String))
    -> Language {
    func pick(_ names: [String], prefix: String, wide: Bool) -> [Shot] {
        names.compactMap { name in motifs.first { $0.raw == name }?.shot(prefix: prefix, wide: wide) }
    }
    return Language(raw: raw, locale: locale,
                    iPhone: motifs.map { $0.shot(prefix: "iphone") },
                    iPad: motifs.map { $0.shot(prefix: "ipad", wide: true) },
                    duoOuter: pick(duoOuter, prefix: "duo-outer", wide: false),
                    duoInner: pick(duoInner, prefix: "duo-inner", wide: true),
                    claim: claim, facts: facts, header: header, search: search)
}

/// Fürs iPhone Duo je fünf: außen die Listen fürs Unterwegs, innen die großen Kalenderansichten.
let duoOuter = ["month", "shopping", "todos", "event", "family"]
let duoInner = ["month", "screenshot", "dark", "shopping", "event"]

let german = language(
    raw: "de", locale: "de-DE",
    motifs: [
        Motif(raw: "month", output: "01-kalender", headline: "Ein Kalender.\nDie ganze Familie.",
              subline: "Gemeinsame und eigene Kalender –\nklar nach Farben getrennt.", theme: .light),
        Motif(raw: "event", output: "02-absprechen", headline: "Absprechen,\nwo es passiert.",
              subline: "Wer dabei ist und wer die Snacks\nmitbringt – direkt am Termin.", theme: .dark),
        Motif(raw: "shopping", output: "03-einkauf", headline: "Einkaufen in\nLaufreihenfolge.",
              subline: "Kacheln mit Symbolen, nach Abteilungen\nsortiert – für alle sofort aktuell.", theme: .light),
        Motif(raw: "todos", output: "04-todos", headline: "Wer macht was?",
              subline: "Todos mit Zuständigen und Fälligkeit.\nWiederkehrende rollen einfach weiter.", theme: .dark),
        Motif(raw: "screenshot", output: "05-screenshot", headline: "Aus Screenshot\nwird Termin.",
              subline: "Elternbrief teilen – yafo erkennt Datum,\nUhrzeit und Ort. Auf dem Gerät.", theme: .light),
        Motif(raw: "dark", output: "06-woche", headline: "Tabs oder Wischen.",
              subline: "Die Woche auf einen Blick –\nin hell und dunkel.", theme: .dark),
        Motif(raw: "family", output: "07-privat", headline: "Kein Konto.\nKeine Werbung.",
              subline: "Alles liegt in eurer iCloud.\nDie Familie per QR-Code einladen.", theme: .light),
    ],
    duoOuter: duoOuter, duoInner: duoInner,
    claim: "Ein Kalender.\nDie ganze Familie.",
    facts: "Kalender, Einkaufsliste und Todos für iPhone und iPad\nGeteilt über iCloud · kein Konto · kein Tracking",
    header: ("Ein Kalender.", "Die ganze Familie."),
    search: ("FAMILIEN-ORGANIZER", "Familie,\norganisiert.", "Gemeinsam. Über iCloud. Privat.")
)

let english = language(
    raw: "en", locale: "en-US",
    motifs: [
        Motif(raw: "month", output: "01-calendar", headline: "One calendar.\nThe whole family.",
              subline: "Shared and personal calendars –\nclearly color-coded.", theme: .light),
        Motif(raw: "event", output: "02-plan-together", headline: "Plan it where\nit happens.",
              subline: "Who's coming and who brings snacks –\nright on the event.", theme: .dark),
        Motif(raw: "shopping", output: "03-shopping", headline: "Shop aisle\nby aisle.",
              subline: "Tiles with icons, sorted by aisle –\nup to date for everyone.", theme: .light),
        Motif(raw: "todos", output: "04-to-dos", headline: "Who does what?",
              subline: "To-dos with assignees and due dates.\nRepeating chores roll forward.", theme: .dark),
        Motif(raw: "screenshot", output: "05-screenshot", headline: "Screenshot in,\nevent out.",
              subline: "Share a school letter – yafo finds date,\ntime and place. On your device.", theme: .light),
        Motif(raw: "dark", output: "06-week", headline: "Tabs or swipe.",
              subline: "The week at a glance –\nin light and dark.", theme: .dark),
        Motif(raw: "family", output: "07-private", headline: "No account.\nNo ads.",
              subline: "Everything stays in your iCloud.\nInvite your family with a QR code.", theme: .light),
    ],
    duoOuter: duoOuter, duoInner: duoInner,
    claim: "One calendar.\nThe whole family.",
    facts: "Calendar, shopping list and to-dos for iPhone and iPad\nShared via iCloud · no account · no tracking",
    header: ("One calendar.", "The whole family."),
    search: ("FAMILY ORGANIZER", "Your family,\norganized.", "Together. Via iCloud. Private.")
)

// MARK: - Rendern

/// Ohne Alphakanal – App Store Connect lehnt Screenshots mit Transparenz ab.
@MainActor
func writePNG(_ view: some View, size: CGSize, to url: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(origin: .zero, size: size))
    let opaque = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: opaque)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func loadScreenshot(_ name: String, language: Language) -> NSImage? {
    let url = rawDirectory.appending(path: language.raw).appending(path: name + ".png")
    guard let image = NSImage(contentsOf: url) else {
        print("Fehlt: \(url.path)")
        return nil
    }
    // Pixelmaße statt Punkte: Rohaufnahmen haben 1 px = 1 pt.
    if let rep = image.representations.first {
        image.size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return image
}

MainActor.assumeIsolated {
    let icon = NSImage(contentsOfFile: "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    for language in [german, english] {
        let base = outputDirectory.appending(path: language.locale)
        if !onlyDuo, let icon, let front = loadScreenshot("iphone-month", language: language),
           let back = loadScreenshot("iphone-shopping", language: language) {
            let folder = base.appending(path: "Promo")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "yafo-banner-1920x1080.png")
            let banner = Banner(icon: icon, front: front, back: back, claim: language.claim, facts: language.facts)
            try? writePNG(banner, size: Banner.size, to: url)
            print(url.path)
        }

        if !onlyDuo, let calm = loadScreenshot("iphone-month", language: language),
           let vivid = loadScreenshot("iphone-shopping", language: language),
           let reader = loadScreenshot("iphone-event", language: language) {
            let folder = base.appending(path: "Creative")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let header = HeaderArt(left: calm, right: vivid, first: language.header.0, second: language.header.1)
            let search = SearchArt(front: calm, back: reader, kicker: language.search.kicker,
                                   headline: language.search.headline, subline: language.search.subline)
            for (view, size, name) in [(AnyView(header), HeaderArt.size, "header-3840x1646.png"),
                                       (AnyView(search), SearchArt.size, "search-3840x2560.png")] {
                let url = folder.appending(path: name)
                try? writePNG(view, size: size, to: url)
                print(url.path)
            }
        }

        let duo = [(Device.duoOuter, language.duoOuter), (.duoInner, language.duoInner)]
        let phoneAndPad = [(Device.iPhone, language.iPhone), (.iPhoneCompact, language.iPhone), (.iPad, language.iPad)]
        for (device, shots) in onlyDuo ? duo : phoneAndPad + duo {
            let folder = base.appending(path: device.folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for shot in shots {
                guard let screenshot = loadScreenshot(shot.raw, language: language) else { continue }
                let url = folder.appending(path: shot.output + ".png")
                do {
                    try writePNG(Poster(device: device, shot: shot, screenshot: screenshot), size: device.canvas, to: url)
                    print(url.path)
                } catch {
                    print("Fehler bei \(shot.output): \(error)")
                }
            }
        }
    }
}
