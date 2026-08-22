import Foundation
import SwiftData

@Model
final class Work {
    var id: UUID = UUID()
    var composer: String = ""
    var title: String = ""
    var catalogueNumber: String = ""
    var edition: String = ""
    var year: Int?
    var createdAt: Date = Date()
    var lastOpenedAt: Date = Date()
    /// Soft delete: a binned work sits in the Recycle Bin under Tools until
    /// the musician empties it. Nothing on disk is touched until then.
    var deletedAt: Date?
    /// Autofilled at import (about 3 minutes a page), editable ever after.
    /// Programme entries start from it instead of a flat guess.
    var estimatedMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: \Part.work)
    var parts: [Part] = []

    init(composer: String, title: String, catalogueNumber: String = "", edition: String = "") {
        self.composer = composer
        self.title = title
        self.catalogueNumber = catalogueNumber
        self.edition = edition
    }

    /// "Cello Suite no. 1 in G major" → "Cello Suite no. 1", for tight layouts
    /// like programme cards.
    var shortTitle: String {
        title.components(separatedBy: " in ").first ?? title
    }
}
