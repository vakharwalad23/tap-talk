import Foundation

struct DictionaryEntry: Codable, Identifiable {
    var id: UUID
    var from: String
    var to: String

    init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

struct DictionarySegment: Codable, Identifiable {
    var id: String { name }
    var name: String
    var isEnabled: Bool
    var entries: [DictionaryEntry]
}
