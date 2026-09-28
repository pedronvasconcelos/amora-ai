import Foundation

struct ActivityEvent: Decodable {
    enum Source: String, Decodable {
        case cursor
        case claude
    }

    enum Activity: String, Decodable {
        case thinking
        case working
        case waiting
        case finished
    }

    let v: Int
    let source: Source
    let activity: Activity

    static func decode(_ data: Data) -> ActivityEvent? {
        guard let event = try? JSONDecoder().decode(Self.self, from: data), event.v == 1 else {
            return nil
        }
        return event
    }
}
