import Foundation
import FoundationModels
import UIKit
import Vision
import YafoKit

/// Findet Termine auf einem Screenshot, komplett auf dem Gerät. Private Cloud Compute wird
/// bewusst nicht genutzt, das Bild verlässt das Gerät nicht.
///
/// 1. Mit Apple Intelligence: Bild direkt an das On-Device-Modell, Ausgabe per `@Generable`.
/// 2. Kann das Modell kein Bild annehmen: Texterkennung mit Vision, dann der Text ans Modell.
/// 3. Ohne Modell: Texterkennung und `NSDataDetector`.
enum ScreenshotAnalyzer {
    enum Method: Sendable {
        case imageModel, textModel, dataDetector
    }

    struct Result {
        var suggestions: [EventSuggestion]
        var method: Method
    }

    static func analyze(_ image: UIImage, now: Date = .now) async -> Result {
        let modelAvailable = SystemLanguageModel.default.isAvailable
        if modelAvailable, let suggestions = try? await fromImage(image, now: now), !suggestions.isEmpty {
            return Result(suggestions: suggestions, method: .imageModel)
        }
        let text = (try? await recognizeText(in: image)) ?? ""
        if modelAvailable, !text.isEmpty, let suggestions = try? await fromText(text, now: now), !suggestions.isEmpty {
            return Result(suggestions: suggestions, method: .textModel)
        }
        return Result(suggestions: EventSuggestionDetector.suggestions(in: text, now: now),
                      method: modelAvailable ? .textModel : .dataDetector)
    }

    // MARK: - Sprachmodell

    private static func fromImage(_ image: UIImage, now: Date) async throws -> [EventSuggestion] {
        let session = LanguageModelSession(instructions: instructions(now: now))
        let response = try await session.respond(generating: GeneratedEvents.self) {
            "Find all events, appointments and deadlines in this screenshot."
            Attachment(image)
        }
        return suggestions(from: response.content)
    }

    private static func fromText(_ text: String, now: Date) async throws -> [EventSuggestion] {
        let session = LanguageModelSession(instructions: instructions(now: now))
        let prompt = "Find all events, appointments and deadlines in this text from a screenshot:\n\n\(text)"
        let response = try await session.respond(to: prompt, generating: GeneratedEvents.self)
        return suggestions(from: response.content)
    }

    private static func instructions(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm"
        return """
        You extract calendar events from screenshots of chats, emails, letters, flyers and websites.
        Now is \(formatter.string(from: now)) in the time zone \(TimeZone.current.identifier).
        Resolve relative dates such as "tomorrow", "next Friday" or "on the 14th" against now.
        If the year is missing, use the next date that is not in the past.
        Only include events that are actually stated. Never invent a time; leave it out instead.
        Keep titles short and in the language of the screenshot, without the date or time.
        """
    }

    private static func suggestions(from generated: GeneratedEvents) -> [EventSuggestion] {
        var seen = Set<String>()
        return generated.events.prefix(10).compactMap { event in
            EventSuggestion.fromModel(title: event.title, start: event.start, end: event.end,
                                      isAllDay: event.isAllDay, location: event.location)
        }
        .filter { seen.insert("\($0.title)|\($0.start.timeIntervalSince1970)").inserted }
    }

    // MARK: - Texterkennung

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: cgImage)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

// MARK: - Ausgabeformat des Modells

/// Daten als Text, weil das Modell so verlässlicher antwortet; `EventSuggestion.fromModel` liest sie.
@Generable
nonisolated struct GeneratedEvents {
    @Guide(description: "Every event, appointment or deadline in the input. Empty if there is none.")
    var events: [GeneratedEvent]
}

@Generable
nonisolated struct GeneratedEvent {
    @Guide(description: "Short title without date or time, in the language of the input")
    var title: String
    @Guide(description: "Start in local time as yyyy-MM-dd'T'HH:mm, or yyyy-MM-dd if no time of day is given")
    var start: String
    @Guide(description: "End in the same format, or an empty string if no end is given")
    var end: String
    @Guide(description: "True if the event has no time of day, e.g. holidays or deadlines")
    var isAllDay: Bool
    @Guide(description: "Place or address, or an empty string")
    var location: String
}
