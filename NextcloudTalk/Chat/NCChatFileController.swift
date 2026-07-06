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

    private static let deleteFilesOlderThanDays = 7

    public weak var delegate: NCChatFileControllerDelegate?
    public var messageType: String?
    public var actionType: String?
    public private(set) var tempDirectoryPath = ""

    private var fileStatus: NCChatFileStatus?

    public func initDownloadDirectory(for account: TalkAccount) {
        let encodedAccountId = account.accountId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        let fileManager = FileManager.default

        tempDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("download")
        tempDirectoryPath = (tempDirectoryPath as NSString).appendingPathComponent(encodedAccountId)

        print("Directory for downloads: \(tempDirectoryPath)")

        if !fileManager.fileExists(atPath: tempDirectoryPath) {
            // Make sure our download directory exists
            try? fileManager.createDirectory(atPath: tempDirectoryPath, withIntermediateDirectories: true)
        }

        removeOldFilesFromCache(thresholdDays: NCChatFileController.deleteFilesOlderThanDays)
    }

    private func removeOldFilesFromCache(thresholdDays: Int) {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(atPath: tempDirectoryPath),
              let thresholdDate = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date())
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

    public func deleteDownloadDirectory(for account: TalkAccount) {
        initDownloadDirectory(for: account)
        try? FileManager.default.removeItem(atPath: tempDirectoryPath)

        print("Deleted download directory: \(tempDirectoryPath)")
    }

    public func clearDownloadDirectory(for account: TalkAccount) {
        deleteDownloadDirectory(for: account)
        initDownloadDirectory(for: account)
    }

    public func getDiskUsage(for account: TalkAccount) -> Int {
        initDownloadDirectory(for: account)

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

    private func setCreationDate(onFile filePath: String, withCreationDate date: Date) {
        try? FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: filePath)
    }

    private func setModificationDate(onFile filePath: String, withModificationDate date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: filePath)
    }

    public func downloadFile(fromMessage fileParameter: NCMessageFileParameter) {
        let fileStatus = NCChatFileStatus(fileId: fileParameter.parameterId, fileName: fileParameter.name, filePath: fileParameter.path ?? "")
        self.fileStatus = fileStatus
        fileParameter.fileStatus = fileStatus

        startDownload()
    }

    public func downloadFile(withFileId fileId: String) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getFileById(forAccount: activeAccount, withFileId: fileId) { file, error in
            guard let file else {
                print("An error occurred while getting file with fileId \(fileId): \(error?.errorDescription ?? "")")
                self.delegate?.fileControllerDidFailLoadingFile(self, withFileId: fileId, withErrorDescription: error?.errorDescription ?? "")
                return
            }

            let remoteDavPrefix = "/remote.php/dav/files/\(activeAccount.userId)/"
            let directoryPath = file.path.components(separatedBy: remoteDavPrefix).last ?? ""

            let filePath = "\(directoryPath)\(file.fileName)"

            self.fileStatus = NCChatFileStatus(fileId: file.fileId, fileName: file.fileName, filePath: filePath)
            self.startDownload()
        }
    }

    public func moveFileToTemporaryDirectory(fromSourcePath sourcePath: String, destinationPath: String) -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        initDownloadDirectory(for: activeAccount)

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

    private func startDownload() {
        guard let fileStatus else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().setupNCCommunication(forAccount: activeAccount)
        initDownloadDirectory(for: activeAccount)

        let serverUrlFileName = "\(activeAccount.server)\(NCAPIController.sharedInstance().filesPath(forAccount: activeAccount))/\(fileStatus.filePath)"
        let fileLocalPath = (tempDirectoryPath as NSString).appendingPathComponent(fileStatus.fileName)
        fileStatus.fileLocalPath = fileLocalPath

        // Setting just isDownloading without a concrete progress will show an indeterminate activity indicator
        didChangeIsDownloadingNotification(isDownloading: true)

        // First read metadata from the file and check if we already downloaded it
        let options = NKRequestOptions(timeout: 60, queue: .main)
        NextcloudKit.shared.readFileOrFolder(serverUrlFileName: serverUrlFileName, depth: "0", showHiddenFiles: true, options: options) { _, files, _, error in
            guard error.errorCode == 0, files.count == 1, let file = files.first else {
                self.didChangeIsDownloadingNotification(isDownloading: false)

                print("Error downloading file: \(error.errorCode) - \(error.errorDescription)")
                self.delegate?.fileControllerDidFailLoadingFile(self, withFileId: fileStatus.fileId, withErrorDescription: error.errorDescription)
                return
            }

            // File exists on server -> check our cache
            if self.isFileInCache(fileLocalPath, withModificationDate: file.date as Date, withSize: file.size) {
                print("Found file in cache: \(fileLocalPath)")

                self.delegate?.fileControllerDidLoadFile(self, with: fileStatus)
                self.didChangeIsDownloadingNotification(isDownloading: false)

                return
            }

            NextcloudKit.shared.download(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileLocalPath, queue: .main) { _ in
                print("Download task")
            } progressHandler: { progress in
                self.didChangeDownloadProgressNotification(progress: progress)
            } completionHandler: { _, _, _, _, _, error in
                if error.errorCode == 0 {
                    // Set modification date to invalidate our cache
                    self.setModificationDate(onFile: fileLocalPath, withModificationDate: file.date as Date)

                    // Set creation date to delete older files from cache
                    self.setCreationDate(onFile: fileLocalPath, withCreationDate: Date())

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
