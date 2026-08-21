import Foundation
import SwiftData
import UIKit

/// Layer limits. Ink itself lives in `StrokeJournal`, not in SwiftData — this
/// is only the vocabulary shared by the model, the reading surface and the UI.
enum AnnotationLayers {
    /// Tentative cap. Ten is far past what anyone has asked for at a stand,
    /// which is the point: the ceiling should never be the thing you notice.
    static let max = 10
    static let first = 1

    // The shared margin belongs to the PART, not to any page: what you write
    // beside page 1 is still there beside page 5. It needs a slot in the
    // journal that no real page index can ever take.
    /// Value kept at -1 through the move from the left edge to the right, so
    /// anything already written in the margin travels with it.
    static let marginRightIndex = -1

    // -2 is retired. It was the bottom margin's journal slot, back when the
    // space under the score was a writable surface; it is scroll headroom now
    // and authors nothing. Never reuse the value: journals written before the
    // change still carry -2 records, and a new feature landing on that slot
    // would inherit somebody's old scribbles.

    static func isMargin(_ pageIndex: Int) -> Bool { pageIndex < 0 }
}

@Model
final class AnnotationLayer {
    var id: UUID = UUID()
    var pageIndex: Int = 0
    var drawingData: Data = Data()
    var pageWidth: Double = 0
    var pageHeight: Double = 0
    var schemaVersion: Int = 1
    var updatedAt: Date = Date()
    var deviceID: String = ""

    var part: Part?

    init(pageIndex: Int, part: Part) {
        self.pageIndex = pageIndex
        self.part = part
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
