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

    // The shared margins belong to the PART, not to any page: what you write
    // beside page 1 is still there beside page 5. They need slots in the
    // journal that no real page index can ever take.
    static let marginLeftIndex = -1
    static let marginBottomIndex = -2

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
