//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreText
import UIKit

extension UIImage {

    // Function to overlay an image on top of the current image
    @objc func overlay(with overlayImage: UIImage, at overlayRect: CGRect) -> UIImage? {
        // Calculate the new size for the resulting image
        let newWidth = max(self.size.width, overlayRect.origin.x + overlayRect.size.width)
        let newHeight = max(self.size.height, overlayRect.origin.y + overlayRect.size.height)
        let newSize = CGSize(width: newWidth, height: newHeight)

        // Begin a new image context with the new size.
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)

        // Draw the base image in its original position.
        self.draw(in: CGRect(origin: CGPoint.zero, size: self.size))

        // Draw the overlay image in the specified rectangle.
        overlayImage.draw(in: overlayRect)

        // Capture the new image from the context.
        let newImage = UIGraphicsGetImageFromCurrentImageContext()

        // End the image context to free up memory.
        UIGraphicsEndImageContext()

        return newImage
    }

    // Function to crop an image into a circle with the specified size.
    @objc func cropToCircle(withSize size: CGSize) -> UIImage? {
        // Begin a new image context with the target size
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)

        // Create a circular path using a rounded rectangle
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size.width / 2)
        path.addClip()

        // Draw the image in the context, scaled to fill the entire circular area
        self.draw(in: rect)

        // Capture the new image
        let circleImage = UIGraphicsGetImageFromCurrentImageContext()

        // End the image context to free up memory
        UIGraphicsEndImageContext()

        return circleImage
    }

    // Function to add a circular background with specified background color, diameter and padding
    @objc func withCircularBackground(backgroundColor: UIColor, diameter: CGFloat, padding: CGFloat) -> UIImage? {
        // Begin a new image context with the target diameter as both width and height
        UIGraphicsBeginImageContextWithOptions(CGSize(width: diameter, height: diameter), false, 0.0)

        // Define the circle's path using the diameter
        let circlePath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))

        // Set the fill color and fill the circle
        backgroundColor.setFill()
        circlePath.fill()

        // Calculate the frame for the image inside the circle
        let imageSize = CGSize(width: diameter - 2 * padding, height: diameter - 2 * padding)
        let imageRect = CGRect(
            x: (diameter - imageSize.width) / 2,
            y: (diameter - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        // Draw the image inside the calculated frame
        self.draw(in: imageRect)

        // Capture the final image
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()

        // End the image context to free up memory
        UIGraphicsEndImageContext()

        return resultImage
    }

    /// Draws a short text in a box, like the SD and HD badges of a video player.
    ///
    /// Sized from the font of the label the badge is shown next to, so both scale together, and
    /// returned as a template image, so it takes the color of whatever shows it.
    ///
    /// - Parameter text: A word or an abbreviation. Anything longer only gets a wider box.
    /// - Parameter font: The font of the label next to the badge.
    static func badge(withText text: String, matching font: UIFont) -> UIImage {
        let textFont = UIFont.systemFont(ofSize: font.pointSize * 0.7, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: UIColor.black]

        // The advance width of the text includes the side bearings of its letters, which are not
        // the same on both sides and would put the letters off centre. The bounds of the glyphs
        // themselves are what has to be padded and centred instead.
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        let borderWidth = max(1, (font.pointSize / 12).rounded())
        // Enough room for the letters to not look cramped in their box, and it makes the badge as
        // tall as the images of a menu row, which shows it without having to scale it
        let padding = (font.pointSize / 3).rounded()

        // The width follows the glyphs, the height the cap height of the font instead of the height
        // of its line, which would add the room that ascenders and descenders need. Capitals use
        // neither, so that room would only show up as more padding above and below them.
        let size = CGSize(width: (ink.width + padding * 2).rounded(.up),
                          height: (textFont.capHeight + padding * 2).rounded(.up))

        // Where the text has to be drawn for the glyphs to end up centred, which also spreads
        // whatever the rounding of the size added evenly to both sides. Vertically the capitals are
        // what gets centred, so every badge of the same font is equally tall.
        let capTop = (size.height - textFont.capHeight) / 2
        let origin = CGPoint(x: (size.width - ink.width) / 2 - ink.minX,
                            y: capTop + textFont.capHeight - textFont.ascender)

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let box = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                                   cornerRadius: size.height * 0.25)
            box.lineWidth = borderWidth
            UIColor.black.setStroke()
            box.stroke()

            (text as NSString).draw(at: origin, withAttributes: attributes)
        }

        // Drawn in black, so the template can be tinted to any color
        return image.withRenderingMode(.alwaysTemplate)
    }

    // Function to create a UIImage from a UILabel
    @objc static func image(from label: UILabel) -> UIImage? {
        // Begin a new image context with the size of the label
        UIGraphicsBeginImageContextWithOptions(label.bounds.size, false, 0.0)

        // Render the label layer into the current context
        label.layer.render(in: UIGraphicsGetCurrentContext()!)

        // Capture the image from the context
        let image = UIGraphicsGetImageFromCurrentImageContext()

        // End the image context to free up memory
        UIGraphicsEndImageContext()

        return image
    }
}
