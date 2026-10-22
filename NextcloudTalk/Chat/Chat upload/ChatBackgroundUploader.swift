//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import UserNotifications

/// A file handed to a background URL session, together with everything needed to post it into the
/// conversation once it is uploaded.
struct ChatBackgroundUploadJob: Codable {
    let id: String
    let sessionIdentifier: String
    let index: Int
    let accountId: String
    let roomToken: String
    let roomName: String
    let fileName: String
    let draftPath: String
    let serverURL: String
    let referenceId: String?
    let metadata: ChatFileUploadMetadata
    let allowUpdate: Bool
    let createdAt: Date
    var uploaded = false
    var postStarted = false
    var uploadAttempts = 0
    var announceAttempts = 0
}

/// Uploads files through background URL sessions, so the share extension can close right after send.
///
/// The extension starts the uploads, the app finishes them when the system launches it for the session events.
/// Only the draft folder flow is supported, as uploading again to the same draft path is harmless there.
final class ChatBackgroundUploader: NSObject, URLSessionTaskDelegate {

    static let shared = ChatBackgroundUploader()

    private static let sessionIdentifierPrefix = "\(groupIdentifier).chatUpload."

    // Younger jobs may still belong to a running extension, and two processes must not use the same session
    private static let reconnectGracePeriod: TimeInterval = 60

    // Gives a reconnected session time to deliver its completion events before tasks are taken as lost
    private static let lostTaskCheckDelay: TimeInterval = 5

    private static let maxAnnounceAttempts = 3
    private static let maxJobAge: TimeInterval = 24 * 60 * 60

    // Delays before the next upload attempt, the last one repeats until the job is too old
    private static let uploadRetryDelays: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]

    private static let jobFileName = "job.json"
    private static let dataFileName = "data"

    // Only touched on the main queue, which is the delegate queue of the sessions as well
    private var sessions: [String: URLSession] = [:]
    private var backgroundEventsCompletionHandlers: [String: () -> Void] = [:]
    private var sessionsWithFinishedEvents: Set<String> = []
    private var announcingSessions: Set<String> = []
    private var checkedSessions: Set<String> = []

    // MARK: - Enqueue

    /// Returns once all uploads are handed to the system. Nothing is uploaded when this throws.
    @MainActor
    func enqueue(_ uploads: [ChatFileUpload]) async throws {
        guard let firstUpload = uploads.first else { return }

        guard let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: firstUpload.account)
        else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

        let draftFolder = try await ChatFileUploader.probeDraftFolder(for: firstUpload.room,
                                                                      account: firstUpload.account,
                                                                      fileNames: uploads.map { $0.fileName },
                                                                      allowUpdate: firstUpload.allowUpdate)

        let sessionIdentifier = Self.sessionIdentifierPrefix + UUID().uuidString
        var preparedJobs: [ChatBackgroundUploadJob] = []

        do {
            for (index, upload) in uploads.enumerated() {
                let destination = try await ChatFileUploader.draftFolderDestination(in: draftFolder, for: upload)

                // Encoded the same way NextcloudKit encodes its upload URLs
                guard case .draftFolder(let draftPath, _, let serverURL) = destination,
                      let encodedServerURL = serverURL.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                      URL(string: encodedServerURL) != nil
                else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

                let job = ChatBackgroundUploadJob(id: UUID().uuidString,
                                                  sessionIdentifier: sessionIdentifier,
                                                  index: index,
                                                  accountId: upload.account.accountId,
                                                  roomToken: upload.room.token,
                                                  roomName: upload.room.displayName,
                                                  fileName: upload.fileName,
                                                  draftPath: draftPath,
                                                  serverURL: encodedServerURL,
                                                  referenceId: upload.referenceId,
                                                  metadata: upload.metadata,
                                                  allowUpdate: upload.allowUpdate,
                                                  createdAt: Date())

                preparedJobs.append(job)

                try self.prepareFiles(for: job, copying: URL(fileURLWithPath: upload.localPath))
            }
        } catch {
            preparedJobs.forEach { self.removeJob($0) }
            throw error
        }

        let session = self.session(withIdentifier: sessionIdentifier)

        for job in preparedJobs {
            self.startUploadTask(for: job, in: session, authHeader: authHeader)
        }

        NCLog.log("Handed \(preparedJobs.count) files to the background session \(sessionIdentifier)")
    }

    private func prepareFiles(for job: ChatBackgroundUploadJob, copying fileURL: URL) throws {
        guard let jobDirectory = self.jobDirectory(forJobId: job.id)
        else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fileURL, to: jobDirectory.appendingPathComponent(Self.dataFileName))
        try self.save(job)
    }

    private func startUploadTask(for job: ChatBackgroundUploadJob, in session: URLSession, authHeader: String, earliestBeginDate: Date? = nil) {
        guard let url = URL(string: job.serverURL),
              let dataFileURL = self.jobDirectory(forJobId: job.id)?.appendingPathComponent(Self.dataFileName)
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")

        let task = session.uploadTask(with: request, fromFile: dataFileURL)
        task.taskDescription = job.id
        task.earliestBeginDate = earliestBeginDate
        task.resume()
    }

    // MARK: - App

#if !APP_EXTENSION
    /// Returns `false` for sessions that belong to someone else.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        guard identifier.hasPrefix(Self.sessionIdentifierPrefix) else { return false }

        NCLog.log("Handling events of the background upload session \(identifier)")

        self.backgroundEventsCompletionHandlers[identifier] = completionHandler
        _ = self.session(withIdentifier: identifier)

        return true
    }

    func startResumingPendingJobs() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resumePendingJobs()
        }
    }

    /// Finishes what the system did not launch the app for, for example after a failed post or a force quit.
    /// The completion is called once the posts it started are done. Must be called on the main queue.
    func resumePendingJobs(completion: (() -> Void)? = nil) {
        guard let jobsDirectory = Self.jobsDirectory,
              let jobDirectories = try? FileManager.default.contentsOfDirectory(at: jobsDirectory, includingPropertiesForKeys: [.creationDateKey])
        else {
            completion?()
            return
        }

        let now = Date()
        var sessionsToCheck: Set<String> = []
        var sessionsToAnnounce: Set<String> = []

        for jobDirectory in jobDirectories {
            let creationDate = (try? jobDirectory.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? now

            guard now.timeIntervalSince(creationDate) > Self.reconnectGracePeriod else { continue }

            // Left behind by an extension that was killed while preparing it
            guard let job = self.loadJob(withId: jobDirectory.lastPathComponent) else {
                try? FileManager.default.removeItem(at: jobDirectory)
                continue
            }

            if now.timeIntervalSince(job.createdAt) > Self.maxJobAge {
                self.drop(job, reason: "it is too old")
            } else if job.uploaded {
                sessionsToAnnounce.insert(job.sessionIdentifier)
            } else if !self.checkedSessions.contains(job.sessionIdentifier) {
                sessionsToCheck.insert(job.sessionIdentifier)
            }
        }

        let announceGroup = DispatchGroup()

        for identifier in sessionsToAnnounce {
            announceGroup.enter()
            self.announceFiles(of: identifier) { announceGroup.leave() }
        }

        announceGroup.notify(queue: .main) { completion?() }

        for identifier in sessionsToCheck {
            self.checkedSessions.insert(identifier)
            self.restartLostTasks(in: self.session(withIdentifier: identifier))
        }
    }

    private func restartLostTasks(in session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lostTaskCheckDelay) {
            session.getAllTasks { tasks in
                let runningJobIds = Set(tasks.compactMap { $0.taskDescription })

                DispatchQueue.main.async {
                    for job in self.loadAllJobs() where job.sessionIdentifier == identifier && !job.uploaded && !runningJobIds.contains(job.id) {
                        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId),
                              let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: account)
                        else {
                            self.drop(job, reason: "its account is gone")
                            continue
                        }

                        NCLog.log("Restarting background upload of \(job.fileName)")
                        self.startUploadTask(for: job, in: session, authHeader: authHeader)
                    }
                }
            }
        }
    }
#endif

    // MARK: - Announce

    /// Posts the files of one share in their original order once all of them are uploaded, like the web
    /// does, so the caption on the last one ends the group in the chat.
    private func announceFiles(of sessionIdentifier: String, completion: (() -> Void)? = nil) {
        guard !self.announcingSessions.contains(sessionIdentifier) else {
            completion?()
            return
        }

        let jobs = self.loadAllJobs().filter { $0.sessionIdentifier == sessionIdentifier }.sorted { $0.index < $1.index }

        guard !jobs.isEmpty, jobs.allSatisfy({ $0.uploaded }) else {
            completion?()
            return
        }

        self.announcingSessions.insert(sessionIdentifier)

        let bgTask = BGTaskHelper.startExpiringActivity(withName: "ChatBackgroundUploader.announce")

        Task { @MainActor in
            // A file that stays behind for a retry stops the rest, otherwise they would overtake it
            for job in jobs {
                guard await self.post(job) else { break }
            }

            self.announcingSessions.remove(sessionIdentifier)
            self.finishSessionIfDone(sessionIdentifier)

            bgTask.stopBackgroundTask()
            completion?()
        }
    }

    /// Returns whether the job is done, either posted or dropped.
    @MainActor
    private func post(_ job: ChatBackgroundUploadJob) async -> Bool {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId) else {
            self.drop(job, reason: "its account is gone")
            return true
        }

        // Saved before sending, as the process can be suspended before the answer arrives,
        // for example the extension right after it was closed
        var job = job
        let earlierPostStarted = job.postStarted
        job.postStarted = true
        try? self.save(job)

        do {
            try await NCAPIController.sharedInstance().postConversationAttachment(inRoom: job.roomToken,
                                                                                 filePath: job.draftPath,
                                                                                 fileName: job.fileName,
                                                                                 referenceId: job.referenceId,
                                                                                 talkMetaData: job.metadata.asDictionary(),
                                                                                 allowUpdate: job.allowUpdate,
                                                                                 forAccount: account)

            NCLog.log("Posted background upload \(job.fileName)")
            self.removeJob(job)

            return true
        } catch {
            NCLog.log("Failed to post background upload \(job.fileName). Error: \(error.localizedDescription)")

            // Being offline should not use up the attempts, only answers of the server do
            guard (error as NSError).domain != NSURLErrorDomain else { return false }

            // An earlier post whose answer got lost already moved the file out of the draft folder
            let response = (error as NSError).userInfo[AFNetworkingOperationFailingURLResponseErrorKey] as? HTTPURLResponse
            if earlierPostStarted, response?.statusCode == 404 {
                NCLog.log("Background upload \(job.fileName) was already posted")
                self.removeJob(job)
                return true
            }

            job.announceAttempts += 1

            if job.announceAttempts >= Self.maxAnnounceAttempts {
                self.drop(job, reason: "posting it failed \(job.announceAttempts) times")
                return true
            }

            try? self.save(job)

            return false
        }
    }

    private func finishSessionIfDone(_ identifier: String) {
        guard self.sessionsWithFinishedEvents.contains(identifier),
              !self.announcingSessions.contains(identifier)
        else { return }

        self.sessionsWithFinishedEvents.remove(identifier)

        if !self.loadAllJobs().contains(where: { $0.sessionIdentifier == identifier }) {
            self.sessions.removeValue(forKey: identifier)?.finishTasksAndInvalidate()
        }

        self.backgroundEventsCompletionHandlers.removeValue(forKey: identifier)?()
    }

    // MARK: - URLSession

    private func session(withIdentifier identifier: String) -> URLSession {
        if let session = self.sessions[identifier] {
            return session
        }

        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = groupIdentifier
        // Without it, an upload waiting for a network keeps the job alive for 7 days
        configuration.timeoutIntervalForResource = Self.maxJobAge

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.sessions[identifier] = session

        return session
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let jobId = task.taskDescription,
              var job = self.loadJob(withId: jobId)
        else { return }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0

        if error == nil, (200..<300).contains(statusCode) {
            job.uploaded = true
            try? self.save(job)

            self.announceFiles(of: job.sessionIdentifier)
            return
        }

        NCLog.log("Background upload of \(job.fileName) failed with status \(statusCode). Error: \(error?.localizedDescription ?? "none")")

        let isPermanent = statusCode == 507 || ((400..<500).contains(statusCode) && statusCode != 408 && statusCode != 429)

        if isPermanent {
            self.drop(job, reason: "the server rejected it")
            // The other files of the share were waiting for this one
            self.announceFiles(of: job.sessionIdentifier)
        } else if Date().timeIntervalSince(job.createdAt) > Self.maxJobAge {
            self.drop(job, reason: "it is too old")
            self.announceFiles(of: job.sessionIdentifier)
        } else if let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId),
                  let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: account) {
            let retryAfter = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            let delay = min(retryAfter ?? Self.uploadRetryDelays[min(job.uploadAttempts, Self.uploadRetryDelays.count - 1)], Self.uploadRetryDelays.last ?? 0)

            job.uploadAttempts += 1
            try? self.save(job)

            // The system starts it after the delay, even when neither the app nor the extension is running
            NCLog.log("Retrying background upload of \(job.fileName) in \(Int(delay))s")
            self.startUploadTask(for: job, in: session, authHeader: authHeader, earliestBeginDate: Date(timeIntervalSinceNow: delay))
        } else {
            self.drop(job, reason: "its account is gone")
            self.announceFiles(of: job.sessionIdentifier)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           CCCertificate.sharedManager().checkTrustedChallenge(challenge),
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }

        self.sessionsWithFinishedEvents.insert(identifier)
        self.finishSessionIfDone(identifier)
    }

    // MARK: - Failure

    private func drop(_ job: ChatBackgroundUploadJob, reason: String) {
        NCLog.log("Dropping background upload of \(job.fileName), \(reason)")
        self.removeJob(job)

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Upload failed", comment: "")
        content.body = String.localizedStringWithFormat(NSLocalizedString("%1$@ could not be sent to %2$@", comment: "'photo.jpg' could not be sent to 'Conversation name'"), job.fileName, job.roomName)
        content.threadIdentifier = job.roomToken
        content.sound = .default

        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "BackgroundUpload-\(job.id)", content: content, trigger: nil))
    }

    // MARK: - Storage

    private static var jobsDirectory: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("BackgroundUploads", isDirectory: true)
    }

    private func jobDirectory(forJobId jobId: String) -> URL? {
        return Self.jobsDirectory?.appendingPathComponent(jobId, isDirectory: true)
    }

    private func save(_ job: ChatBackgroundUploadJob) throws {
        guard let jobFileURL = self.jobDirectory(forJobId: job.id)?.appendingPathComponent(Self.jobFileName)
        else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

        try JSONEncoder().encode(job).write(to: jobFileURL, options: .atomic)
    }

    private func loadJob(withId jobId: String) -> ChatBackgroundUploadJob? {
        guard let jobFileURL = self.jobDirectory(forJobId: jobId)?.appendingPathComponent(Self.jobFileName),
              let data = try? Data(contentsOf: jobFileURL)
        else { return nil }

        return try? JSONDecoder().decode(ChatBackgroundUploadJob.self, from: data)
    }

    private func loadAllJobs() -> [ChatBackgroundUploadJob] {
        guard let jobsDirectory = Self.jobsDirectory,
              let jobIds = try? FileManager.default.contentsOfDirectory(atPath: jobsDirectory.path)
        else { return [] }

        return jobIds.compactMap { self.loadJob(withId: $0) }
    }

    private func removeJob(_ job: ChatBackgroundUploadJob) {
        guard let jobDirectory = self.jobDirectory(forJobId: job.id) else { return }

        try? FileManager.default.removeItem(at: jobDirectory)
    }
}
