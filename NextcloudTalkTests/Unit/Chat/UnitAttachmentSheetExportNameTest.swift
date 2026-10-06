//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitAttachmentSheetExportNameTest: XCTestCase {

    func testOriginalNameAndExtensionAreKept() throws {
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0042.HEIC", resourceFileName: "IMG_0042.HEIC", uniformTypeIdentifier: "public.heic", isVideo: false),
                       "IMG_0042.HEIC")
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0043.GIF", resourceFileName: "IMG_0043.GIF", uniformTypeIdentifier: "com.compuserve.gif", isVideo: false),
                       "IMG_0043.GIF")
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0044.MOV", resourceFileName: "IMG_0044.MOV", uniformTypeIdentifier: "com.apple.quicktime-movie", isVideo: true),
                       "IMG_0044.MOV")
    }

    func testEditedPhotoKeepsNameButTakesTypeOfEditedData() throws {
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0042.HEIC", resourceFileName: "FullSizeRender.jpeg", uniformTypeIdentifier: "public.jpeg", isVideo: false),
                       "IMG_0042.jpeg")
    }

    func testExtensionFromTypeWhenResourceHasNone() throws {
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0045", resourceFileName: "IMG_0045", uniformTypeIdentifier: "public.png", isVideo: false),
                       "IMG_0045.png")
    }

    func testFallbacksWithoutAnyInformation() throws {
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "IMG_0046", resourceFileName: "IMG_0046", uniformTypeIdentifier: nil, isVideo: false), "IMG_0046.jpg")
        XCTAssertEqual(AttachmentAssetExporter.exportFileName(originalFileName: "VID_0001", resourceFileName: "VID_0001", uniformTypeIdentifier: nil, isVideo: true), "VID_0001.mov")
        XCTAssertTrue(AttachmentAssetExporter.exportFileName(originalFileName: "", resourceFileName: "", uniformTypeIdentifier: nil, isVideo: true).hasPrefix("VID_"))
    }

    func testOnlyHeicAndHeifAreConvertedToJPEG() throws {
        XCTAssertTrue(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "public.heic"))
        XCTAssertTrue(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "public.heif"))
        XCTAssertFalse(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "public.jpeg"))
        XCTAssertFalse(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "public.png"))
        XCTAssertFalse(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "com.compuserve.gif"))
        XCTAssertFalse(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: "com.apple.quicktime-movie"))
        XCTAssertFalse(AttachmentAssetExporter.needsJPEGConversion(uniformTypeIdentifier: nil))
    }

    func testJPEGFileName() throws {
        XCTAssertEqual(AttachmentAssetExporter.jpegFileName(for: "IMG_0042.HEIC"), "IMG_0042.jpg")
    }
}
