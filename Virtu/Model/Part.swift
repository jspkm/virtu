import Foundation
import SwiftData

@Model
final class Part {
    var id: UUID = UUID()
    var name: String = ""
    var pdfFileName: String = ""
    var pageCount: Int = 0
    /// Furthest page the musician has reached — drives the card progress line.
    var furthestPageIndex: Int = 0

    // MARK: - Annotation layers
    //
    // Every mark lands on a layer. Layer 1 exists from the start and is the
    // default, so a musician who never opens the layer control never has to
    // learn the concept. Hiding every layer shows the clean engraving — that
    // is the whole point of the feature.

    /// How many layers this part has (1...AnnotationLayers.max).
    var layerCount: Int = 1
    /// Which layer receives new ink. Erase, lasso and undo reach no further.
    var activeLayerIndex: Int = 1
    /// Layers the musician has switched off. Absence means visible, so an
    /// existing part migrates in with everything showing.
    var hiddenLayerIndices: [Int] = []

    func isLayerVisible(_ index: Int) -> Bool {
        !hiddenLayerIndices.contains(index)
    }

    /// Visible layers in composite order — layer 1 at the bottom.
    var visibleLayerIndices: [Int] {
        (1...max(layerCount, 1)).filter(isLayerVisible)
    }

    var work: Work?

    @Relationship(deleteRule: .cascade, inverse: \AnnotationLayer.part)
    var annotationLayers: [AnnotationLayer] = []

    var pdfURL: URL {
        Part.storageDirectory.appendingPathComponent(pdfFileName)
    }

    init(name: String, pdfFileName: String, pageCount: Int) {
        self.name = name
        self.pdfFileName = pdfFileName
        self.pageCount = pageCount
    }

    static let storageDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PDFs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
