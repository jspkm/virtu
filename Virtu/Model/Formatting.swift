import Foundation

extension String {
    /// Six call sites wrote `trimmingCharacters(in: .whitespaces)` by hand
    /// against typed-in text. Newlines count too — a title pasted out of a
    /// PDF arrives with one on the end, and an "empty" field that holds a
    /// newline is not empty to `isEmpty`.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Date {
    /// "3 minutes ago". Only the Recycle Bin says this now — how long a work
    /// has been waiting to be destroyed is the one place the answer matters.
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
