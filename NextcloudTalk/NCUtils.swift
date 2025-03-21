//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CommonCrypto
import MobileCoreServices
import UniformTypeIdentifiers
import AVFoundation

@objcMembers public class NCUtils: NSObject {

    private static let nextcloudScheme = "nextcloud:"

    public static func previewImage(forFileExtension fileExtension: String) -> String {
        return previewImage(forFileType: UTType(filenameExtension: fileExtension))
    }

    public static func previewImage(forMimeType mimeType: String?) -> String {
        guard let mimeType else { return "file" }

        return self.previewImage(forFileType: UTType(mimeType: mimeType))
    }

    // swiftlint:disable:next cyclomatic_complexity
    public static func previewImage(forFileType fileType: UTType?) -> String {
        guard let fileType else { return "file" }

        if let mimeType = fileType.preferredMIMEType {
            if mimeType.contains("org.openxmlformats") || mimeType.contains("org.oasis-open.opendocument") ||
                mimeType.contains("officedocument.wordprocessingml") {

                return "file-document"
            } else if mimeType == "httpd/unix-directory" {
                return "folder"
            }
        }

        if !fileType.isDeclared {
            return "file"
        }

        if fileType.conforms(to: .audio) {
            return "file-audio"
        } else if fileType.conforms(to: .movie) {
            return "file-video"
        } else if fileType.conforms(to: .image) {
            return "file-image"
        } else if fileType.conforms(to: .spreadsheet) {
            return "file-spreadsheet"
        } else if fileType.conforms(to: .presentation) {
            return "file-presentation"
        } else if fileType.conforms(to: .pdf) {
            return "file-pdf"
        } else if fileType.conforms(to: .vCard) {
            return "file-vcard"
        } else if fileType.conforms(to: .text) {
            return "file-text"
        } else if fileType.conforms(to: .zip) {
            return "file-zip"
        }

        return "file"
    }

    public static func isImage(fileType: String) -> Bool {
        return self.previewImage(forMimeType: fileType) == "file-image"
    }

    public static func isImage(fileExtension: String) -> Bool {
        return self.previewImage(forFileExtension: fileExtension) == "file-image"
    }

    public static func isVideo(fileType: String) -> Bool {
        return self.previewImage(forMimeType: fileType) == "file-video"
    }

    public static func isAudio(fileType: String) -> Bool {
        return self.previewImage(forMimeType: fileType) == "file-audio"
    }

    public static func isVCard(fileType: String) -> Bool {
        return self.previewImage(forMimeType: fileType) == "file-vcard"
    }

    public static func isGif(fileType: String) -> Bool {
        return UTType(mimeType: fileType)?.conforms(to: .gif) ?? false
    }

    public static func isNextcloudAppInstalled() -> Bool {
        var isInstalled = false

#if !APP_EXTENSION
        if let URL = URL(string: nextcloudScheme) {
            isInstalled = UIApplication.shared.canOpenURL(URL)
        }
#endif
        return isInstalled
    }

    public static func openFileInNextcloudApp(path: String, withFileLink link: String) {
#if !APP_EXTENSION
        if !self.isNextcloudAppInstalled() {
            return
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let nextcloudURLString = "\(nextcloudScheme)//open-file?path=\(path)&user=\(activeAccount.userId)&link=\(link)"
        if let nextcloudEncodedURLString = nextcloudURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let nextcloudURL = URL(string: nextcloudEncodedURLString) {

            UIApplication.shared.open(nextcloudURL)
        }
#endif
    }

    public static func openFileInNextcloudAppOrBrowser(path: String, withFileLink link: String) {
#if !APP_EXTENSION
        if self.isNextcloudAppInstalled() {
            self.openFileInNextcloudApp(path: path, withFileLink: link)
        } else {
            self.openLinkInBrowser(link: link)
        }
#endif
    }

    public static func openLinkInBrowser(link: String) {
#if !APP_EXTENSION
        guard let URL = URL(string: link) else { return }

        UIApplication.shared.open(URL)
#endif
    }

    public static func isInstanceRoomLink(link: String) -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomPrefix1 = "\(activeAccount.server)/call"
        let roomPrefix2 = "\(activeAccount.server)/index.php/call"

        return link.lowercased().contains(roomPrefix1) || link.lowercased().contains(roomPrefix2)
    }

    // MARK: - Date utils

    public static func dateFromDateAtomFormat(dateAtomFormatString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"

        return dateFormatter.date(from: dateAtomFormatString)
    }

    public static func dateAtomFormatFromDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"

        return dateFormatter.string(from: date)
    }

    public static func readableDateTime(fromDate date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true

        return dateFormatter.string(from: date)
    }

    public static func readableTimeOrDate(fromDate date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return self.getTime(fromDate: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        return dateFormatter.string(from: date)
    }

    public static func readableTimeAndDate(fromDate date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return self.getTime(fromDate: date)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        return dateFormatter.string(from: date)
    }

    public static func getTime(fromDate date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short

        return dateFormatter.string(from: date)
    }

    public static func relativeTimeFromDate(date: Date) -> String {
        let todayDate = Date()
        var ti = date.timeIntervalSince(todayDate)
        ti *= -1

        if ti < 60 {
            // This minute
            return NSLocalizedString("less than a minute ago", comment: "")
        } else if ti < 3600 {
            // This hour
            let diff = Int(round(ti / 60))
            return String(format: NSLocalizedString("%d minutes ago", comment: ""), diff)
        } else if ti < 86400 {
            // This day
            let diff = Int(round(ti / 60 / 60))
            return String(format: NSLocalizedString("%d hours ago", comment: ""), diff)
        } else if ti < 86400 * 30 {
            // This month
            let diff = Int(round(ti / 60 / 60 / 24))
            return String(format: NSLocalizedString("%d days ago", comment: ""), diff)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.formatterBehavior = .behavior10_4
        dateFormatter.dateStyle = .medium

        return dateFormatter.string(from: date)
    }

    public static func today(withHour hour: Int, withMinute minute: Int, withSecond second: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = second

        return calendar.date(from: components)
    }

    public static func setWeekday(_ weekday: Int, withDate date: Date) -> Date {
        let currentWeekday = Calendar.current.component(.weekday, from: date)
        return Calendar.current.date(byAdding: .day, value: (weekday - currentWeekday), to: date)!
    }

    // MARK: - Crypto utils

    public static func sha1(fromString string: String) -> String {
        let data = string.data(using: .utf8)!
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }

    // MARK: - Image utils

    public static func blurImage(fromImage image: UIImage) -> UIImage? {
        let inputRadius = 8.0

        guard let inputImage = CIImage(image: image),
              let filter = CIFilter(name: "CIGaussianBlur")
        else { return nil }

        let context = CIContext()
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(inputRadius, forKey: "inputRadius")

        guard let result = filter.value(forKey: kCIOutputImageKey) as? CIImage else { return nil }

        let imageRect = inputImage.extent
        let cropRect = CGRect(x: imageRect.origin.x + inputRadius, y: imageRect.origin.y + inputRadius, width: imageRect.width - inputRadius * 2, height: imageRect.height - inputRadius * 2)

        if let cgImage = context.createCGImage(result, from: imageRect)?.cropping(to: cropRect) {
            return UIImage(cgImage: cgImage)
        }

        return nil
    }

    public static func roundedImage(fromImage image: UIImage) -> UIImage {
        let imageSize = image.size
        let rect = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.width)

        UIGraphicsBeginImageContextWithOptions(imageSize, false, UIScreen.main.scale)
        UIBezierPath(roundedRect: rect, cornerRadius: imageSize.height).addClip()
        image.draw(in: rect)

        if let resultImage = UIGraphicsGetImageFromCurrentImageContext() {
            UIGraphicsEndImageContext()
            return resultImage
        }

        UIGraphicsEndImageContext()
        return image
    }

    public static func renderAspectImage(image: UIImage?, ofSize size: CGSize, centerImage center: Bool) -> UIImage? {
        guard let image else { return nil }

        let newRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(newRect.size, false, 0.0)

        let aspectRatio = AVMakeRect(aspectRatio: image.size, insideRect: newRect)
        var targetOrigin: CGPoint = .zero

        if center {
            targetOrigin = CGPoint(x: newRect.maxX / 2 - aspectRatio.width / 2, y: newRect.maxY / 2 - aspectRatio.height / 2)
        }

        image.draw(in: CGRect(origin: targetOrigin, size: aspectRatio.size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }

    public static func getImage(withString string: String, withBackgroundColor color: UIColor, withBounds bounds: CGRect, isCircular circular: Bool) -> UIImage? {
        // Based on the "UIImageView+Letters" library from Tom Bachant

        let fontSize = bounds.width * 0.5
        var displayString = ""

        let word = string.components(separatedBy: .whitespacesAndNewlines)

        // Get first letter of the first word
        if let firstWord = word.first, !firstWord.isEmpty, let firstCharacter = firstWord.first {
            displayString.append(firstCharacter)
        }

        let scale = Float(UIScreen.main.scale)
        let width = floorf(Float(bounds.size.width) * scale) / scale
        let height = floorf(Float(bounds.size.height) * scale) / scale
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))

        UIGraphicsBeginImageContextWithOptions(size, false, CGFloat(scale))
        let context = UIGraphicsGetCurrentContext()!

        if circular {
            // Clip context to a circle
            let path = CGPath(ellipseIn: bounds, transform: nil)
            context.addPath(path)
            context.clip()
        }

        // Fill background of context
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Draw text in the context
        displayString = displayString.uppercased()

        let textAttributes = [
            NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: fontSize),
            NSAttributedString.Key.foregroundColor: UIColor.white
        ]

        let textSize = displayString.size(withAttributes: textAttributes)
        let textRect = CGRect(x: bounds.size.width / 2 - textSize.width / 2,
                              y: bounds.size.height / 2 - textSize.height / 2,
                              width: textSize.width,
                              height: textSize.height)

        displayString.draw(in: textRect, withAttributes: textAttributes)

        let snapshot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return snapshot
    }

    // MARK: - Color utils

    public static func searchbarBGColor(forColor color: UIColor) -> UIColor {
        let luma = self.calculateLuma(fromColor: color)
        return (luma > 0.6) ? UIColor(white: 0, alpha: 0.1) : UIColor(white: 1, alpha: 0.2)
    }

    public static func calculateLuma(fromColor color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }

    public static func color(fromHexString hexString: String) -> UIColor? {
        if hexString.isEmpty {
            return nil
        }

        // Check hex color string format (e.g."#00FF00")
        guard let regex = try? NSRegularExpression(pattern: "^#(?:[0-9a-fA-F]{6})$", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: hexString, range: NSRange(location: 0, length: hexString.count))
        else { return nil }

        if match.numberOfRanges != 1 {
            return nil
        }

        // Convert Hex color to UIColor
        var rgbValue: UInt64 = 0
        let scanner = Scanner(string: hexString)
        scanner.scanLocation = 1
        scanner.scanHexInt64(&rgbValue)

        let red = CGFloat((rgbValue & 0xFF0000) >> 16)/255.0
        let green = CGFloat((rgbValue & 0xFF00) >> 8)/255.0
        let blue = CGFloat(rgbValue & 0xFF)/255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    public static func hexString(fromColor color: UIColor) -> String {
        // See: https://stackoverflow.com/a/39358741
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let multiplier = CGFloat(255.999999)

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return ""
        }

        // We don't expect an alpha component right now
        return String(
            format: "#%02lX%02lX%02lX",
            min(Int(red * multiplier), 255),
            min(Int(green * multiplier), 255),
            min(Int(blue * multiplier), 255)
        )
    }

    // MARK: - QueryItems utils

    public static func value(forKey key: String, fromQueryItems queryItems: NSArray) -> String? {
        let predicate = NSPredicate(format: "name=%@", key)
        if let queryItem = queryItems.filtered(using: predicate).first as? NSURLQueryItem {
            return queryItem.value
        }

        return nil
    }

    // MARK: - Logging

    private static var logfilePath: URL? = {
        guard let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }

        let fileManager = FileManager.default
        let logDir = documentDir.appendingPathComponent("logs")
        let logPath = logDir.path

        // Allow writing to files while the app is in the background
        if !fileManager.fileExists(atPath: logPath) {
            try? fileManager.createDirectory(atPath: logPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.protectionKey: FileProtectionType.none])
        }

        return logDir
    }()

    public static func removeOldLogfiles() {
        guard let logfilePath else { return }

        let logPath = logfilePath.path
        let fileManager = FileManager.default

        var dayComponent = DateComponents()
        dayComponent.day = -10

        guard let enumerator = fileManager.enumerator(atPath: logPath),
              let thresholdDate = Calendar.current.date(byAdding: dayComponent, to: Date())
        else { return }

        while let file = enumerator.nextObject() as? String {
            let filePathURL = logfilePath.appendingPathComponent(file)
            let filePath = filePathURL.path

            guard let creationDate = (try? FileManager.default.attributesOfItem(atPath: filePath))?[.creationDate] as? Date
            else { continue }

            if creationDate.compare(thresholdDate) == .orderedAscending && file.hasPrefix("debug-") && file.hasSuffix(".log") {
                NSLog("Deleting old logfile %@", filePath)
                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }

    public static func log(_ message: String) {
        do {
            guard let logfilePath else { return }

            let currentQueueName = Thread.current.queueName
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "y-MM-dd H:mm:ss.SSSS"

            var logMessage = "\(dateFormatter.string(from: Date())) "
            logMessage += "(\(currentQueueName)): \(message)\n"

            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let logFileName = "debug-\(dateString).log"
            let fullPath = logfilePath.appendingPathComponent(logFileName).path

            if let fileHandle = FileHandle(forWritingAtPath: fullPath) {
                fileHandle.seekToEndOfFile()
                // UTF-8 will never be nil
                try fileHandle.write(contentsOf: logMessage.data(using: .utf8)!)
                try fileHandle.close()
            } else {
                try logMessage.write(toFile: fullPath, atomically: false, encoding: .utf8)
            }

            NSLog("%@", logMessage)
        } catch {
            NSLog("Exception in NCUtils.log: %@", error.localizedDescription)
            NSLog("Message: %@", message)
        }
    }

    // MARK: - iOS on Mac

    public static func isiOSAppOnMac() -> Bool {
        return ProcessInfo.processInfo.isiOSAppOnMac
    }
}

extension Thread {
    var threadName: String {
        if isMainThread {
            return "main"
        } else if let threadName = Thread.current.name, !threadName.isEmpty {
            return threadName
        } else {
            return description
        }
    }

    var queueName: String {
        if let queueName = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            return queueName
        } else if let operationQueueName = OperationQueue.current?.name, !operationQueueName.isEmpty {
            return operationQueueName
        } else if let dispatchQueueName = OperationQueue.current?.underlyingQueue?.label, !dispatchQueueName.isEmpty {
            return dispatchQueueName
        } else {
            return "n/a"
        }
    }
}
