import Foundation
import SwiftData
import UIKit

/// Layer limits. Ink itself lives in `StrokeJournal`, not in SwiftData — this
/// is only the vocabulary shared by the model, the reading surface and the UI.
enum AnnotationLayers {
    /// Three, always, for every part — decided 2026-08-22. Ten was headroom
    /// nobody asked for, and it pushed the rail past an iPad mini's height.
    /// Three exist from the start; there is no adding and no removing.
    static let max = 3
    static let first = 1

    /// What `max` was from 2026-08-20 to 2026-08-22. Ink written on layers
    /// 4–10 under those builds is still on disk; nothing may pretend it is
    /// not there. `configure` folds it into the top layer, and a destroyed
    /// work takes it to the bin with everything else.
    static let legacyMax = 10

    // The Right Page belongs to a SPREAD — not to the part, and not to a
    // single score page.
    //
    // Landscape shows pages 1 and 2 side by side; portrait shows the same two
    // one at a time. Both have to reach the same sheet, or a note written
    // beside page 2 in portrait would vanish when the iPad is turned. So the
    // key is the spread: Right Page 1 beside score pages 1 and 2, Right Page 2
    // beside 3 and 4. `AppState.goToPage` parity-locks landscape to even page
    // indices, so halving lands on the same spread from either orientation.
    // Swift.max, because `max` alone resolves to the layer cap above.
    static func spread(forPage pageIndex: Int) -> Int { Swift.max(0, pageIndex) / 2 }

    /// Journal slot for a spread's Right Page. Negative, so it can never
    /// collide with a real page index, and starting at -10 so it clears the
    /// two retired slots below.
    static func rightPageIndex(spread: Int) -> Int { -10 - spread }

    /// Every Right Page slot a part can own, for bulk work like deletion.
    static func rightPageIndices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        return (0...spread(forPage: pageCount - 1)).map { rightPageIndex(spread: $0) }
    }

    // -1 and -2 are retired, and neither value may ever be reused: journals
    // written before these changes still carry records at both, so a new
    // feature landing on either slot would inherit somebody's old marks.
    //   -1  the part-wide shared margin, from when one sheet served the whole
    //       part rather than one sheet per spread.
    //   -2  the bottom margin, from when the space under the score was a
    //       writable surface instead of scroll headroom.
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
