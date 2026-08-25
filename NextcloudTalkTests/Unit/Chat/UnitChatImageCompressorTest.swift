//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import ImageIO
import UIKit
import XCTest
@testable import NextcloudTalk

final class UnitChatImageCompressorTest: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        self.directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    // MARK: - Supported types

    func testImagesSupportCompression() throws {
        XCTAssertTrue(ChatImageCompressor.supportsCompression(fileName: "IMG_1.jpg"))
        XCTAssertTrue(ChatImageCompressor.supportsCompression(fileName: "IMG_1.JPEG"))
        XCTAssertTrue(ChatImageCompressor.supportsCompression(fileName: "screenshot.png"))
        XCTAssertTrue(ChatImageCompressor.supportsCompression(fileName: "IMG_1.heic"))
    }

    func testAnimationsAndVectorsDoNotSupportCompression() throws {
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "party.gif"))
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "logo.svg"))
    }

    func testOtherFilesDoNotSupportCompression() throws {
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "invoice.pdf"))
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "Contact_1.vcf"))
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "VID_1.mov"))
        XCTAssertFalse(ChatImageCompressor.supportsCompression(fileName: "IMG_1"))
    }

    // MARK: - Compression

    func testLargeImageIsDownscaledAndReencoded() throws {
        let original = try self.writeImage(width: 3000, height: 2000, named: "IMG_1.png")

        let compressed = try XCTUnwrap(ChatImageCompressor.compressedCopy(of: original, named: "IMG_1.png", in: self.directory))

        XCTAssertEqual(compressed.fileName, "IMG_1.jpg")

        let size = try self.pixelSize(of: compressed.url)
        XCTAssertEqual(max(size.width, size.height), ChatImageCompressor.maxPixelSize)
        // The aspect ratio of 3:2 has to survive the downscaling
        XCTAssertEqual(Double(size.width) / Double(size.height), 1.5, accuracy: 0.01)

        XCTAssertLessThan(try self.fileSize(of: compressed.url), try self.fileSize(of: original))

        // The original has to stay untouched, so a failed upload can be retried with it
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testAlreadyLightJpegKeepsTheOriginal() throws {
        // Nothing is gained by re-encoding a file that was encoded with a lower quality already
        let original = try self.writeImage(width: 640, height: 480, named: "IMG_1.jpg", jpegQuality: 0.3)

        XCTAssertNil(ChatImageCompressor.compressedCopy(of: original, named: "IMG_1.jpg", in: self.directory))
    }

    func testSmallButHeavyJpegIsCompressed() throws {
        // An image can be heavy without being large, so its size is not left alone just because
        // it does not have to be downscaled
        let original = try self.writeImage(width: 1000, height: 750, named: "IMG_1.jpg", jpegQuality: 1)

        let compressed = try XCTUnwrap(ChatImageCompressor.compressedCopy(of: original, named: "IMG_1.jpg", in: self.directory))

        XCTAssertLessThan(try self.fileSize(of: compressed.url), try self.fileSize(of: original))

        // It fits already, so it keeps its dimensions
        let size = try self.pixelSize(of: compressed.url)
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 750)
    }

    func testSmallPngIsStillReencoded() throws {
        // A small PNG is not downscaled, but JPEG still saves a lot of its size
        let original = try self.writeImage(width: 640, height: 480, named: "IMG_1.png")

        let compressed = try XCTUnwrap(ChatImageCompressor.compressedCopy(of: original, named: "IMG_1.png", in: self.directory))

        XCTAssertEqual(compressed.fileName, "IMG_1.jpg")

        let size = try self.pixelSize(of: compressed.url)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 480)
    }

    func testNonImageIsNotCompressed() throws {
        let fileURL = self.directory.appendingPathComponent("invoice.pdf")
        try Data("Not an image at all".utf8).write(to: fileURL)

        XCTAssertNil(ChatImageCompressor.compressedCopy(of: fileURL, named: "invoice.pdf", in: self.directory))
    }

    // MARK: - Utils

    /// Writes a photo-like image: smooth enough for a lossy encoder to win, but not a flat colour
    /// that would compress into almost nothing and make the size comparisons meaningless.
    private func writeImage(width: Int, height: Int, named fileName: String, jpegQuality: CGFloat? = nil) throws -> URL {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        let image = renderer.image { context in
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1])!

            context.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: width, y: height),
                                                 options: [])

            for index in 0..<12 {
                UIColor(white: CGFloat(index) / 12, alpha: 0.4).setFill()
                let side = CGFloat(width) / CGFloat(index + 2)
                context.cgContext.fillEllipse(in: CGRect(x: CGFloat(index) * side / 2, y: CGFloat(index) * side / 3, width: side, height: side))
            }
        }

        let data = try XCTUnwrap(jpegQuality.map { image.jpegData(compressionQuality: $0) } ?? image.pngData())
        let fileURL = self.directory.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        return fileURL
    }

    private func pixelSize(of fileURL: URL) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fileURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        return (try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private func fileSize(of fileURL: URL) throws -> Int {
        return try XCTUnwrap(FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int)
    }
}
