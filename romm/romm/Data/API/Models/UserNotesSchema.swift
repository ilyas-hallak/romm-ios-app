import Foundation

public struct UserNotesSchema: Codable, JSONEncodable, Hashable {

    public var userId: Int
    public var username: String
    public var noteRawMarkdown: String

    public init(userId: Int, username: String, noteRawMarkdown: String) {
        self.userId = userId
        self.username = username
        self.noteRawMarkdown = noteRawMarkdown
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case userId = "user_id"
        case username
        case noteRawMarkdown = "note_raw_markdown"
        case content
    }

    // RomM 5.1 removed `note_raw_markdown`; the note body now lives in `content`.
    // Decode defensively so a missing/renamed field never fails the whole
    // ROM-detail decode (which otherwise cascades into download failures).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(Int.self, forKey: .userId)) ?? 0
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        noteRawMarkdown = ((try? c.decodeIfPresent(String.self, forKey: .noteRawMarkdown)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .content)) ?? nil)
            ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(username, forKey: .username)
        try container.encode(noteRawMarkdown, forKey: .noteRawMarkdown)
    }
}
