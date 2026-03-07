//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers public class NCLog: NSObject {

    private static let backgroundLogQueue = DispatchQueue(label: "\(bundleIdentifier).backgroundLogQueue", qos: .background)

    private static let logLineDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd H:mm:ss.SSSS"

        return dateFormatter
    }()

    private static let fileNameDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return dateFormatter
    }()

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

    public static func log(_ message: String) {
        guard let logfilePath else { return }

        // Determine the queue here, as otherwise it will be always the backgroundQueue
        let currentQueueName = Thread.current.queueName

        backgroundLogQueue.async {
            do {
                let now = Date()

                var logMessage = "\(logLineDateFormatter.string(from: now)) "
                logMessage += "(\(currentQueueName)): \(message)\n"

                let dateString = fileNameDateFormatter.string(from: now)
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
                NSLog("Exception in NCLog.log: %@", error.localizedDescription)
                NSLog("Message: %@", message)
            }
        }
    }

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
}
