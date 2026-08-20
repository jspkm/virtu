import Foundation
import SwiftData

/// A concert program (musicians say "program", not "setlist"): an ordered list
/// of works, optionally with a date and venue. Dated sets are performances and
/// surface in the Next Performance panel; undated sets are simply collections
/// ("warm-ups", "audition excerpts"). Programs reference works — they never
/// copy them. On gig day the program is the reading surface: page turns flow
/// across pieces without a trip back to the library.
@Model
final class Program {
    var id: UUID = UUID()
    var name: String = ""
    var venue: String = ""
    var date: Date?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProgramItem.program)
    var items: [ProgramItem] = []

    var sortedItems: [ProgramItem] {
        items.sorted { $0.index < $1.index }
    }

    var totalMinutes: Int {
        items.reduce(0) { $0 + $1.durationMinutes }
    }

    init(name: String, venue: String = "", date: Date? = nil) {
        self.name = name
        self.venue = venue
        self.date = date
    }
}

@Model
final class ProgramItem {
    var id: UUID = UUID()
    var index: Int = 0
    var durationMinutes: Int = 0

    var work: Work?
    var program: Program?

    init(index: Int, durationMinutes: Int, work: Work?) {
        self.index = index
        self.durationMinutes = durationMinutes
        self.work = work
    }
}

extension Int {
    /// 0 → "I", 1 → "II" … movement/programme numbering.
    var romanNumeral: String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return self >= 0 && self < numerals.count ? numerals[self] : "\(self + 1)"
    }
}
