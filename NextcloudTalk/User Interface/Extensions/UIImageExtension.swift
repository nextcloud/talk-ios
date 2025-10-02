//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

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
