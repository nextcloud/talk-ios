//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public typealias RoomToken = String

@objcMembers
public class NCRoomController {
    public var userSessionId: String
    public var inCall: Bool
    public var inChat: Bool

    init(userSessionId: String, inCall: Bool, inChat: Bool) {
        self.userSessionId = userSessionId
        self.inCall = inCall
        self.inChat = inChat

        AllocationTracker.shared.addAllocation()
    }

    deinit {
        AllocationTracker.shared.removeAllocation()
    }
}

@objcMembers
class NCRoomsManager: NSObject, CallViewControllerDelegate {

    public static let shared = NCRoomsManager()

    private static let statusCodeNoSessionId = 996
    private static let statusCodeFailedToJoinExternal = 997
    private static let statusCodeShouldIgnoreAttemptButJoinedSuccessfully = 998
    private static let statusCodeIgnoreJoinAttempt = 999

    public var chatViewController: ChatViewController?
    public var callViewController: CallViewController?

    internal var activeRooms = [RoomToken: NCRoomController]()
    internal var joiningAttempts: Int = 0

    private var joiningRoomToken: String?
    private var leavingRoomToken: String?
    private var joiningSessionId: String?
    private var joinRoomTask: URLSessionTask?
    private var leaveRoomTask: URLSessionTask?
    private var upgradeCallToken: String?
    private var pendingToStartCallToken: String?
    private var pendingToStartCallHasVideo: Bool = false
    private var highlightMessageDict: [AnyHashable: Any]?
    private var showThreadPushNotification: NCPushNotification?

    override init() {
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(joinChatWithLocalNotification(notification:)), name: NSNotification.Name.NCLocalNotificationJoinChat, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinChat(notification:)), name: NSNotification.Name.NCPushNotificationJoinChat, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinAudioCallAccepted(notification:)), name: NSNotification.Name.NCPushNotificationJoinAudioCallAccepted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinVideoCallAccepted(notification:)), name: NSNotification.Name.NCPushNotificationJoinVideoCallAccepted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(selectedUserForChat(notification:)), name: NSNotification.Name.NCSelectedUserForChat, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(roomCreated(notification:)), name: NSNotification.Name.NCRoomCreated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(acceptCallForRoom(notification:)), name: NSNotification.Name.CallKitManagerDidAnswerCall, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startCallForRoom(notification:)), name: NSNotification.Name.CallKitManagerDidStartCall, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkForCallUpgrades(notification:)), name: NSNotification.Name.CallKitManagerDidEndCall, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinOrCreateChat(notification:)), name: NSNotification.Name.NCChatViewControllerReplyPrivatelyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinChatOfForwardedMessage(notification:)), name: NSNotification.Name.NCChatViewControllerForwardNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinOrCreateChat(notification:)), name: NSNotification.Name.NCChatViewControllerTalkToUserNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinOrCreateChatWithURL(notification:)), name: NSNotification.Name.NCURLWantsToOpenConversation, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinChatHighlightingMessage(notification:)), name: NSNotification.Name.NCPresentChatHighlightingMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectionStateHasChanged(notification:)), name: NSNotification.Name.NCConnectionStateHasChangedNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Room

    @objc(updateRoomsAndChatsUpdatingUserStatus: onlyLastModified: withCompletionBlock:)
    public func updateRoomsAndChats(updatingUserStatus updateStatus: Bool, onlyLastModified: Bool, withCompletionBlock completion: ((_ error: Error?) -> Void)?) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if onlyLastModified, Int(activeAccount.lastReceivedModifiedSince) == 0 {
            completion?(nil)
            return
        }

        self.updateRooms(updatingUserStatus: updateStatus, onlyLastModified: onlyLastModified) { roomsWithNewMessages, account, error in
            guard error == nil else {
                completion?(error)
                return
            }

            print("Finished rooms update with \(roomsWithNewMessages?.count ?? 0) rooms with new messages")

            // When in low power mode, we only update the conversation list and don't load new messages for each room
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatKeepNotifications, forAccountId: account.accountId) else {
                completion?(nil)
                return
            }

            guard let roomsWithNewMessages else {
                completion?(nil)
                return
            }

            let chatUpdateGroup = DispatchGroup()

            for room in roomsWithNewMessages {
                chatUpdateGroup.enter()

                print("Updating room \(room.internalId)")
                var chatController: NCChatController

                if let activeController = self.chatViewController?.chatController, activeController.room.internalId == room.internalId {
                    chatController = activeController
                } else {
                    chatController = NCChatController(for: room)
                }

                chatController.updateHistoryInBackground { _ in
                    print("Finished updating \(room.internalId)")
                    chatUpdateGroup.leave()
                }
            }

            chatUpdateGroup.notify(queue: .main) {
                // Notify backgroundFetch that we're finished
                completion?(nil)
            }
        }
    }

    // TODO: Can be removed when ObjC is gone
    @objc(updateRoomsUpdatingUserStatus: onlyLastModified:)
    public func updateRooms(updatingUserStatus updateStatus: Bool, onlyLastModified: Bool) {
        self.updateRooms(updatingUserStatus: updateStatus, onlyLastModified: onlyLastModified, withCompletion: nil)
    }

    @objc(updateRoomsUpdatingUserStatus: onlyLastModified: withCompletionBlock:)
    public func updateRooms(updatingUserStatus updateStatus: Bool, onlyLastModified: Bool, withCompletion completion: ((_ roomsWithNewMessage: [NCRoom]?, _ account: TalkAccount, _ error: Error?) -> Void)? = nil) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let lastReceivedModified = Int(activeAccount.lastReceivedModifiedSince) ?? 0
        let modifiedSince = onlyLastModified ? lastReceivedModified : 0

        NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: updateStatus, modifiedSince: modifiedSince) { rooms, error in
            if let error {
                NCUtils.log("Could not update rooms. Error: \(error.localizedDescription)")

                NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRooms, object: self, userInfo: ["error": error])
                completion?([], activeAccount, error)

                return
            }

            guard let rooms else {
                NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRooms, object: self)
                completion?([], activeAccount, nil)
                return
            }

            let realm = RLMRealm.default()
            var roomsWithNewMessages = [NCRoom]()

            let bgTask = BGTaskHelper.startBackgroundTask { _ in
                NCUtils.log("ExpirationHandler called NCUpdateRoomsTransaction, number of rooms \(rooms.count)")
            }

            defer {
                bgTask.stopBackgroundTask()

                NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRooms, object: self)
                completion?(roomsWithNewMessages, activeAccount, nil)
            }

            try? realm.transaction {
                let updateTimestamp = Int(Date().timeIntervalSince1970)

                // Add or update rooms
                for roomDict in rooms {
                    if bgTask.isExpired {
                        roomsWithNewMessages.removeAll()
                        realm.cancelWriteTransaction()
                        return
                    }

                    let roomContainsNewMessages = self.updateRoom(withDict: roomDict, withAccount: activeAccount, withTimestamp: updateTimestamp, withRealm: realm)

                    if roomContainsNewMessages, let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {
                        roomsWithNewMessages.append(room)
                    }
                }

                // Only delete rooms if it was a complete rooms update (not using modifiedSince)
                if !onlyLastModified {
                    // Delete old rooms
                    let roomsQuery = NSPredicate(format: "accountId = %@ AND lastUpdate != %ld", activeAccount.accountId, updateTimestamp)
                    let managedRoomsToBeDeleted = NCRoom.objects(with: roomsQuery)

                    // Delete messages, chat blocks and threads from old rooms
                    for case let managedRoom as NCRoom in managedRoomsToBeDeleted {
                        if bgTask.isExpired {
                            roomsWithNewMessages.removeAll()
                            realm.cancelWriteTransaction()
                            return
                        }

                        let messagesAndBlocksQuery = NSPredicate(format: "accountId = %@ AND token = %@", activeAccount.accountId, managedRoom.token)
                        realm.deleteObjects(NCChatMessage.objects(with: messagesAndBlocksQuery))
                        realm.deleteObjects(NCChatBlock.objects(with: messagesAndBlocksQuery))

                        let threadsQuery = NSPredicate(format: "accountId = %@ AND roomToken = %@", activeAccount.accountId, managedRoom.token)
                        realm.deleteObjects(NCThread.objects(with: threadsQuery))

                        if managedRoom.isFederated {
                            let federatedCapabilities = NSPredicate(format: "accountId = %@ AND remoteServer = %@ AND roomToken = %@", activeAccount.accountId, managedRoom.remoteServer, managedRoom.token)
                            realm.deleteObjects(FederatedCapabilities.objects(with: federatedCapabilities))
                        }
                    }

                    realm.deleteObjects(managedRoomsToBeDeleted)
                }
            }
        }
    }

    public func updateRoom(_ token: String, withCompletionBlock completion: ((_ roomDict: [String: AnyObject]?, _ error: Error?) -> Void)? = nil) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: token) { roomDict, error in
            if let error {
                NCUtils.log("Could not update room. Error: \(error.localizedDescription)")

                NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRoom, object: self, userInfo: ["error": error])
                completion?([:], error as NSError)

                return
            }

            guard let roomDict else {
                NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRoom, object: self)
                completion?([:], nil)

                return
            }

            let realm = RLMRealm.default()
            try? realm.transaction {
                self.updateRoom(withDict: roomDict, withAccount: activeAccount, withTimestamp: Int(Date().timeIntervalSince1970), withRealm: realm)
            }

            var userDict = [String: Any]()

            // TODO: Can be returend from updateRoom(withDict)?
            if let updateRoom = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: activeAccount.accountId) {
                userDict["room"] = updateRoom
            }

            NotificationCenter.default.post(name: .NCRoomsManagerDidUpdateRoom, object: self, userInfo: userDict)
            completion?(roomDict, error)
        }
    }

    @discardableResult
    public func updateRoom(withDict roomDict: [String: Any], withAccount account: TalkAccount, withTimestamp timestamp: Int, withRealm realm: RLMRealm) -> Bool {
        var roomContainsNewMessages = false

        guard let room = NCRoom(dictionary: roomDict, andAccountId: account.accountId)
        else { return false }

        room.lastUpdate = timestamp

        var lastMessage: NCChatMessage?
        let lastMessageDict = roomDict["lastMessage"] as? [AnyHashable: Any]

        if !room.isFederated, let lastMessageDict {
            // TODO: Move handling to NCRoom roomWithDictionary?
            lastMessage = NCChatMessage(dictionary: lastMessageDict, andAccountId: account.accountId)
            room.lastMessageId = lastMessage?.internalId
        }

        if let managedRoom = NCRoom.objects(where: "internalId = %@", room.internalId).firstObject() as? NCRoom {
            if room.lastActivity > managedRoom.lastActivity {
                roomContainsNewMessages = true
            }

            NCRoom.update(managedRoom, with: room)
        } else {
            realm.add(room)
        }

        if let lastMessage, let lastMessageDict, let internalId = lastMessage.internalId {
            if let managedLastMessage = NCChatMessage.objects(where: "internalId = %@", internalId).firstObject() as? NCChatMessage {
                NCChatMessage.update(managedLastMessage, with: lastMessage, isRoomLastMessage: true)
            } else {
                let chatController = NCChatController(for: room)
                chatController?.storeMessages([lastMessageDict], with: realm)
            }
        }

        return roomContainsNewMessages
    }

    private func updateRoom(_ room: NCRoom, withBlock block: @escaping (_ managedRoom: NCRoom) -> Void) {
        let bgTask = BGTaskHelper.startBackgroundTask()
        try? RLMRealm.default().transaction {
            if let managedRoom = NCRoom.objects(where: "internalId = %@", room.internalId).firstObject() as? NCRoom {
                block(managedRoom)
            }
        }
        bgTask.stopBackgroundTask()
    }

    public func updatePendingMessage(_ message: String, forRoom room: NCRoom) {
        self.updateRoom(room) { managedRoom in
            managedRoom.pendingMessage = message
        }
    }

    public func updateLastReadMessage(_ lastReadMessage: Int, forRoom room: NCRoom) {
        self.updateRoom(room) { managedRoom in
            managedRoom.lastReadMessage = lastReadMessage
        }
    }

    public func updateLastCommonReadMessage(_ messageId: Int, forRoom room: NCRoom) {
        self.updateRoom(room) { managedRoom in
            if messageId > managedRoom.lastCommonReadMessage {
                managedRoom.lastCommonReadMessage = messageId
            }
        }
    }

    public func setNoUnreadMessages(forRoom room: NCRoom, withLastMessage lastMessage: NCChatMessage?) {
        self.updateRoom(room) { managedRoom in
            managedRoom.unreadMention = false
            managedRoom.unreadMentionDirect = false
            managedRoom.unreadMessages = 0

            if let lastMessage, !room.isSensitive {
                managedRoom.lastMessageId = lastMessage.internalId
                managedRoom.lastActivity = lastMessage.timestamp
            }
        }
    }

    public func deleteRoom(withConfirmation room: NCRoom, withStartedBlock startedBlock: (() -> Void)? = nil, withFinishedBlock finishedBlock: ((_ success: Bool) -> Void)? = nil) {
        self.deleteRoom(withConfirmation: room, withTitle: NSLocalizedString("Delete conversation", comment: ""), withMessage: room.deletionMessage, withKeepOption: false, withStartedBlock: startedBlock, withFinishedBlock: finishedBlock)
    }

    public func deleteEventRoomWithConfirmationAfterCall(_ room: NCRoom) {
        var title = NSLocalizedString("Delete conversation", comment: "")
        var message = NSLocalizedString("The call for this event ended. Do you want to delete this conversation for everyone?", comment: "")

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        let retentionEvent = serverCapabilities?.retentionEvent ?? 0
        let isRetentionEnabled = retentionEvent > 0

        if isRetentionEnabled {
            title = NSLocalizedString("Do you want to delete this conversation?", comment: "")
            message = String.localizedStringWithFormat("This conversation will be automatically deleted for everyone in %ld days of no activity.", retentionEvent)

        }

        self.deleteRoom(withConfirmation: room, withTitle: title, withMessage: message, withKeepOption: isRetentionEnabled, withStartedBlock: nil, withFinishedBlock: nil)
    }

    private func deleteRoom(withConfirmation room: NCRoom, withTitle title: String, withMessage message: String, withKeepOption keepOption: Bool, withStartedBlock startedBlock: (() -> Void)?, withFinishedBlock finishedBlock: ((_ success: Bool) -> Void)?) {
        let confirmDialog = UIAlertController(title: title, message: message, preferredStyle: .alert)

        if keepOption {
            let keepAction = UIAlertAction(title: NSLocalizedString("Keep", comment: ""), style: .default) { _ in
                startedBlock?()

                let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                NCAPIController.sharedInstance().unbindRoomFromObject(room.token, forAccount: activeAccount) { error in
                    if let error {
                        print("Error unbinding room from object: \(error.localizedDescription)")
                    }

                    finishedBlock?(error == nil)
                }
            }

            confirmDialog.addAction(keepAction)
        }

        // Delete option
        let deleteTitle = keepOption ?
        NSLocalizedString("Delete now", comment: "Delete a conversation right now without waiting for auto-deletion") :
        NSLocalizedString("Delete", comment: "")

        let confirmAction = UIAlertAction(title: deleteTitle, style: .destructive) { _ in
            NCUserInterfaceController.sharedInstance().presentConversationsList()

            startedBlock?()

            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            NCAPIController.sharedInstance().deleteRoom(room.token, forAccount: activeAccount) { error in
                if let error {
                    print("Error deleting room: \(error.localizedDescription)")
                }

                self.updateRooms(updatingUserStatus: true, onlyLastModified: false)

                finishedBlock?(error == nil)
            }
        }

        confirmDialog.addAction(confirmAction)

        // Cancel option
        let cancelTitle = keepOption ? NSLocalizedString("Dismiss", comment: "") : NSLocalizedString("Cancel", comment: "")

        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel)
        confirmDialog.addAction(cancelAction)

        NCUserInterfaceController.sharedInstance().presentAlertViewController(confirmDialog)
    }

    // MARK: - Chat

    public func startChat(inRoom room: NCRoom) {
        guard self.callViewController == nil else {
            print("Not starting chat due to in a call.")
            return
        }

        guard let roomToken = room.token else {
            print("Trying to start a chat in a room, without a token")
            return
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if self.activeRooms[roomToken] != nil {
            // Workaround until external signaling supports multi-room
            if let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId) {
                let currentRoom = extSignalingController.currentRoom

                if currentRoom != roomToken {
                    // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                    // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                    // is no longer the room we want to leave (so no message is sent to the external signaling server).
                    extSignalingController.currentRoom = nil
                }
            }
        }

        if chatViewController == nil || chatViewController?.room.token != roomToken {
            print("Creating new chat view controller.")
            self.chatViewController = ChatViewController(forRoom: room, withAccount: activeAccount)

            // Highlight message
            if let highlightToken = self.highlightMessageDict?["token"] as? String, highlightToken == roomToken {
                if let messageId = self.highlightMessageDict?[intForKey: "messageId"] {
                    self.chatViewController?.highlightMessageId = messageId
                    self.highlightMessageDict = nil
                }
            }

            // Open thread view on appear
            if let showThreadPushNotification, showThreadPushNotification.roomToken == roomToken {
                self.chatViewController?.presentThreadOnAppear = showThreadPushNotification.threadId
                self.showThreadPushNotification = nil
            }

            NCUserInterfaceController.sharedInstance().present(chatViewController)
        } else {
            print("Not creating new chat room: chatViewController for room \(roomToken) does already exist.")

            // Open thread view on appear
            if let showThreadPushNotification, showThreadPushNotification.roomToken == roomToken {
                self.chatViewController?.presentThreadView(for: showThreadPushNotification.threadId)
                self.showThreadPushNotification = nil

                // Still make sure the current room is highlighted
                NCUserInterfaceController.sharedInstance().roomsTableViewController.selectedRoomToken = roomToken
            }
        }
    }

    public func startChat(withRoomToken token: String) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if let room = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: activeAccount.accountId) {
            self.startChat(inRoom: room)
        } else {
            // TODO: Show spinner
            NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: token) { roomDict, error in
                guard error == nil else { return }

                if let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {
                    self.startChat(inRoom: room)
                }
            }
        }
    }

    public func leaveChat(inRoom token: String) {
        self.activeRooms[token]?.inChat = false
        self.leaveRoom(token)
    }

    // MARK: - Call

    public func startCall(withVideo video: Bool, inRoom room: NCRoom, withVideoEnabled videoEnabled: Bool, asInitiator initiator: Bool, silently: Bool, withRecordingConsent recordingConsent: Bool, withVoiceChatMode voiceChatMode: Bool) {
        guard self.callViewController == nil else {
            print("Not starting call due to in another call.")
            return
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let callViewController = CallViewController(for: room, asUser: activeAccount.userDisplayName, audioOnly: !video)
        self.callViewController = callViewController

        callViewController.videoDisabledAtStart = !videoEnabled
        callViewController.voiceChatModeAtStart = voiceChatMode
        callViewController.initiator = initiator
        callViewController.silentCall = silently
        callViewController.recordingConsent = recordingConsent
        callViewController.modalTransitionStyle = .crossDissolve
        callViewController.delegate = self

        let chatViewControllerRoomToken = self.chatViewController?.room.token
        let joiningRoomToken = room.token

        // Workaround until external signaling supports multi-room
        if let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId) {
            let extSignalingRoomToken = extSignalingController.currentRoom

            if extSignalingRoomToken != joiningRoomToken {
                // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                // is no longer the room we want to leave (so no message is sent to the external signaling server).
                extSignalingController.currentRoom = nil
            }

            // Make sure the external signaling contoller is connected.
            // Could be that the call has been received while the app was inactive or in the background,
            // so the external signaling controller might be disconnected at this point.
            if extSignalingController.disconnected {
                extSignalingController.forceConnect()
            }
        }

        if let chatViewController {
            if chatViewControllerRoomToken == joiningRoomToken {
                // We're in the chat of the room we want to start a call, so stop chat for now
                chatViewController.stopChat()
            } else {
                // We're in a different chat, so make sure we leave the chat and go back to the conversation list
                chatViewController.leaveChat()
                NCUserInterfaceController.sharedInstance().presentConversationsList()
            }
        }

        NCUserInterfaceController.sharedInstance().present(callViewController) {
            self.joinRoom(room.token, forCall: true)
        }
    }

    public func joinCall(withCallToken token: String, withVideo video: Bool, asInitiator initiator: Bool, recordingConsent: Bool) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: token) { roomDict, error in
            guard error == nil else { return }

            if let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {
                CallKitManager.sharedInstance().startCall(room.token, withVideoEnabled: video, andDisplayName: room.displayName, asInitiator: initiator, silently: true, recordingConsent: recordingConsent, withAccountId: activeAccount.accountId)
            }
        }
    }

    public func startCall(withToken token: String, withVideo video: Bool, enabledAtStart videoEnabled: Bool, asInitiator initiator: Bool, silently: Bool, recordingConsent: Bool, withVoiceChatMode voiceChatMode: Bool) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: token) { roomDict, error in
            guard error == nil else { return }

            if let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {
                self.startCall(withVideo: video, inRoom: room, withVideoEnabled: videoEnabled, asInitiator: initiator, silently: silently, withRecordingConsent: recordingConsent, withVoiceChatMode: voiceChatMode)
            }
        }
    }

    public func isCallOngoing(withCallToken token: String) -> Bool {
        guard let callViewController = self.callViewController else { return false }

        return callViewController.room.token == token
    }

    public var areThereActiveCalls: Bool {
        return self.activeRooms.values.contains(where: { $0.inCall })
    }

    public func checkForPendingToStartCalls() {
        if let pendingToStartCallToken = self.pendingToStartCallToken {
            // Pending calls can only happen when answering a new call. That's why we start with video disabled at start and in voice chat mode.
            // We also can start call silently because we are joining an already started call so no need to notify.
            self.startCall(withToken: pendingToStartCallToken, withVideo: pendingToStartCallHasVideo, enabledAtStart: false, asInitiator: false, silently: true, recordingConsent: false, withVoiceChatMode: true)
            self.pendingToStartCallToken = nil
        }
    }

    public func upgradeCallToVideoCall(forRoom room: NCRoom) {
        guard let roomToken = room.token else { return }

        if let roomController = activeRooms[roomToken] {
            roomController.inCall = false
        }

        self.upgradeCallToken = roomToken
        CallKitManager.sharedInstance().endCall(roomToken, withStatusCode: 0)
    }

    // MARK: - Switch to

    public func prepareSwitchToAnotherRoom(fromRoom token: String, withCompletionBlock completionBlock: @escaping (_ error: Error?) -> Void) {
        if self.chatViewController?.room.token == token {
            self.chatViewController?.leaveChat()
            NCUserInterfaceController.sharedInstance().popToConversationsList()
        }

        // Remove room controller and exit rooms
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if self.activeRooms[token] != nil {
            self.activeRooms.removeValue(forKey: token)
            NCAPIController.sharedInstance().exitRoom(token, forAccount: activeAccount) { error in
                completionBlock(error)
            }
        } else {
            print("Couldn't find a room controller from the room we are switching from")
            completionBlock(nil)
        }
    }

    // MARK: CallViewControllerDelegate

    func callViewControllerWantsToBeDismissed(_ viewController: CallViewController) {
        guard self.callViewController == viewController else { return }

        if !viewController.isBeingDismissed {
            viewController.dismiss(animated: true)
        }
    }

    func callViewControllerWantsVideoCallUpgrade(_ viewController: CallViewController) {
        guard self.callViewController == viewController else { return }

        if let room = self.callViewController?.room {
            self.callViewController = nil
            self.upgradeCallToVideoCall(forRoom: room)
        }
    }

    func callViewController(_ viewController: CallViewController, wantsToSwitchFromRoom from: String, toRoom to: String) {
        guard self.callViewController == viewController else { return }

        CallKitManager.sharedInstance().switchCall(from: from, toCall: to)
    }

    func callViewControllerDidFinish(_ viewController: CallViewController) {
        guard self.callViewController == viewController,
              let roomToken = viewController.room.token
        else { return }

        let room = viewController.room

        self.callViewController = nil
        self.activeRooms[roomToken]?.inCall = false
        self.leaveRoom(roomToken)

        CallKitManager.sharedInstance().endCall(roomToken, withStatusCode: 0)

        if let chatViewController, chatViewController.room.token == roomToken {
            chatViewController.resumeChat()
        }

        // Keep connection alive temporarily when a call was finished while the app in the background
        if UIApplication.shared.applicationState == .background {
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
            appDelegate?.keepExternalSignalingConnectionAliveTemporarily()
        }

        // If this is an event room and we are a moderator, we allow direct deletion
        if room.canModerate, room.isEvent {
            self.deleteEventRoomWithConfirmationAfterCall(room)
        }
    }

    // MARK: - Notifications

    func checkForCallUpgrades(notification: Notification) {
        guard let upgradeCallToken else { return }
        let token = upgradeCallToken
        self.upgradeCallToken = nil

        // Add some delay so CallKit doesn't fail requesting new call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.joinCall(withCallToken: token, withVideo: true, asInitiator: false, recordingConsent: true)
        }
    }

    private func checkForAccountChange(_ accountId: String?) {
        guard let accountId else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if activeAccount.accountId == accountId {
            // Leave chat before changing accounts
            self.chatViewController?.leaveChat()
        }
        // Set notification account active
        NCSettingsController.sharedInstance().setActiveAccountWithAccountId(accountId)
    }

    func acceptCallForRoom(notification: Notification) {
        guard let roomToken = notification.userInfo?[stringForKey: "roomToken"],
              let waitForcallEnd = notification.userInfo?[boolForKey: "waitForCallEnd"],
              let hasVideo = notification.userInfo?[boolForKey: "hasVideo"]
        else { return }

        let activeCalls = self.areThereActiveCalls

        if !waitForcallEnd || (!activeCalls && leaveRoomTask == nil) {
            // Calls that have been answered start with video disabled by default, in voice chat mode and silently (without notification).
            self.startCall(withToken: roomToken, withVideo: hasVideo, enabledAtStart: false, asInitiator: false, silently: true, recordingConsent: false, withVoiceChatMode: true)
        } else {
            self.pendingToStartCallToken = roomToken
            self.pendingToStartCallHasVideo = hasVideo
        }
    }

    func startCallForRoom(notification: Notification) {
        guard let roomToken = notification.userInfo?[stringForKey: "roomToken"],
              let isVideoEnabled = notification.userInfo?[boolForKey: "isVideoEnabled"],
              let initiator = notification.userInfo?[boolForKey: "initiator"],
              let silentCall = notification.userInfo?[boolForKey: "silentCall"],
              let recordingConsent = notification.userInfo?[boolForKey: "recordingConsent"]
        else { return }

        self.startCall(withToken: roomToken, withVideo: isVideoEnabled, enabledAtStart: true, asInitiator: initiator, silently: silentCall, recordingConsent: recordingConsent, withVoiceChatMode: false)
    }

    func joinAudioCallAccepted(notification: Notification) {
        guard let pushNotification = notification.userInfo?["pushNotification"] as? NCPushNotification
        else { return }

        self.checkForAccountChange(pushNotification.accountId)
        self.joinCall(withCallToken: pushNotification.roomToken, withVideo: false, asInitiator: false, recordingConsent: false)
    }

    func joinVideoCallAccepted(notification: Notification) {
        guard let pushNotification = notification.userInfo?["pushNotification"] as? NCPushNotification
        else { return }

        self.checkForAccountChange(pushNotification.accountId)
        self.joinCall(withCallToken: pushNotification.roomToken, withVideo: true, asInitiator: false, recordingConsent: false)
    }

    func joinChat(notification: Notification) {
        guard let pushNotification = notification.userInfo?["pushNotification"] as? NCPushNotification
        else { return }

        self.checkForAccountChange(pushNotification.accountId)

        if pushNotification.threadId > 0 {
            self.showThreadPushNotification = pushNotification
        }

        self.startChat(withRoomToken: pushNotification.roomToken)
    }

    func joinOrCreateChat(withUser userId: String, usingAccountId accountId: String) {
        let accountRooms = NCDatabaseManager.sharedInstance().roomsForAccountId(accountId, withRealm: nil)

        if let room = accountRooms.first(where: { $0.type == .oneToOne && $0.name == userId }) {
            // Room already exists -> join the room
            self.startChat(inRoom: room)
            return
        }

        // Did not find a one-to-one room for this user -> create a new one
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: userId, ofType: .oneToOne, andName: nil) { room, error in
            guard error == nil, let room else {
                print("Failed creating room with \(userId)")
                return
            }

            self.startChat(withRoomToken: room.token)
        }
    }

    func joinOrCreateChat(notification: Notification) {
        guard let actorId = notification.userInfo?[stringForKey: "actorId"]
        else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        self.joinOrCreateChat(withUser: actorId, usingAccountId: activeAccount.accountId)
    }

    func joinOrCreateChatWithURL(notification: Notification) {
        guard let accountId = notification.userInfo?[stringForKey: "accountId"]
        else { return }

        let withUser = notification.userInfo?[stringForKey: "withUser"]
        let roomToken = notification.userInfo?[stringForKey: "withRoomToken"]

        self.checkForAccountChange(accountId)

        if let withUser {
            self.joinOrCreateChat(withUser: withUser, usingAccountId: accountId)
        } else if let roomToken {
            self.startChat(withRoomToken: roomToken)
        }
    }

    func joinChatOfForwardedMessage(notification: Notification) {
        guard let accountId = notification.userInfo?[stringForKey: "accountId"],
              let roomToken = notification.userInfo?[stringForKey: "token"]
        else { return }

        self.checkForAccountChange(accountId)
        self.startChat(withRoomToken: roomToken)
    }

    func joinChatWithLocalNotification(notification: Notification) {
        guard let accountId = notification.userInfo?[stringForKey: "accountId"],
              let roomToken = notification.userInfo?[stringForKey: "roomToken"]
        else { return }

        self.checkForAccountChange(accountId)
        self.startChat(withRoomToken: roomToken)

        // In case this notification occurred because of a failed chat-sending event, make sure the text is not lost
        // Note: This will override any stored pending message
        if let responseUserText = notification.userInfo?[stringForKey: "responseUserText"], let chatViewController {
            chatViewController.setChatMessage(responseUserText)
        }
    }

    func joinChatHighlightingMessage(notification: Notification) {
        guard let roomToken = notification.userInfo?[stringForKey: "token"]
        else { return }

        self.highlightMessageDict = notification.userInfo
        self.startChat(withRoomToken: roomToken)
    }

    func selectedUserForChat(notification: Notification) {
        guard let roomToken = notification.userInfo?[stringForKey: "token"]
        else { return }

        self.startChat(withRoomToken: roomToken)
    }

    func roomCreated(notification: Notification) {
        guard let roomToken = notification.userInfo?[stringForKey: "token"]
        else { return }

        self.startChat(withRoomToken: roomToken)
    }

    func connectionStateHasChanged(notification: Notification) {
        guard let rawConnectionState = notification.userInfo?["connectionState"] as? Int,
              let connectionState = ConnectionState(rawValue: rawConnectionState)
        else { return }

        // Try to send offline message when the connection state changes to connected again
        if connectionState == .connected {
            self.resendOfflineMessagesWithCompletionBlock(nil)
        }
    }

    // MARK: - Join/Leave room

    public func joinRoom(_ token: String, forCall call: Bool) {
        NCUtils.log("Joining room \(token) for call \(call)")

        // Clean up joining room flag and attempts
        self.joiningRoomToken = nil
        self.joiningSessionId = nil
        self.joiningAttempts = 0
        self.joinRoomTask?.cancel()

        // Check if we try to join a room, we're still trying to leave
        if self.isLeavingRoom(withToken: token) {
            self.leaveRoomTask?.cancel()

            self.leaveRoomTask = nil
            self.leavingRoomToken = nil
        }

        self.joinRoomHelper(token, forCall: call)
    }

    private func joinRoomHelper(_ token: String, forCall call: Bool) {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["token"] = token

        if let roomController = self.activeRooms[token] {
            NCUtils.log("JoinRoomHelper: Found active room controller")

            if call {
                roomController.inCall = true
            } else {
                roomController.inChat = true
            }

            userInfo["roomController"] = roomController
            NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)

            return
        }

        self.joiningRoomToken = token

        self.joinRoomHelper(token, forCall: call) { sessionId, room, error, statusCode, statusReason in
            if statusCode == NCRoomsManager.statusCodeIgnoreJoinAttempt {
                // Not joining the room any more. Ignore response
                return
            } else if statusCode == NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully {
                // We joined the Nextcloud server successfully, but locally we are not trying to join that room anymore.
                // We need to make sure that we leave the room on the server again to not leave an active session.
                // Do a direct API call here, as the join method will check for an active NCRoomController, which we don't have

                if !self.isLeavingRoom(withToken: token) {
                    self.leavingRoomToken = token

                    let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                    self.leaveRoomTask = NCAPIController.sharedInstance().exitRoom(token, forAccount: activeAccount, completionBlock: { _ in
                        self.leaveRoomTask = nil
                        self.leavingRoomToken = nil
                    })
                }

                return
            }

            if error == nil, let sessionId {
                let controller = NCRoomController(userSessionId: sessionId, inCall: call, inChat: !call)
                userInfo["roomController"] = controller

                if let room {
                    userInfo["room"] = room
                }

                // Set room as active
                self.activeRooms[token] = controller
            } else {
                if self.joiningAttempts < 3 && statusCode != 403 {
                    NCUtils.log("Error joining room, retrying. \(self.joiningAttempts)")
                    self.joiningAttempts += 1
                    self.joinRoomHelper(token, forCall: call)
                    return
                }

                // Add error to user info
                userInfo["error"] = error
                userInfo["statusCode"] = statusCode
                userInfo["errorReason"] = self.getJoinRoomErrorReason(statusCode, andReason: statusReason)

                if statusCode == 403, statusReason == "ban" {
                    userInfo["isBanned"] = true
                }

                NCUtils.log("Could not join room. Status code: \(statusCode). Error: \(error?.localizedDescription ?? "")")
            }

            self.joiningRoomToken = nil
            self.joiningSessionId = nil
            NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)
        }
    }

    private func isJoiningRoom(withToken token: String) -> Bool {
        guard let joiningRoomToken = self.joiningRoomToken else { return false }

        return joiningRoomToken == token
    }

    private func isLeavingRoom(withToken token: String) -> Bool {
        guard let leavingRoomToken = self.leavingRoomToken else { return false }

        return leavingRoomToken == token
    }

    private func isJoiningRoom(withSessionId sessionId: String) -> Bool {
        guard let joiningSessionId = self.joiningSessionId else { return false }

        return joiningSessionId == sessionId
    }

    private func joinRoomHelper(_ token: String, forCall call: Bool, completionBlock: @escaping (_ sessionId: String?, _ room: NCRoom?, _ error: Error?, _ statusCode: Int, _ statusReason: String?) -> Void) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        self.joinRoomTask = NCAPIController.sharedInstance().joinRoom(token, forAccount: activeAccount, completionBlock: { sessionId, room, error, statusCode, statusReason in
            if !self.isJoiningRoom(withToken: token) {
                // Treat a cancelled request as success, as we can't determine if the request was processed on the server or not
                if let error = error as? NSError, error.code != NSURLErrorCancelled {
                    NCUtils.log("Not joining the room any more. Ignore attempt as the join request failed anyway.")
                    completionBlock(nil, nil, nil, NCRoomsManager.statusCodeIgnoreJoinAttempt, nil)
                } else {
                    NCUtils.log("Not joining the room any more, but our join request was successful.")
                    completionBlock(nil, nil, nil, NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully, nil)
                }

                return
            }

            // Failed to join room in NC
            if let error {
                completionBlock(nil, nil, error, statusCode, statusReason)
                return
            }

            // While we received a successful http status code, we did not receive a sessionId -> treat it as an error
            guard let sessionId else {
                let error = NSError(domain: NSCocoaErrorDomain, code: NCRoomsManager.statusCodeNoSessionId)
                completionBlock(nil, nil, error, NCRoomsManager.statusCodeNoSessionId, nil)
                return
            }

            NCUtils.log("Joined room \(token) in NC successfully")

            // Remember the latest sessionId we're using to join a room, to be able to check when joining the external signaling server
            self.joiningSessionId = sessionId

            self.getExternalSignalingHelper(for: activeAccount, forRoom: token) { extSignalingController, signalingSettings, error in
                guard error == nil else {
                    // There was an error to ensure we have the correct signaling settings for joining a federated conversation
                    completionBlock(nil, nil, nil, NCRoomsManager.statusCodeFailedToJoinExternal, nil)
                    return
                }

                guard let extSignalingController else {
                    // Joined room in NC successfully and no external signaling server configured.
                    completionBlock(sessionId, room, nil, 0, nil)
                    return
                }

                NCUtils.log("Trying to join room \(token) in external signaling server...")

                let federation = signalingSettings?.getFederationJoinDictionary()

                extSignalingController.joinRoom(withRoomId: token, withSessionId: sessionId, withFederation: federation) { error in
                    // If the sessionId is not the same anymore we tried to join with, we either already left again before
                    // joining the external signaling server succeeded, or we already have another join in process
                    if !self.isJoiningRoom(withToken: token) {
                        NCUtils.log("Not joining the room any more. Ignore external signaling completion block, but we joined the Nextcloud instance before.")
                        completionBlock(nil, nil, nil, NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully, nil)
                        return
                    }

                    if !self.isJoiningRoom(withSessionId: sessionId) {
                        NCUtils.log("Joining the same room with a different sessionId. Ignore external signaling completion block.")
                        completionBlock(nil, nil, nil, NCRoomsManager.statusCodeIgnoreJoinAttempt, nil)
                        return
                    }

                    if error == nil {
                        NCUtils.log("Joined room \(token) in external signaling server successfully.")
                        completionBlock(sessionId, room, nil, 0, nil)
                    } else {
                        NCUtils.log("Failed joining room \(token) in external signaling server.")
                        completionBlock(nil, nil, error, statusCode, statusReason)
                    }
                }
            }
        })
    }

    private func getExternalSignalingHelper(for account: TalkAccount, forRoom token: String, withCompletion completion: @escaping (NCExternalSignalingController?, SignalingSettings?, Error?) -> Void) {
        let room = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: account.accountId)

        guard room?.supportsFederatedCalling ?? false else {
            // No federated room -> just ensure that we have a signaling configuration and a potential external signaling controller
            NCSettingsController.sharedInstance().ensureSignalingConfiguration(forAccountId: account.accountId, with: nil) { extSignalingController in
                completion(extSignalingController, nil, nil)
            }

            return
        }

        // This is a federated conversation (with federated calling supported), so we require signaling settings for joining
        // the external signaling controller
        NCAPIController.sharedInstance().getSignalingSettings(for: account, forRoom: token) { signalingSettings, _ in
            guard let signalingSettings else {
                // We need to fail if we are unable to get signaling settings for a federation conversation
                completion(nil, nil, NSError(domain: NSCocoaErrorDomain, code: 0))
                return
            }

            NCSettingsController.sharedInstance().ensureSignalingConfiguration(forAccountId: account.accountId, with: signalingSettings) { extSignalingController in
                completion(extSignalingController, signalingSettings, nil)
            }
        }
    }

    public func rejoinRoomForCall(_ token: String, completionBlock: @escaping (_ sessionId: String?, _ room: NCRoom?, _ error: Error?, _ statusCode: Int, _ statusReason: String?) -> Void) {
        NCUtils.log("Rejoining room \(token)")

        guard let roomController = self.activeRooms[token] else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        self.joiningRoomToken = token
        self.joinRoomTask = NCAPIController.sharedInstance().joinRoom(token, forAccount: activeAccount, completionBlock: { sessionId, room, error, statusCode, statusReason in
            if error == nil, let sessionId {
                roomController.userSessionId = sessionId
                roomController.inCall = true

                self.getExternalSignalingHelper(for: activeAccount, forRoom: token) { extSignalingController, signalingSettings, error in
                    guard error == nil else {
                        // There was an error to ensure we have the correct signaling settings for joining a federated conversation
                        completionBlock(nil, nil, nil, NCRoomsManager.statusCodeFailedToJoinExternal, nil)
                        return
                    }

                    guard let extSignalingController else {
                        // Joined room in NC successfully and no external signaling server configured.
                        completionBlock(sessionId, room, nil, 0, nil)
                        return
                    }

                    let federation = signalingSettings?.getFederationJoinDictionary()

                    extSignalingController.joinRoom(withRoomId: token, withSessionId: sessionId, withFederation: federation) { error in
                        if error == nil {
                            NCUtils.log("Re-Joined room \(token) in external signaling server successfully.")
                            completionBlock(sessionId, room, nil, 0, nil)
                        } else {
                            NCUtils.log("Failed re-joining room \(token) in external signaling server.")
                            completionBlock(nil, nil, error, statusCode, statusReason)
                        }
                    }
                }
            } else {
                NCUtils.log("Could not re-join room \(token). Status code: \(statusCode). Error: \(error?.localizedDescription ?? "Unknown")")
                completionBlock(nil, nil, error, statusCode, statusReason)
            }

            self.joiningRoomToken = nil
            self.joiningSessionId = nil
        })
    }

    public func leaveRoom(_ token: String) {
        // Check if leaving the room we are joining
        if self.isJoiningRoom(withToken: token) {
            NCUtils.log("Leaving room \(token), but still joining -> cancel")

            self.joiningRoomToken = nil
            self.joiningSessionId = nil
            self.joinRoomTask?.cancel()
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Remove room controller and exit room
        if let roomController = self.activeRooms[token], !roomController.inCall, !roomController.inChat {

            self.activeRooms.removeValue(forKey: token)

            self.leavingRoomToken = token
            self.leaveRoomTask = NCAPIController.sharedInstance().exitRoom(token, forAccount: activeAccount, completionBlock: { error in
                var userInfo = [:]
                userInfo["token"] = token

                self.leaveRoomTask = nil
                self.leavingRoomToken = nil

                if let error {
                    userInfo["error"] = error
                    print("Could not exit room. Error: \(error.localizedDescription)")
                } else {
                    if let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId) {
                        extSignalingController.leaveRoom(withRoomId: token)
                    }

                    self.checkForPendingToStartCalls()
                }

                NotificationCenter.default.post(name: .NCRoomsManagerDidLeaveRoom, object: self, userInfo: userInfo)
            })
        } else {
            self.checkForPendingToStartCalls()
        }
    }

    private func getJoinRoomErrorReason(_ statusCode: Int, andReason statusReason: String?) -> String {
        var errorReason = ""

        switch statusCode {
        case 0:
            errorReason = NSLocalizedString("No response from server", comment: "")
        case 403:
            if statusReason == "ban" {
                errorReason = NSLocalizedString("No permission to join this conversation", comment: "")
            } else {
                errorReason = NSLocalizedString("The password is wrong", comment: "")
            }
        case 404:
            errorReason = NSLocalizedString("Conversation not found", comment: "")
        case 409:
            // Currently not triggered, needs to be enabled in API with sending force=false
            errorReason = NSLocalizedString("Duplicate session", comment: "")
        case 422:
            errorReason = NSLocalizedString("Remote server is unreachable", comment: "")
        case 503:
            errorReason = NSLocalizedString("Server is currently in maintenance mode", comment: "")
        default:
            errorReason = NSLocalizedString("Unknown error occurred", comment: "")
        }

        return errorReason
    }

    // MARK: - Room

    public func resendOfflineMessagesWithCompletionBlock(_ block: (() -> Void)?) {
        // Try to send offline messages for all rooms
        self.resendOfflineMessages(forToken: nil, withCompletionBlock: block)
    }

    public func resendOfflineMessages(forToken token: String?, withCompletionBlock completionBlock: (() -> Void)?) {
        var query: NSPredicate

        if let token {
            query = NSPredicate(format: "isOfflineMessage = true AND token = %@", token)
        } else {
            query = NSPredicate(format: "isOfflineMessage = true")
        }

        let realm = RLMRealm.default()
        let managedTemporaryMessages = NCChatMessage.objects(with: query)
        let twelveHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (60 * 60 * 12))

        for case let offlineMessage as NCChatMessage in managedTemporaryMessages {
            // If we were unable to send a message after 12 hours, mark as failed
            if offlineMessage.timestamp < twelveHoursAgoTimestamp {
                try? realm.transaction {
                    offlineMessage.isOfflineMessage = false
                    offlineMessage.sendingFailed = true
                }

                var userInfo: [AnyHashable: Any] = [:]
                userInfo["message"] = offlineMessage
                userInfo["isOfflineMessage"] = false

                if offlineMessage.referenceId != nil {
                    userInfo["referenceId"] = offlineMessage.referenceId
                }

                // Inform the chatViewController about this change
                NotificationCenter.default.post(name: .NCChatControllerDidSendChatMessage, object: self, userInfo: userInfo)
            } else {
                if let accountId = offlineMessage.accountId,
                   let room = NCDatabaseManager.sharedInstance().room(withToken: offlineMessage.token, forAccountId: accountId) {
                    if offlineMessage.threadId > 0 && offlineMessage.isThread {
                        guard let chatController = NCChatController(forThreadId: offlineMessage.threadId, in: room) else { return }
                        chatController.send(offlineMessage)
                    } else {
                        guard let chatController = NCChatController(for: room) else { return }
                        chatController.send(offlineMessage)
                    }
                }
            }
        }

        completionBlock?()
    }

}
