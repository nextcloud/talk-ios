//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
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
    var uploadRetryDate: Date?
    var shareRetried = false
    // Caption with mention placeholders, only for showing it before it is posted
    var captionMessage: String?
    var captionMessageParameters: String?
    // Not started yet while nil
    var taskStart: TaskStart?
    var failedAt: Date?
    // Not sent in turns while nil
    var uploadTurn: UploadTurn?

    enum TaskStart: String, Codable {
        case foreground
        // The system may hold such a task back for hours, so the app starts it again from the foreground
        case background
    }

    /// Some servers read only a few uploads of one connection and let the others time out, so a file that timed out
    /// waits until fewer than uploadsPerTurn files of its share are sending.
    enum UploadTurn: String, Codable {
        case waiting
        // Still waiting, but tapped by the user, so it starts next and shows as uploading
        case requested
        case started
    }

    var isWaitingForUploadTurn: Bool {
        return self.uploadTurn == .waiting || self.uploadTurn == .requested
    }

    var isWaitingForUploadRetry: Bool {
        guard !self.uploaded, let uploadRetryDate = self.uploadRetryDate else { return false }

        return uploadRetryDate > Date()
    }

    /// Named like the file, so it can be previewed as it is
    var localFileName: String {
        let fileName = (self.fileName as NSString).lastPathComponent

        return fileName.isEmpty ? "data" : fileName
    }
}

/// What the chat shows of a file shared in the background.
enum ChatBackgroundUploadState: Equatable {
    case uploading
    case waitingForRetry(until: Date)
    /// See ChatBackgroundUploadJob.UploadTurn
    case waitingForTurn
    case uploaded
    case failed
}

/// A file of a share that is not in the conversation yet.
struct ChatBackgroundUpload {
    let job: ChatBackgroundUploadJob
    let fileURL: URL
    let isFailed: Bool

    var state: ChatBackgroundUploadState {
        if self.isFailed {
            return .failed
        }

        if self.job.uploaded {
            return .uploaded
        }

        if self.job.uploadTurn == .waiting {
            return .waitingForTurn
        }

        if self.job.uploadTurn == .requested {
            return .uploading
        }

        if self.job.isWaitingForUploadRetry, let uploadRetryDate = self.job.uploadRetryDate {
            return .waitingForRetry(until: uploadRetryDate)
        }

        return .uploading
    }
}

/// What the conversation list shows of the files shared into a conversation.
struct ChatBackgroundUploadSummary {
    /// Combined like the files behind a "+N" tile, nil when all of them failed
    let pendingState: ChatBackgroundUploadState?
    let failedFileCount: Int
    /// Seconds, like NCRoom.lastActivity
    let lastFailure: Int?
    /// Sharing a file and its failure count as activity of the conversation. Seconds, like NCRoom.lastActivity.
    let lastActivity: Int
}

extension Notification.Name {
    /// Posted on the main queue whenever this process added, changed or removed a job.
    static let ChatBackgroundUploaderDidChangeUploads = Notification.Name("ChatBackgroundUploaderDidChangeUploads")

    /// Posted on the main queue with "jobId" and "progress" (Float) in the user info.
    static let ChatBackgroundUploaderDidChangeUploadProgress = Notification.Name("ChatBackgroundUploaderDidChangeUploadProgress")
}

/// Uploads files through background URL sessions, so the share extension can close right after send.
///
/// The extension starts the uploads, the app finishes them when the system launches it for the session events.
/// Only the draft folder flow is supported, as uploading again to the same draft path is harmless there.
final class ChatBackgroundUploader: NSObject, URLSessionTaskDelegate {

    static let shared = ChatBackgroundUploader()

    private static let sessionIdentifierPrefix = "\(groupIdentifier).chatUpload."

    private static let reconnectGracePeriod: TimeInterval = 60

    /// The extension may still own the session, write the job, upload in the foreground or post it.
    private static func isInGracePeriod(since preparedAt: Date, now: Date) -> Bool {
        return now.timeIntervalSince(preparedAt) <= self.reconnectGracePeriod
    }

    // Gives a reconnected session time to deliver its completion events before tasks are taken as lost
    private static let lostTaskCheckDelay: TimeInterval = 5

    private static let maxJobAge: TimeInterval = 24 * 60 * 60

    // A failed upload is retried once after this delay, which covers a dropped connection or a server hiccup
    private static let uploadRetryDelay: TimeInterval = 30

    private static let uploadsPerTurn = 2

    // Also bounds the transfer, a background session does not tell it apart from waiting for a network
    private static let uploadResourceTimeout: TimeInterval = 60 * 60

    private static let jobFileName = "job.json"

    // Only touched on the main queue, which is the delegate queue of the sessions as well
    private var sessions: [String: URLSession] = [:]
    private var backgroundEventsCompletionHandlers: [String: () -> Void] = [:]
    private var sessionsWithFinishedEvents: Set<String> = []
    private var sharingSessions: Set<String> = []
    private var checkedSessions: Set<String> = []
    private var uploadProgress: [String: Float] = [:]

#if !APP_EXTENSION
    private var scheduledResumeDate: Date?
#endif

    // Only while the app is in the foreground
    private static let shareRetryDelay: TimeInterval = 30

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
                                                  createdAt: Date(),
                                                  captionMessage: upload.captionMessage,
                                                  captionMessageParameters: upload.captionMessageParameters)

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
        try FileManager.default.copyItem(at: fileURL, to: jobDirectory.appendingPathComponent(job.localFileName))
        try self.save(job)
    }

    private func startUploadTask(for job: ChatBackgroundUploadJob, in session: URLSession, authHeader: String, earliestBeginDate: Date? = nil) {
        guard let url = URL(string: job.serverURL),
              let dataFileURL = self.jobDirectory(forJobId: job.id)?.appendingPathComponent(job.localFileName)
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")

        let task = session.uploadTask(with: request, fromFile: dataFileURL)
        task.taskDescription = job.id
        task.earliestBeginDate = earliestBeginDate
        task.resume()

#if APP_EXTENSION
        let taskStart = ChatBackgroundUploadJob.TaskStart.foreground
#else
        let taskStart: ChatBackgroundUploadJob.TaskStart = UIApplication.shared.applicationState == .active ? .foreground : .background
#endif

        // Saving notifies the chat, so only when it changes
        if job.taskStart != taskStart {
            self.updateJob(withId: job.id) { $0.taskStart = taskStart }
        }
    }

    // MARK: - App

#if !APP_EXTENSION
    /// Returns `false` for sessions that belong to someone else.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        guard identifier.hasPrefix(Self.sessionIdentifierPrefix) else { return false }

        NCLog.log("Handling events of the background upload session \(identifier)")

        self.backgroundEventsCompletionHandlers[identifier] = completionHandler

        // Recreating the session with this identifier is what makes the system deliver its events
        _ = self.session(withIdentifier: identifier)

        return true
    }

    func startResumingPendingJobs() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resumePendingJobs()
        }
    }

    /// Otherwise held back jobs wait until the app becomes active again. The earliest scheduled resume wins.
    private func scheduleResume(after delay: TimeInterval) {
        let resumeDate = Date(timeIntervalSinceNow: delay)

        // An earlier scheduled resume covers this one
        if let scheduledResumeDate = self.scheduledResumeDate, scheduledResumeDate <= resumeDate {
            return
        }

        self.scheduledResumeDate = resumeDate

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.scheduledResumeDate == resumeDate else { return }

            self.scheduledResumeDate = nil

            // Otherwise the next activation or background refresh does it
            guard UIApplication.shared.applicationState == .active else { return }

            self.resumePendingJobs()
        }
    }

    /// Finishes what the system did not launch the app for, for example after a failed post or a force quit.
    /// The completion is called once the posts it started are done. Must be called on the main queue.
    func resumePendingJobs(completion: (() -> Void)? = nil) {
        self.removeOldFailedJobs()

        guard let jobsDirectory = Self.jobsDirectory,
              let jobDirectories = try? FileManager.default.contentsOfDirectory(at: jobsDirectory, includingPropertiesForKeys: [.creationDateKey])
        else {
            completion?()
            return
        }

        let now = Date()
        var sessionsToCheck: Set<String> = []
        var sessionsToShare: Set<String> = []
        var sessionsToConnect: Set<String> = []

        for jobDirectory in jobDirectories {
            let job = self.loadJob(withId: jobDirectory.lastPathComponent)
            let preparedAt = job?.createdAt ?? (try? jobDirectory.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? now
            let isInGracePeriod = Self.isInGracePeriod(since: preparedAt, now: now)

            if isInGracePeriod {
                // Look again once the grace period is over
                self.scheduleResume(after: Self.reconnectGracePeriod - now.timeIntervalSince(preparedAt) + 1)
            }

            guard let job else {
                // Left behind by an extension that was killed while preparing it
                if !isInGracePeriod {
                    try? FileManager.default.removeItem(at: jobDirectory)
                }

                continue
            }

            if now.timeIntervalSince(job.createdAt) > Self.maxJobAge {
                self.drop(job, reason: "it is too old")
            } else if job.uploaded {
                // The extension may still be posting it
                if !isInGracePeriod {
                    sessionsToShare.insert(job.sessionIdentifier)
                }
            } else if isInGracePeriod {
                // Connect for the progress only, the extension may still own the session
                if job.taskStart != nil {
                    sessionsToConnect.insert(job.sessionIdentifier)
                }
            } else {
                let isUnchecked = !self.checkedSessions.contains(job.sessionIdentifier)
                let isRetryDue = (job.uploadRetryDate ?? .distantFuture) <= now
                if isUnchecked || isRetryDue || self.mayBeHeldBack(job) || job.isWaitingForUploadTurn {
                    sessionsToCheck.insert(job.sessionIdentifier)
                }
            }
        }

        for identifier in sessionsToConnect.subtracting(sessionsToCheck) {
            _ = self.session(withIdentifier: identifier)
        }

        let group = DispatchGroup()

        for identifier in sessionsToShare {
            group.enter()
            self.shareFiles(of: identifier) { group.leave() }
        }

        for identifier in sessionsToCheck {
            self.checkedSessions.insert(identifier)

            group.enter()
            self.restartTasks(in: self.session(withIdentifier: identifier)) { group.leave() }
        }

        group.notify(queue: .main) { completion?() }
    }

    // A task the app started while in the background, which it can now start again from the foreground
    private func mayBeHeldBack(_ job: ChatBackgroundUploadJob) -> Bool {
        return job.taskStart == .background && UIApplication.shared.applicationState == .active
    }

    struct UploadTaskSnapshot {
        let isRunning: Bool
        let bytesSent: Int64
        let earliestBeginDate: Date?

        init(_ task: URLSessionTask) {
            self.isRunning = task.state == .running
            self.bytesSent = task.countOfBytesSent
            self.earliestBeginDate = task.earliestBeginDate
        }
    }

    enum UploadTaskRestart: Equatable {
        case keep
        /// Cancels the task the job has, if any, and starts a new one
        case restart(earliestBeginDate: Date?)
    }

    /// What restartTasks does with the upload of a job.
    ///
    /// - Parameter task: Nil when the session has no task for the job, so it was lost.
    static func uploadTaskRestart(for task: UploadTaskSnapshot?, mayBeHeldBack: Bool, isRetriedNow: Bool, now: Date) -> UploadTaskRestart {
        guard let task else { return .restart(earliestBeginDate: nil) }

        // Already sending, nothing to restart
        guard task.isRunning, task.bytesSent == 0 else { return .keep }

        if isRetriedNow {
            return .restart(earliestBeginDate: nil)
        }

        if mayBeHeldBack {
            // Started again from the foreground, a retry that is not due yet keeps its time
            if let earliestBeginDate = task.earliestBeginDate, earliestBeginDate > now {
                return .restart(earliestBeginDate: earliestBeginDate)
            }

            return .restart(earliestBeginDate: nil)
        }

        // A retry the system still holds back after its time
        if let earliestBeginDate = task.earliestBeginDate, earliestBeginDate <= now {
            return .restart(earliestBeginDate: nil)
        }

        return .keep
    }

    /// Restarts lost uploads, retries the system still holds back after their time, and from the foreground the
    /// uploads started in the background.
    ///
    /// - Parameter retryingJobIds: Uploads waiting for their retry that start right away. It still is their one retry.
    private func restartTasks(in session: URLSession, retryingJobIds: Set<String> = [], completion: (() -> Void)? = nil) {
        guard let identifier = session.configuration.identifier else {
            completion?()
            return
        }

        // Nothing is lost when the user asks for a retry
        let delay = retryingJobIds.isEmpty ? Self.lostTaskCheckDelay : 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            session.getAllTasks { tasks in
                DispatchQueue.main.async {
                    // Invalidated in the meantime, as another process is connected to it
                    guard self.sessions[identifier] === session else {
                        completion?()
                        return
                    }

                    let now = Date()

                    // Files waiting for their turn are started by startUploadTurns
                    for var job in self.loadAllJobs() where job.sessionIdentifier == identifier && !job.uploaded && !job.isWaitingForUploadTurn {
                        let isRetriedNow = retryingJobIds.contains(job.id) && job.isWaitingForUploadRetry
                        let task = tasks.first(where: { $0.taskDescription == job.id })
                        let taskSnapshot = task.map(UploadTaskSnapshot.init)

                        guard case .restart(let earliestBeginDate) = Self.uploadTaskRestart(for: taskSnapshot,
                                                                                         mayBeHeldBack: self.mayBeHeldBack(job),
                                                                                         isRetriedNow: isRetriedNow,
                                                                                         now: now)
                        else { continue }

                        // Its cancellation is reported and ignored
                        task?.cancel()

                        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId),
                              let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: account)
                        else {
                            self.drop(job, reason: "its account is gone")
                            continue
                        }

                        if isRetriedNow, let retriedJob = self.updateJob(withId: job.id, { $0.uploadRetryDate = now }) {
                            job = retriedJob
                        }

                        NCLog.log("Restarting background upload of \(job.fileName)")
                        self.startUploadTask(for: job, in: session, authHeader: authHeader, earliestBeginDate: earliestBeginDate)
                    }

                    // No file of the share may be sending anymore, for example after a force quit
                    self.startUploadTurns(in: session, completion: completion)
                }
            }
        }
    }
#endif

    // MARK: - Share

    /// Posts the files of one share in their original order once all of them are uploaded, like the web
    /// does, so the caption on the last one ends the group in the chat.
    private func shareFiles(of sessionIdentifier: String, completion: (() -> Void)? = nil) {
        guard !self.sharingSessions.contains(sessionIdentifier) else {
            completion?()
            return
        }

        let jobs = self.loadAllJobs().filter { $0.sessionIdentifier == sessionIdentifier }.sorted { $0.index < $1.index }

        guard !jobs.isEmpty, jobs.allSatisfy({ $0.uploaded }) else {
            // The last job of the session may just have been dropped
            self.finishSessionIfDone(sessionIdentifier)
            completion?()
            return
        }

        self.sharingSessions.insert(sessionIdentifier)

        let bgTask = BGTaskHelper.startExpiringActivity(withName: "ChatBackgroundUploader.share")

        Task { @MainActor in
            // A file that stays behind for a retry stops the rest, otherwise they would overtake it
            for job in jobs {
                guard await self.post(job) else {
#if !APP_EXTENSION
                    self.scheduleResume(after: Self.shareRetryDelay)
#endif
                    break
                }
            }

            self.sharingSessions.remove(sessionIdentifier)
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
        let earlierPostStarted = job.postStarted
        let job = self.updateJob(withId: job.id) { $0.postStarted = true } ?? job

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

            // An earlier post whose answer got lost already moved the file out of the draft folder
            let response = (error as? NCHTTPResponseError)?.response
            if earlierPostStarted, response?.statusCode == 404 {
                NCLog.log("Background upload \(job.fileName) was already posted")
                self.removeJob(job)
                return true
            }

            if job.shareRetried {
                self.drop(job, reason: "its retry failed as well")
                return true
            }

            // Retried shortly while the app is active, otherwise on its next start or background refresh
            self.updateJob(withId: job.id) { $0.shareRetried = true }

            return false
        }
    }

    private func finishSessionIfDone(_ identifier: String) {
        guard !self.sharingSessions.contains(identifier) else { return }

        let eventsFinished = self.sessionsWithFinishedEvents.remove(identifier) != nil
        // Invalidating the session would stop the events the system is still delivering
        let waitingForEvents = !eventsFinished && self.backgroundEventsCompletionHandlers[identifier] != nil

        if !waitingForEvents, !self.loadAllJobs().contains(where: { $0.sessionIdentifier == identifier }) {
            self.sessions.removeValue(forKey: identifier)?.finishTasksAndInvalidate()
            self.checkedSessions.remove(identifier)
        }

        if eventsFinished {
            self.backgroundEventsCompletionHandlers.removeValue(forKey: identifier)?()
        }
    }

    // MARK: - URLSession

    private func session(withIdentifier identifier: String) -> URLSession {
        if let session = self.sessions[identifier] {
            return session
        }

        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = groupIdentifier
        // Without it, an upload waiting for a network keeps the job alive for 7 days
        configuration.timeoutIntervalForResource = Self.uploadResourceTimeout

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.sessions[identifier] = session

        return session
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let jobId = task.taskDescription, totalBytesExpectedToSend > 0 else { return }

        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)

        // Whole percents are enough for an indicator
        if let previousProgress = self.uploadProgress[jobId], Int(previousProgress * 100) == Int(progress * 100) {
            return
        }

        self.uploadProgress[jobId] = progress

        NotificationCenter.default.post(name: .ChatBackgroundUploaderDidChangeUploadProgress, object: self, userInfo: ["jobId": jobId, "progress": progress])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let jobId = task.taskDescription else { return }

        self.uploadProgress.removeValue(forKey: jobId)

        guard var job = self.loadJob(withId: jobId) else { return }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0

        if error == nil, (200..<300).contains(statusCode) {
            job.uploaded = true
            try? self.save(job)

            self.shareFiles(of: job.sessionIdentifier)
            self.startUploadTurns(in: session)
            return
        }

        NCLog.log("Background upload of \(job.fileName) failed with status \(statusCode). Error: \(error?.localizedDescription ?? "none")")

        // A new task takes over a cancelled one, and another process connected to the session handles the job
        if let code = (error as? URLError)?.code, code == .cancelled || code == .backgroundSessionInUseByAnotherProcess {
            return
        }

        // Retrying all of them together would time out again, and waiting for its turn does not use up its retry
        if statusCode == 408, job.uploadTurn == nil {
            NCLog.log("Sending the files of the share of \(job.fileName) in turns")
            job.uploadTurn = .waiting
            try? self.save(job)

            self.startUploadTurns(in: session)
            return
        }

        let dropReason: String

        // 429 too: the server blocks other requests as well, and rarely within minutes
        if statusCode == 507 || ((400..<500).contains(statusCode) && statusCode != 408) {
            dropReason = "the server rejected it"
        } else if job.uploadRetryDate != nil {
            dropReason = "its retry failed as well"
        } else if let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId),
                  let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: account) {
            let retryDate = Date(timeIntervalSinceNow: Self.uploadRetryDelay)

            job.uploadRetryDate = retryDate
            try? self.save(job)

            // The system starts it then, even when neither the app nor the extension is running
            NCLog.log("Retrying background upload of \(job.fileName) in \(Int(Self.uploadRetryDelay))s")
            self.startUploadTask(for: job, in: session, authHeader: authHeader, earliestBeginDate: retryDate)
            return
        } else {
            dropReason = "its account is gone"
        }

        self.drop(job, reason: dropReason)
        // The other files of the share were waiting for this one
        self.shareFiles(of: job.sessionIdentifier)
        self.startUploadTurns(in: session)
    }

    /// Starts files waiting for their turn while fewer than uploadsPerTurn files of the share are sending.
    private func startUploadTurns(in session: URLSession, completion: (() -> Void)? = nil) {
        guard let identifier = session.configuration.identifier,
              self.loadAllJobs().contains(where: { $0.sessionIdentifier == identifier && $0.isWaitingForUploadTurn })
        else {
            completion?()
            return
        }

        // Otherwise the process may be suspended before the next files are handed to the system
        let bgTask = BGTaskHelper.startExpiringActivity(withName: "ChatBackgroundUploader.turns")

        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                defer {
                    bgTask.stopBackgroundTask()
                    completion?()
                }

                // Invalidated in the meantime, as another process is connected to it
                guard self.sessions[identifier] === session else { return }

                let jobs = self.loadAllJobs().filter { $0.sessionIdentifier == identifier && !$0.uploaded }.sorted { $0.index < $1.index }
                let runningJobIds = Set(tasks.filter { $0.state == .running }.compactMap { $0.taskDescription })

                // Started turns count by their job, as their tasks may be missing from a list fetched before
                let sendingCount = jobs.filter { job in
                    job.uploadTurn == .started || (job.uploadTurn == nil && runningJobIds.contains(job.id))
                }.count

                let waitingJobs = jobs.filter { $0.uploadTurn == .requested } + jobs.filter { $0.uploadTurn == .waiting }

                for job in waitingJobs.prefix(max(Self.uploadsPerTurn - sendingCount, 0)) {
                    guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: job.accountId),
                          let authHeader = NCAPIController.sharedInstance().authHeader(forAccount: account)
                    else {
                        self.drop(job, reason: "its account is gone")
                        self.shareFiles(of: identifier)
                        continue
                    }

                    guard let startedJob = self.updateJob(withId: job.id, { $0.uploadTurn = .started }) else { continue }

                    NCLog.log("Starting background upload of \(job.fileName) in its turn")
                    self.startUploadTask(for: startedJob, in: session, authHeader: authHeader)
                }
            }
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

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        // Sessions invalidated on purpose are no longer cached
        guard let identifier = session.configuration.identifier,
              self.sessions[identifier] === session
        else { return }

        // Another process is connected to the session
        NCLog.log("Background upload session \(identifier) became invalid. Error: \(error?.localizedDescription ?? "none")")
        self.sessions.removeValue(forKey: identifier)
        self.checkedSessions.remove(identifier)
        self.sessionsWithFinishedEvents.remove(identifier)

        // No events come anymore, the other process got them
        self.backgroundEventsCompletionHandlers.removeValue(forKey: identifier)?()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }

        self.sessionsWithFinishedEvents.insert(identifier)
        self.finishSessionIfDone(identifier)
    }

    // MARK: - Failure

    private func drop(_ job: ChatBackgroundUploadJob, reason: String) {
        NCLog.log("Dropping background upload of \(job.fileName), \(reason)")

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Upload failed", comment: "")
        content.body = String.localizedStringWithFormat(NSLocalizedString("%1$@ could not be sent to %2$@", comment: "'photo.jpg' could not be sent to 'Conversation name'"), job.fileName, job.roomName)
        content.threadIdentifier = job.roomToken
        content.sound = .default
        content.attachments = self.notificationAttachment(for: job).map { [$0] } ?? []
        content.userInfo = [
            "localNotificationType": NCLocalNotificationType.failedBackgroundUpload.rawValue,
            "accountId": job.accountId,
            "roomToken": job.roomToken,
            "failedUploadJobId": job.id
        ]

        self.keepFailedJob(job)

#if !APP_EXTENSION
        // The open chat shows the failed file already
        if UIApplication.shared.applicationState == .active,
           let chatViewController = NCRoomsManager.shared.chatViewController, chatViewController.isVisible,
           chatViewController.room.token == job.roomToken, chatViewController.account.accountId == job.accountId {
            return
        }
#endif

        let identifier = "BackgroundUpload-\(job.id)"

        guard let room = NCDatabaseManager.sharedInstance().room(withToken: job.roomToken, forAccountId: job.accountId) else {
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return
        }

        // Keeps the extension running while the avatar loads
        let bgTask = BGTaskHelper.startExpiringActivity(withName: "ChatBackgroundUploader.drop")

        // Shown as a communication notification of the conversation, so it carries the conversation avatar
        NCIntentController.sharedInstance().getInteractionFor(room, withTitle: job.roomName) { sendMessageIntent in
            let updatedContent = sendMessageIntent.flatMap { try? content.updating(from: $0) } ?? content

            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: updatedContent, trigger: nil)) { _ in
                bgTask.stopBackgroundTask()
            }
        }
    }

    /// Kept so the user can share the file again by tapping the notification.
    private func keepFailedJob(_ job: ChatBackgroundUploadJob) {
        guard let jobDirectory = self.jobDirectory(forJobId: job.id),
              let failedJobsDirectory = Self.failedJobsDirectory
        else { return }

        // Not saved through updateJob, so only the move notifies
        if var failedJob = self.loadJob(in: jobDirectory) {
            failedJob.failedAt = Date()
            try? JSONEncoder().encode(failedJob).write(to: jobDirectory.appendingPathComponent(Self.jobFileName), options: .atomic)
        }

        do {
            try FileManager.default.createDirectory(at: failedJobsDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: jobDirectory, to: failedJobsDirectory.appendingPathComponent(job.id, isDirectory: true))
            self.notifyUploadsChanged()
        } catch {
            NCLog.log("Could not keep the failed background upload of \(job.fileName). Error: \(error.localizedDescription)")
            self.removeJob(job)
        }
    }

#if !APP_EXTENSION
    /// The failed files of the share the given job belongs to, in their original order.
    func failedJobs(sharedWith jobId: String) -> [(job: ChatBackgroundUploadJob, fileURL: URL)] {
        let failedUploads = self.loadFailedUploads()

        guard let sharedJob = failedUploads.first(where: { $0.job.id == jobId })?.job else { return [] }

        return failedUploads
            .filter { $0.job.sessionIdentifier == sharedJob.sessionIdentifier }
            .sorted { $0.job.index < $1.job.index }
            .map { ($0.job, $0.fileURL) }
    }

    func removeFailedJobs(_ jobs: [ChatBackgroundUploadJob]) {
        guard let failedJobsDirectory = Self.failedJobsDirectory else { return }

        for job in jobs {
            try? FileManager.default.removeItem(at: failedJobsDirectory.appendingPathComponent(job.id, isDirectory: true))
        }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: jobs.map { "BackgroundUpload-\($0.id)" })

        self.notifyUploadsChanged()
    }

    /// Pending and failed files, except those without a reference id to match their message.
    func uploads(forAccountId accountId: String, roomToken: String, threadId: Int?) -> [ChatBackgroundUpload] {
        return self.shownUploads()
            .filter { $0.job.accountId == accountId && $0.job.roomToken == roomToken }
            .filter { $0.job.metadata.threadId == threadId && $0.job.referenceId != nil }
            .sorted { ($0.job.createdAt, $0.job.index) < ($1.job.createdAt, $1.job.index) }
    }

    /// By room token, only for conversations that have pending or failed files.
    func uploadSummaries(forAccountId accountId: String) -> [String: ChatBackgroundUploadSummary] {
        let uploads = self.shownUploads().filter { $0.job.accountId == accountId }

        func activity(of upload: ChatBackgroundUpload) -> Int {
            return Int((upload.job.failedAt ?? upload.job.createdAt).timeIntervalSince1970)
        }

        return Dictionary(grouping: uploads, by: { $0.job.roomToken }).compactMapValues { roomUploads in
            guard let lastActivity = roomUploads.map(activity(of:)).max() else { return nil }

            let failedUploads = roomUploads.filter { $0.isFailed }

            return ChatBackgroundUploadSummary(pendingState: roomUploads.filter { !$0.isFailed }.map { $0.state }.combined,
                                               failedFileCount: failedUploads.count,
                                               lastFailure: failedUploads.map(activity(of:)).max(),
                                               lastActivity: lastActivity)
        }
    }

    private func shownUploads() -> [ChatBackgroundUpload] {
        let now = Date()

        // Before its tasks start, a share may still fall back to uploading in the foreground
        let startedJobs = self.loadAllJobs().filter {
            $0.taskStart != nil || !Self.isInGracePeriod(since: $0.createdAt, now: now)
        }

        let pendingUploads = startedJobs.compactMap { job in
            self.jobDirectory(forJobId: job.id).map {
                ChatBackgroundUpload(job: job, fileURL: $0.appendingPathComponent(job.localFileName), isFailed: false)
            }
        }

        return pendingUploads + self.loadFailedUploads()
    }

    /// Only known while this process is connected to the session of the job.
    func uploadProgress(forJobId jobId: String) -> Float? {
        return self.uploadProgress[jobId]
    }

    /// Stops the given files and forgets them. Returns the ids of the cancelled ones, as files that are being
    /// posted can't be stopped anymore.
    @discardableResult
    func cancelUploads(withJobIds jobIds: Set<String>) -> Set<String> {
        let jobs = self.loadAllJobs().filter { jobIds.contains($0.id) && !self.sharingSessions.contains($0.sessionIdentifier) }

        for job in jobs {
            NCLog.log("Cancelling background upload of \(job.fileName)")
            self.removeJob(job)
        }

        // Without a connection to the session, the upload still finishes and is ignored then
        for identifier in Set(jobs.map { $0.sessionIdentifier }) {
            guard let session = self.sessions[identifier] else { continue }

            session.getAllTasks { tasks in
                tasks.filter { jobIds.contains($0.taskDescription ?? "") }.forEach { $0.cancel() }
            }

            // A cancelled file frees its turn, which resumePendingJobs leaves alone in the grace period
            self.startUploadTurns(in: session)
        }

        // The rest of a share may have waited for the cancelled files
        self.resumePendingJobs()

        return Set(jobs.map { $0.id })
    }

    /// Starts uploads waiting for their retry now. It is still their one retry.
    func retryWaitingUploads(withJobIds jobIds: Set<String>) {
        let now = Date()

        let waitingJobs = self.loadAllJobs().filter {
            // Within the grace period the extension may still be connected to the session, unless this process is
            let mayBelongToExtension = self.sessions[$0.sessionIdentifier] == nil && Self.isInGracePeriod(since: $0.createdAt, now: now)

            return jobIds.contains($0.id) && $0.isWaitingForUploadRetry && !mayBelongToExtension
        }

        for (identifier, jobs) in Dictionary(grouping: waitingJobs, by: { $0.sessionIdentifier }) {
            self.restartTasks(in: self.session(withIdentifier: identifier), retryingJobIds: Set(jobs.map { $0.id }))
        }
    }

    /// Moves files waiting for their turn to the front. Starting them right away would time out again.
    func requestUploadTurns(forJobIds jobIds: Set<String>) {
        let waitingJobs = self.loadAllJobs().filter { jobIds.contains($0.id) && $0.uploadTurn == .waiting }

        for job in waitingJobs {
            self.updateJob(withId: job.id) { $0.uploadTurn = .requested }
        }

        // Otherwise the process connected to the session starts them on its next turn
        for identifier in Set(waitingJobs.map { $0.sessionIdentifier }) {
            if let session = self.sessions[identifier] {
                self.startUploadTurns(in: session)
            }
        }
    }

    private func loadFailedUploads() -> [ChatBackgroundUpload] {
        guard let failedJobsDirectory = Self.failedJobsDirectory,
              let jobIds = try? FileManager.default.contentsOfDirectory(atPath: failedJobsDirectory.path)
        else { return [] }

        return jobIds.compactMap { jobId in
            let jobDirectory = failedJobsDirectory.appendingPathComponent(jobId, isDirectory: true)

            return self.loadJob(in: jobDirectory).map {
                ChatBackgroundUpload(job: $0, fileURL: jobDirectory.appendingPathComponent($0.localFileName), isFailed: true)
            }
        }
    }

    // The notification may never be tapped
    private func removeOldFailedJobs() {
        guard let failedJobsDirectory = Self.failedJobsDirectory,
              let jobIds = try? FileManager.default.contentsOfDirectory(atPath: failedJobsDirectory.path)
        else { return }

        var removedJob = false

        for jobId in jobIds {
            let jobDirectory = failedJobsDirectory.appendingPathComponent(jobId, isDirectory: true)

            if let job = self.loadJob(in: jobDirectory), Date().timeIntervalSince(job.createdAt) <= Self.maxJobAge {
                continue
            }

            try? FileManager.default.removeItem(at: jobDirectory)
            removedJob = true
        }

        if removedJob {
            self.notifyUploadsChanged()
        }
    }
#endif

    /// A downscaled JPEG of an image file, as the system takes over attached files and limits their size.
    private func notificationAttachment(for job: ChatBackgroundUploadJob) -> UNNotificationAttachment? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ] as CFDictionary

        guard let dataFileURL = self.jobDirectory(forJobId: job.id)?.appendingPathComponent(job.localFileName),
              let imageSource = CGImageSourceCreateWithURL(dataFileURL as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options),
              let jpegData = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8)
        else { return nil }

        let thumbnailURL = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundUpload-\(job.id).jpg")

        guard (try? jpegData.write(to: thumbnailURL, options: .atomic)) != nil else { return nil }

        return try? UNNotificationAttachment(identifier: job.id, url: thumbnailURL)
    }

    // MARK: - Storage

    private static var jobsDirectory: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("BackgroundUploads", isDirectory: true)
    }

    // Outside of the jobs directory, as everything in there is taken as a pending job
    private static var failedJobsDirectory: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("FailedBackgroundUploads", isDirectory: true)
    }

    private func jobDirectory(forJobId jobId: String) -> URL? {
        return Self.jobsDirectory?.appendingPathComponent(jobId, isDirectory: true)
    }

    private func save(_ job: ChatBackgroundUploadJob) throws {
        guard let jobFileURL = self.jobDirectory(forJobId: job.id)?.appendingPathComponent(Self.jobFileName)
        else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

        try JSONEncoder().encode(job).write(to: jobFileURL, options: .atomic)
        self.notifyUploadsChanged()
    }

    /// Changes what is stored rather than a copy, which may be older by now.
    @discardableResult
    private func updateJob(withId jobId: String, _ change: (inout ChatBackgroundUploadJob) -> Void) -> ChatBackgroundUploadJob? {
        guard var job = self.loadJob(withId: jobId) else { return nil }

        change(&job)
        try? self.save(job)

        return job
    }

    private func loadJob(withId jobId: String) -> ChatBackgroundUploadJob? {
        return self.jobDirectory(forJobId: jobId).flatMap { self.loadJob(in: $0) }
    }

    private func loadJob(in jobDirectory: URL) -> ChatBackgroundUploadJob? {
        guard let data = try? Data(contentsOf: jobDirectory.appendingPathComponent(Self.jobFileName))
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
        self.notifyUploadsChanged()
    }

    private func notifyUploadsChanged() {
        let post = { NotificationCenter.default.post(name: .ChatBackgroundUploaderDidChangeUploads, object: self) }

        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
