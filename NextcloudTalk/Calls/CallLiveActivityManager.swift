//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import ActivityKit
import UIKit

// Shows the ongoing call as a Live Activity on the Lock Screen and in the Dynamic Island.
// All methods are expected to be called on the main thread, ActivityKit is only used on the activity queue.
class CallLiveActivityManager {

    static let shared = CallLiveActivityManager()

    private static let avatarFolderName = "LiveActivities"
    private static let avatarSize = CGSize(width: 120, height: 120)

    private weak var callViewController: CallViewController?
    private var roomToken: String?
    private var attributes: CallActivityAttributes?
    private var contentState: CallActivityAttributes.ContentState?

    // ActivityKit waits synchronously for a system service, which must never block the main thread
    private let activityQueue = DispatchQueue(label: "\(groupIdentifier).callLiveActivity")
    // The current Activity<CallActivityAttributes>, only accessed on the activity queue
    private var activity: Any?
    // Updates of the activity run one after another
    private var lastActivityTask: Task<Void, Never>?

    init() {
        // Live Activities can only be started while the app is in the foreground, e.g. not when a call was answered from the Lock Screen
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.requestActivityIfNeeded()
        }
    }

    // MARK: - Actions from the Live Activity

    @MainActor
    func registerActionHandler() {
        CallLiveActivityActionHandler.handler = { [weak self] action, roomToken in
            guard let callViewController = self?.callViewController, callViewController.room.token == roomToken else { return }

            switch action {
            case .toggleAudio:
                callViewController.audioButtonPressed(callViewController)
            case .hangUp:
                callViewController.hangupButtonPressed(callViewController)
            }
        }
    }

    // MARK: - Lifecycle

    func startActivity(for callViewController: CallViewController, isVideoCall: Bool, isAudioMuted: Bool) {
        guard #available(iOS 17.0, *) else { return }

        self.endActivity()

        let room = callViewController.room
        self.callViewController = callViewController
        self.roomToken = room.token
        self.attributes = CallActivityAttributes(roomToken: room.token, roomName: room.displayName, isVideoCall: isVideoCall)
        self.contentState = CallActivityAttributes.ContentState(status: .connecting, isAudioMuted: isAudioMuted)

        self.requestActivityIfNeeded()

        _ = AvatarManager.shared.getAvatar(for: room, with: .dark) { [weak self] image in
            guard let image, let avatarPath = Self.storeAvatar(image, forRoomToken: room.token) else { return }

            DispatchQueue.main.async {
                guard self?.roomToken == room.token else { return }
                self?.updateActivity { $0.avatarPath = avatarPath }
            }
        }
    }

    private func requestActivityIfNeeded() {
        guard #available(iOS 17.0, *), let attributes = self.attributes, let contentState = self.contentState else { return }

        self.activityQueue.async {
            guard self.activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            do {
                self.activity = try Activity.request(attributes: attributes, content: ActivityContent(state: contentState, staleDate: nil), pushType: nil)
            } catch {
                NCLog.log("Failed to start the call Live Activity: \(error.localizedDescription)")
            }
        }
    }

    func updateActivity(_ change: (inout CallActivityAttributes.ContentState) -> Void) {
        guard let currentContentState = self.contentState else { return }

        let contentState = Self.contentState(currentContentState, changedBy: change)
        guard contentState != currentContentState else { return }
        self.contentState = contentState

        guard #available(iOS 17.0, *) else { return }

        self.performOnActivity { activity in
            await activity.update(ActivityContent(state: contentState, staleDate: nil))
        }
    }

    func endActivity(for callViewController: CallViewController) {
        guard self.callViewController === callViewController else { return }

        self.endActivity()
    }

    private func endActivity() {
        if #available(iOS 17.0, *), let finalState = self.contentState {
            self.performOnActivity(andForgetIt: true) { activity in
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
        }

        if let roomToken = self.roomToken {
            Self.removeAvatar(forRoomToken: roomToken)
        }

        self.callViewController = nil
        self.roomToken = nil
        self.attributes = nil
        self.contentState = nil
    }

    // A call can't survive the termination of the app, so Live Activities that are still around at launch are stale
    func endStaleActivities() {
        if let avatarFolderURL = Self.avatarFolderURL() {
            try? FileManager.default.removeItem(at: avatarFolderURL)
        }

        guard #available(iOS 17.0, *) else { return }

        self.activityQueue.async {
            for activity in Activity<CallActivityAttributes>.activities {
                Task {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    @available(iOS 17.0, *)
    private func performOnActivity(andForgetIt forget: Bool = false, _ operation: @escaping (Activity<CallActivityAttributes>) async -> Void) {
        self.activityQueue.async {
            guard let activity = self.activity as? Activity<CallActivityAttributes> else { return }

            if forget {
                self.activity = nil
            }

            let previousTask = self.lastActivityTask
            self.lastActivityTask = Task {
                await previousTask?.value
                await operation(activity)
            }
        }
    }

    // MARK: - Utils

    static func contentState(_ contentState: CallActivityAttributes.ContentState, changedBy change: (inout CallActivityAttributes.ContentState) -> Void, now: Date = Date()) -> CallActivityAttributes.ContentState {
        var changedContentState = contentState
        change(&changedContentState)

        // A call is in progress from the moment someone else joined, even when the server did not tell us the start time
        if changedContentState.status == .inCall, changedContentState.callStartDate == nil {
            changedContentState.callStartDate = now
        }

        return changedContentState
    }

    static func status(for callState: CallState) -> CallActivityAttributes.Status {
        switch callState {
        case .joining, .switchingToAnotherRoom:
            return .connecting
        case .waitingParticipants:
            return .waitingForParticipants
        case .reconnecting:
            return .reconnecting
        case .inCall:
            return .inCall
        @unknown default:
            return .connecting
        }
    }

    static func avatarFolderURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent(avatarFolderName, isDirectory: true)
    }

    static func avatarURL(forRoomToken roomToken: String, in avatarFolderURL: URL? = avatarFolderURL()) -> URL? {
        // Room tokens only contain alphanumeric characters, but don't rely on that for a file name
        guard let fileName = roomToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }

        return avatarFolderURL?.appendingPathComponent("\(fileName).png")
    }

    private static func storeAvatar(_ image: UIImage, forRoomToken roomToken: String) -> String? {
        guard let avatarFolderURL = avatarFolderURL(), let avatarURL = avatarURL(forRoomToken: roomToken, in: avatarFolderURL) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderedImage = UIGraphicsImageRenderer(size: avatarSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: avatarSize))
        }

        do {
            try FileManager.default.createDirectory(at: avatarFolderURL, withIntermediateDirectories: true)
            try renderedImage.pngData()?.write(to: avatarURL, options: .atomic)
        } catch {
            NCLog.log("Failed to store the avatar for the call Live Activity: \(error.localizedDescription)")
            return nil
        }

        return avatarURL.path
    }

    private static func removeAvatar(forRoomToken roomToken: String) {
        guard let avatarURL = avatarURL(forRoomToken: roomToken) else { return }

        try? FileManager.default.removeItem(at: avatarURL)
    }
}
