import Foundation

// MARK: - Where the app talks to the outside world

/// The control cards come from the ORC points system at ``ApiConfig/baseURL``.
/// It issues the QR codes the crews scan and scores the cards they finalize, so
/// moving the app to another host is a one-line change here.
///
/// The system replaces the old Umbraco backend
/// (`/umbraco/surface/controlekaart/...`); the Dutch field names of the two
/// payloads are what is left of it.
enum ApiConfig {

    /// Host of the ORC points system that issues and collects the cards.
    static let baseURL = "https://tel.sarkonline.com"

    /// Look up the card behind a scanned (or typed) code.
    ///
    /// Answers with the rally code, the equipe number and the card number the
    /// app has to send back when the card is finalized.
    static func card(code: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/app/card")
        components?.queryItems = [
            URLQueryItem(name: "code", value: normalize(code))
        ]
        return components?.url
    }

    /// Hand a finalized control card in to be scored.
    static var submitCard: URL? {
        URL(string: "\(baseURL)/api/app/submit")
    }

    /// The alphabet the codes are minted from has no `I`, `L`, `O`, `U`, `0` or
    /// `1`, precisely so a crew can retype the eight characters printed under
    /// the QR. Upper-casing and trimming here is what makes that typing work.
    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

// MARK: - The card behind a code

/// The answer of `GET /api/app/card`.
///
/// Three of these fields have to survive the round trip, because they are all
/// that identifies the card when it is handed in: the rally's `rallycode`, the
/// stage's `kaartid` and the crew's `equipenr`. `kaartnr` is the card's place in
/// the running order and moves when a stage is deleted, so it is shown but never
/// used to resolve the card.
struct CardLookup {
    let rallyCode: String
    let eqNumber: Int
    let eqId: Int
    let cardId: Int
    let cardNumber: Int

    /// Context the card page sends along so a list of cards reads as something
    /// other than a row of numbers.
    let rallyName: String
    let cardName: String
    let crewName: String
    let classification: String

    /// Whether this card has already been handed in on this code. A second
    /// submission is refused until an official reopens it from the QR page.
    let alreadySubmitted: Bool
}

extension CardLookup: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rallyCode      = "rallycode"
        case eqNumber       = "equipenr"
        case eqId           = "equipeid"
        case cardId         = "kaartid"
        case cardNumber     = "kaartnr"
        case rallyName      = "rallynaam"
        case cardName       = "kaartnaam"
        case crewName       = "equipenaam"
        case classification = "klasse"
        case submitted      = "ingeleverd"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let eq   = try container.decode(Int.self, forKey: .eqNumber)
        let card = try container.decode(Int.self, forKey: .cardId)

        rallyCode  = try container.decode(String.self, forKey: .rallyCode)
        eqNumber   = eq
        cardId     = card
        // `equipeid` and `kaartnr` are carried for the old payload's sake; fall
        // back to the identifiers that do the work rather than failing on them.
        eqId       = try container.decodeIfPresent(Int.self, forKey: .eqId) ?? eq
        cardNumber = try container.decodeIfPresent(Int.self, forKey: .cardNumber) ?? card

        rallyName      = try container.decodeIfPresent(String.self, forKey: .rallyName) ?? ""
        cardName       = try container.decodeIfPresent(String.self, forKey: .cardName) ?? ""
        crewName       = try container.decodeIfPresent(String.self, forKey: .crewName) ?? ""
        classification = try container.decodeIfPresent(String.self, forKey: .classification) ?? ""

        alreadySubmitted = try container.decodeIfPresent(Bool.self, forKey: .submitted) ?? false
    }
}

// MARK: - A finalized card

/// The body of `POST /api/app/submit`.
///
/// Nothing about the scoring comes from the phone: the app sends the letters of
/// the 30 ORC rows and the 6 merk rows, and the server grades them.
struct CardSubmission: Encodable {

    struct Row: Encodable {
        let id: Int
        let col1: String
        let col2: String
        let col3: String
        let col4: String
    }

    let rallyCode: String
    let cardId: Int
    let cardNumber: Int
    let eqNumber: Int
    let eqId: Int
    let rows: [Row]
}

// MARK: - Errors

/// What the two public endpoints answer with when they refuse a request. The
/// bodies are generic on purpose — an unknown code is a 404 whether it is
/// malformed or simply wrong — so the app maps the status to something a crew
/// standing next to their car can act on.
enum ORCPointsError: LocalizedError {
    case unknownCode
    case alreadySubmitted
    case rateLimited
    case badRequest(String?)
    case server(status: Int, message: String?)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unknownCode:
            return "This code is not known. Check the eight characters under the QR code, or scan it again."
        case .alreadySubmitted:
            return "This control card has already been handed in. An official has to reopen it before it can be sent again."
        case .rateLimited:
            return "Too many attempts. Wait a minute and try again."
        case .badRequest(let message):
            return message ?? "The control card was refused by the server."
        case .server(let status, let message):
            if let message, !message.isEmpty {
                return "\(message) (status \(status))"
            }
            return "The server could not be reached (status \(status))."
        case .malformedResponse:
            return "Unreadable answer from the server."
        }
    }
}

// MARK: - Client

enum ORCPointsAPI {

    /// Look the scanned or typed code up and answer with the card behind it.
    static func fetchCard(code: String, completion: @escaping (Result<CardLookup, Error>) -> Void) {
        guard let url = ApiConfig.card(code: code) else {
            complete(completion, with: .failure(ORCPointsError.unknownCode))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let refusal = refusal(data: data, response: response, error: error) {
                complete(completion, with: .failure(refusal))
                return
            }

            guard let data, let card = try? JSONDecoder().decode(CardLookup.self, from: data),
                  !card.rallyCode.isEmpty else {
                complete(completion, with: .failure(ORCPointsError.malformedResponse))
                return
            }

            complete(completion, with: .success(card))
        }.resume()
    }

    /// Hand a finalized card in to be scored.
    static func submit(_ submission: CardSubmission, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = ApiConfig.submitCard else {
            complete(completion, with: .failure(ORCPointsError.malformedResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(submission)
        } catch {
            complete(completion, with: .failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let refusal = refusal(data: data, response: response, error: error) {
                complete(completion, with: .failure(refusal))
                return
            }
            complete(completion, with: .success(()))
        }.resume()
    }

    // MARK: - Shared plumbing

    /// Turns anything that is not a 2xx into an error worth showing. Returns
    /// `nil` when the request succeeded.
    private static func refusal(data: Data?, response: URLResponse?, error: Error?) -> Error? {
        if let error { return error }

        guard let http = response as? HTTPURLResponse else {
            return ORCPointsError.malformedResponse
        }

        if (200..<300).contains(http.statusCode) { return nil }

        let message = serverMessage(from: data)

        switch http.statusCode {
        case 404: return ORCPointsError.unknownCode
        case 409: return ORCPointsError.alreadySubmitted
        case 429: return ORCPointsError.rateLimited
        case 400: return ORCPointsError.badRequest(message)
        default:  return ORCPointsError.server(status: http.statusCode, message: message)
        }
    }

    /// Every refusal answers with `{"error": "..."}`.
    private static func serverMessage(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["error"] as? String,
              !message.isEmpty
        else { return nil }
        return message
    }

    private static func complete<T>(_ completion: @escaping (Result<T, Error>) -> Void,
                                    with result: Result<T, Error>) {
        DispatchQueue.main.async { completion(result) }
    }
}
