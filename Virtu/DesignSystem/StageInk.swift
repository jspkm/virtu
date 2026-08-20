import UIKit
import CoreImage

extension UIImage {
    /// Stage-mode luminance remap: invert, then pull toward the warm palette
    /// so paper reads #0A0908 and notation reads #EDE7DC. Shared by the page
    /// renderer and the scrubber thumbnails.
    func stageRemapped() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let input = CIImage(cgImage: cg)

        let inverted = input.applyingFilter("CIColorInvert")
        let remapped = inverted.applyingFilter("CIColorPolynomial", parameters: [
            "inputRedCoefficients": CIVector(x: 0.039, y: 0.890, z: 0, w: 0),
            "inputGreenCoefficients": CIVector(x: 0.035, y: 0.871, z: 0, w: 0),
            "inputBlueCoefficients": CIVector(x: 0.031, y: 0.832, z: 0, w: 0),
        ])

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = context.createCGImage(remapped, from: remapped.extent) else { return nil }
        return UIImage(cgImage: output, scale: scale, orientation: .up)
    }
}
