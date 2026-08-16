//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit

public extension NSNotification.Name {
    static let NCChatFileControllerDidChangeIsDownloading = NSNotification.Name("NCChatFileControllerDidChangeIsDownloadingNotification")
    static let NCChatFileControllerDidChangeDownloadProgress = NSNotification.Name("NCChatFileControllerDidChangeDownloadProgressNotification")
}

public protocol NCChatFileControllerDelegate: AnyObject {
    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus)
    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String)
}

public class NCChatFileController: NSObject {

    public weak var delegate: NCChatFileControllerDelegate?

    public var messageType: String?
    public var actionType: String?
    public private(set) var tempDirectoryPath = ""

    private let account: TalkAccount
    private let deleteFilesOlderThanDays = 7
    private var fileStatus: NCChatFileStatus?
    private var cancelDownloadHandler: (() -> Void)?
    private var isCancelled = false

    init(account: TalkAccount) {
        self.account = account

        super.init()

        self.initDownloadDirectory()
        AllocationTracker.shared.addAllocation()
    }

    deinit {
        AllocationTracker.shared.removeAllocation()
    }

    private func initDownloadDirectory() {
        let encodedAccountId = self.account.accountId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        let fileManager = FileManager.default

        tempDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("download")
        tempDirectoryPath = (tempDirectoryPath as NSString).appendingPathComponent(encodedAccountId)

        print("Directory for downloads: \(tempDirectoryPath)")

        if !fileManager.fileExists(atPath: tempDirectoryPath) {
            // Make sure our download directory exists
            try? fileManager.createDirectory(atPath: tempDirectoryPath, withIntermediateDirectories: true)
        }
    }

    public func removeOldFilesFromCache() {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(atPath: tempDirectoryPath),
              let thresholdDate = Calendar.current.date(byAdding: .day, value: -deleteFilesOlderThanDays, to: Date())
        else { return }

        for case let file as String in enumerator {
            let filePath = (tempDirectoryPath as NSString).appendingPathComponent(file)
            let creationDate = (try? fileManager.attributesOfItem(atPath: filePath))?[.creationDate] as? Date

            if let creationDate, creationDate.compare(thresholdDate) == .orderedAscending {
                print("Deleting file from cache: \(filePath)")

                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }

    public func deleteDownloadDirectory() {
        try? FileManager.default.removeItem(atPath: tempDirectoryPath)

        print("Deleted download directory: \(tempDirectoryPath)")
    }

    public func clearDownloadDirectory() {
        deleteDownloadDirectory()
        initDownloadDirectory()
    }

    public func getDiskUsage() -> Int {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(atPath: tempDirectoryPath) else { return 0 }

        var folderSize = 0

        for case let file as String in enumerator {
            let filePath = (tempDirectoryPath as NSString).appendingPathComponent(file)
            let fileAttributes = try? fileManager.attributesOfItem(atPath: filePath)
            folderSize += (fileAttributes?[.size] as? Int) ?? 0
        }

        return folderSize
    }

    private func isFileInCache(_ filePath: String, withModificationDate date: Date, withSize size: Int64) -> Bool {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: filePath) else { return false }

        let fileAttributes = try? fileManager.attributesOfItem(atPath: filePath)
        let modificationDate = fileAttributes?[.modificationDate] as? Date
        let fileSize = (fileAttributes?[.size] as? Int64) ?? 0

        if let modificationDate, date.compare(modificationDate) == .orderedSame, fileSize == size {
            return true
        }

        // At this point there's a file in our cache but there's a different one on the server
        print("Deleting file from cache: \(filePath)")
        try? fileManager.removeItem(atPath: filePath)

        return false
    }

    private func setDate(onFile filePath: String, withCreationDate creationDate: Date?, withModificationDate modificationDate: Date?) {
        // Setting both, modification- and creationDate in one go does not work, we will end up with the modification date in both fields
        // Also the creationDate needs to be set after modificationDate (most likely because creation cannot be later than modification in theory)
        if let modificationDate {
            try? FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: filePath)
        }

        if let creationDate {
            try? FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: filePath)
        }
    }

    public func moveFileToTemporaryDirectory(fromSourcePath sourcePath: String, destinationPath: String) -> Bool {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationPath) {
            print("File is already in temporary directory: \(destinationPath)")
            return false
        }

        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            print("File successfully moved to: \(destinationPath)")
            return true
        } catch {
            print("Error while moving file to temporary directory: \(error.localizedDescription)")
            return false
        }
    }

    ///
    /// Locally cached file, without asking the server whether our copy is still current.
    ///
    /// Only matches when the size is the one announced in the chat message, so a file that was
    /// replaced with a differently sized one on the server is not returned. A replacement with the
    /// exact same size is only caught once `downloadFile(withFileId:)` has validated the file.
    ///
    public func cachedFileURL(forFileNamed fileName: String, expectedSize: Int) -> URL? {
        guard expectedSize > 0 else { return nil }

        let filePath = (self.tempDirectoryPath as NSString).appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: filePath),
              let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = attributes[.size] as? Int, size == expectedSize
        else { return nil }

        return URL(fileURLWithPath: filePath)
    }

    // Stops an ongoing download. No delegate method is called afterwards.
    public func cancelDownload() {
        self.isCancelled = true
        self.cancelDownloadHandler?()
        self.cancelDownloadHandler = nil

        if self.fileStatus?.isDownloading == true {
            self.didChangeIsDownloadingNotification(isDownloading: false)
        }
    }

    public func downloadFile(withFileId fileId: String) {
        self.isCancelled = false

        // getFileById already sets up NextcloudKit
        NCAPIController.sharedInstance().getFileById(forAccount: self.account, withFileId: fileId) { file, error in
            guard !self.isCancelled else { return }

            guard let file else {
                print("An error occurred while getting file with fileId \(fileId): \(error?.errorDescription ?? "")")
                self.delegate?.fileControllerDidFailLoadingFile(self, withFileId: fileId, withErrorDescription: error?.errorDescription ?? "")
                return
            }

            let remoteDavPrefix = "/remote.php/dav/files/\(self.account.userId)/"
            let directoryPath = file.path.components(separatedBy: remoteDavPrefix).last ?? ""

            let filePath = "\(directoryPath)\(file.fileName)"

            let fileStatus = NCChatFileStatus(fileId: file.fileId, fileName: file.fileName, filePath: filePath)
            self.fileStatus = fileStatus

            let serverUrlFileName = "\(self.account.server)\(NCAPIController.sharedInstance().filesPath(forAccount: self.account))/\(fileStatus.filePath)"
            let fileLocalPath = (self.tempDirectoryPath as NSString).appendingPathComponent(fileStatus.fileName)
            fileStatus.fileLocalPath = fileLocalPath

            // Setting just isDownloading without a concrete progress will show an indeterminate activity indicator
            self.didChangeIsDownloadingNotification(isDownloading: true)

            // File exists on server -> check our cache
            if self.isFileInCache(fileLocalPath, withModificationDate: file.date as Date, withSize: file.size) {
                print("Found file in cache: \(fileLocalPath)")

                self.delegate?.fileControllerDidLoadFile(self, with: fileStatus)
                self.didChangeIsDownloadingNotification(isDownloading: false)

                return
            }

            NextcloudKit.shared.download(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileLocalPath, queue: .main) { request in
                self.cancelDownloadHandler = { _ = request.cancel() }
            } progressHandler: { progress in
                self.didChangeDownloadProgressNotification(progress: progress)
            } completionHandler: { _, _, _, _, _, error in
                self.cancelDownloadHandler = nil

                guard !self.isCancelled else { return }

                if error.errorCode == 0 {
                    // Set modification date to invalidate our cache
                    // Set creation date to delete older files from cache
                    self.setDate(onFile: fileLocalPath, withCreationDate: Date(), withModificationDate: file.date as Date)

                    self.delegate?.fileControllerDidLoadFile(self, with: fileStatus)
                } else {
                    print("Error downloading file: \(error.errorCode) - \(error.errorDescription)")
                    self.delegate?.fileControllerDidFailLoadingFile(self, withFileId: fileStatus.fileId, withErrorDescription: error.errorDescription)
                }

                self.didChangeIsDownloadingNotification(isDownloading: false)
            }
        }
    }

    private func didChangeIsDownloadingNotification(isDownloading: Bool) {
        guard let fileStatus else { return }

        fileStatus.isDownloading = isDownloading

        NotificationCenter.default.post(name: .NCChatFileControllerDidChangeIsDownloading, object: self, userInfo: ["fileStatus": fileStatus])
    }

    private func didChangeDownloadProgressNotification(progress: Progress) {
        guard let fileStatus else { return }

        fileStatus.downloadProgress = Float(progress.fractionCompleted)
        fileStatus.canReportProgress = progress.totalUnitCount != -1

        NotificationCenter.default.post(name: .NCChatFileControllerDidChangeDownloadProgress, object: self, userInfo: ["fileStatus": fileStatus])
    }
}
