import CoreGraphics
import Foundation
import FoundationModels
import Vision
import YafoKit

/// Findet Termine in einem Bild, alles auf dem Gerät (kein Private Cloud Compute):
/// 1. Modell mit Bildverständnis: das Bild direkt an Foundation Models.
/// 2. Sonst Texterkennung mit Vision, dann der Text ans Modell.
/// 3. Ohne Apple Intelligence: Datumserkennung per `NSDataDetector` (`TextEventExtractor`).
/// Wird auch von der Share Extension benutzt.
enum ScreenshotReader {
    enum Method: Equatable {
        case imageModel, textModel, dataDetector
    }

    struct Result {
        var proposals: [EventProposal]
        var method: Method
    }

    static func read(_ image: CGImage, now: Date = .now) async -> Result {
        let model = SystemLanguageModel.default
        if model.isAvailable, model.capabilities.contains(.vision),
           let proposals = try? await askModel(now: now, content: .image(image)), !proposals.isEmpty {
            return Result(proposals: proposals, method: .imageModel)
        }
        let lines = (try? await recognizeText(in: image)) ?? []
        if model.isAvailable, !lines.isEmpty,
           let proposals = try? await askModel(now: now, content: .text(lines)), !proposals.isEmpty {
            return Result(proposals: proposals, method: .textModel)
        }
        return Result(proposals: TextEventExtractor.proposals(in: lines, now: now), method: .dataDetector)
    }

    // MARK: - Foundation Models

    private enum Content {
        case image(CGImage)
        case text([String])
    }

    private static func askModel(now: Date, content: Content) async throws -> [EventProposal] {
        let today = now.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "en_US")))
        let isoToday = now.formatted(.iso8601.year().month().day())
        let session = LanguageModelSession(instructions: """
            You find appointments and events in screenshots of messages, emails, letters, posters and web pages \
            and turn them into calendar entries. Today is \(today) (\(isoToday)). \
            Resolve relative dates such as "tomorrow", "next Friday", "morgen" or "nächsten Samstag" and dates \
            without a year to the next matching date on or after today. \
            Ignore the clock in the status bar, times a message was sent and dates that are only mentioned in passing. \
            Keep the title short and in the language of the text, without the date. \
            If the text says an event repeats ("jeden Dienstag", "montags", "alle zwei Wochen", "every Monday", \
            "weekly"), return it once as a recurring event: date is the first occurrence on or after today \
            (or the stated start date), with repeats and weekdays set. Never invent events.
            """)
        let response = try await session.respond(generating: RecognizedEvents.self) {
            switch content {
            case .image(let image):
                "Find all events in this screenshot."
                Attachment(image)
            case .text(let lines):
                "Find all events in this text, recognized from a screenshot line by line:"
                lines.joined(separator: "\n")
            }
        }
        return response.content.events.compactMap { event in
            EventProposal(title: event.title, date: event.date, startTime: event.startTime,
                          endDate: event.endDate, endTime: event.endTime, location: event.location,
                          repeats: event.repeats?.rawValue, repeatWeekdays: event.repeatWeekdays ?? [],
                          repeatUntil: event.repeatUntil)
        }
    }

    // MARK: - Vision

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

@Generable
struct RecognizedEvents {
    @Guide(description: "Every appointment or event in the content, in order of appearance. Empty if there is none.")
    var events: [RecognizedEvent]
}

@Generable
struct RecognizedEvent {
    @Guide(description: "Short calendar title, e.g. \"Elternabend\" or \"Dentist\"")
    var title: String
    @Guide(description: "Start date in the format yyyy-MM-dd")
    var date: String
    @Guide(description: "Start time in 24-hour format HH:mm; nil for all-day events")
    var startTime: String?
    @Guide(description: "Last day in the format yyyy-MM-dd if the event spans several days, otherwise nil")
    var endDate: String?
    @Guide(description: "End time in 24-hour format HH:mm if given, otherwise nil")
    var endTime: String?
    @Guide(description: "Place or address if given, otherwise nil")
    var location: String?
    @Guide(description: "How often the event repeats if the text says so, otherwise nil")
    var repeats: RecognizedRepeat?
    @Guide(description: "For weekly repeats: the weekdays as two-letter codes MO, TU, WE, TH, FR, SA, SU")
    var repeatWeekdays: [String]?
    @Guide(description: "Last date of a repeating event in the format yyyy-MM-dd if given, otherwise nil")
    var repeatUntil: String?
}

@Generable
enum RecognizedRepeat: String {
    case daily, weekly, biweekly, monthly, yearly
}
