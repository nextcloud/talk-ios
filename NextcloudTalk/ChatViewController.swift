//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import NextcloudKit
import PhotosUI
import UIKit

@objcMembers public class ChatViewController: BaseChatViewController {

    // MARK: - Public var
    public var presentedInCall = false
    public var chatController: NCChatController
    public var highlightMessageId = 0

    // MARK: - Private var
    private var hasPresentedLobby = false
    private var hasRequestedInitialHistory = false
    private var hasReceiveInitialHistory = false
    private var retrievingHistory = false

    private var hasJoinedRoom = false
    private var startReceivingMessagesAfterJoin = false
    private var offlineMode = false
    private var hasStoredHistory = true
    private var hasStopped = false

    private var chatViewPresentedTimestamp = Date().timeIntervalSince1970

    private lazy var unreadMessagesSeparator: NCChatMessage = {
        let message = NCChatMessage()
        message.messageId = kUnreadMessagesSeparatorIdentifier
        return message
    }()

    private lazy var lastReadMessage: Int = {
        return self.room.lastReadMessage
    }()

    private var lobbyCheckTimer: Timer?

    // MARK: - Video buttons in NavigationBar

    func getBarButton(forVideo video: Bool) -> BarButtonItemWithActivity {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        let buttonImage = UIImage(systemName: video ? "video" : "phone", withConfiguration: symbolConfiguration)

        let button = BarButtonItemWithActivity(width: 44, with: buttonImage)
        button.innerButton.addAction { [unowned self] in
            button.showIndicator()
            CallKitManager.sharedInstance().startCall(self.room.token, withVideoEnabled: video, andDisplayName: self.room.displayName, silently: false, withAccountId: self.room.accountId)
        }

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySilentCall) {
            let silentCall = UIAction(title: NSLocalizedString("Call without notification", comment: ""), image: UIImage(systemName: "bell.slash")) { [unowned self] _ in
                button.showIndicator()
                CallKitManager.sharedInstance().startCall(self.room.token, withVideoEnabled: video, andDisplayName: self.room.displayName, silently: true, withAccountId: self.room.accountId)
            }

            button.innerButton.menu = UIMenu(children: [silentCall])
        }

        return button
    }

    private lazy var videoCallButton: BarButtonItemWithActivity = {
        let videoCallButton = self.getBarButton(forVideo: true)

        videoCallButton.accessibilityLabel = NSLocalizedString("Video call", comment: "")
        videoCallButton.accessibilityHint = NSLocalizedString("Double tap to start a video call", comment: "")

        return videoCallButton
    }()

    private lazy var voiceCallButton: BarButtonItemWithActivity = {
        let voiceCallButton = self.getBarButton(forVideo: false)

        videoCallButton.accessibilityLabel = NSLocalizedString("Voice call", comment: "")
        videoCallButton.accessibilityHint = NSLocalizedString("Double tap to start a voice call", comment: "")

        return voiceCallButton
    }()

    private var messageExpirationTimer: Timer?

    public override init?(for room: NCRoom) {
        self.chatController = NCChatController(for: room)

        super.init(for: room)

        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidUpdateRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didJoinRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidJoinRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didLeaveRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidLeaveRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveInitialChatHistory(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveInitialChatHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveInitialChatHistoryOffline(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveInitialChatHistoryOffline, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatHistory(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatMessages(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatMessages, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didSendChatMessage(notification:)), name: NSNotification.Name.NCChatControllerDidSendChatMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatBlocked(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatBlocked, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveNewerCommonReadMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveNewerCommonReadMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveCallStartedMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveCallStartedMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveCallEndedMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveCallEndedMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveUpdateMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveUpdateMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveHistoryCleared(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveHistoryCleared, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMessagesInBackground(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveMessagesInBackground, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveParticipantJoin(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveJoinOfParticipant, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveParticipantLeave(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveLeaveOfParticipant, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveStartedTyping(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveStartedTyping, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveStoppedTyping(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveStoppedTyping, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didFailRequestingCallTransaction(notification:)), name: NSNotification.Name.CallKitManagerDidFailRequestingCallTransaction, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateParticipants(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidUpdateParticipants, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(notification:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(notification:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectionStateHasChanged(notification:)), name: NSNotification.Name.NCConnectionStateHasChanged, object: nil)

        // Notifications when runing on Mac
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(notification:)), name: NSNotification.Name(rawValue: "NSApplicationDidBecomeActiveNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(notification:)), name: NSNotification.Name(rawValue: "NSApplicationDidResignActiveNotification"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("Dealloc NewChatViewController")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        if NCSettingsController.sharedInstance().callsEnabledCapability() {
            let fixedSpace = UIBarButtonItem(systemItem: .fixedSpace)
            fixedSpace.width = 16
            self.navigationItem.rightBarButtonItems = [videoCallButton, fixedSpace, voiceCallButton]
        }

        // Disable room info, input bar and call buttons until joining room
        self.disableRoomControls()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.checkLobbyState()
        self.checkRoomControlsAvailability()

        self.startObservingExpiredMessages()

        // Workaround for open conversations:
        // We can't get initial chat history until we join the conversation (since we are not a participant until then)
        // So for rooms that we don't know the last read message we wait until we join the room to get the initial chat history.
        if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory, self.room.lastReadMessage > 0 {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }

        if !self.offlineMode {
            NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.saveLastReadMessage()
        self.stopVoiceMessagePlayer()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if self.isMovingFromParent {
            self.leaveChat()
        }

        self.videoCallButton.hideIndicator()
        self.voiceCallButton.hideIndicator()
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - App lifecycle

    func appDidBecomeActive(notification: Notification) {
        // Don't handle this event if the view is not loaded yet.
        // Otherwise we try to join the room and receive new messages while
        // viewDidLoad wasn't called, resulting in uninitialized dictionaries and crashes
        if !self.isViewLoaded {
            return
        }

        // If we stopped the chat, we don't want to resume it here
        if self.hasStopped {
            return
        }

        // Check if new messages were added while the app was inactive (eg. via background-refresh)
        self.checkForNewStoredMessages()

        if !self.offlineMode {
            NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
        }

        self.startObservingExpiredMessages()
    }

    func appWillResignActive(notification: Notification) {
        // If we stopped the chat, we don't want to change anything here
        if self.hasStopped {
            return
        }

        self.startReceivingMessagesAfterJoin = true
        self.removeUnreadMessagesSeparator()
        self.savePendingMessage()
        self.chatController.stop()
        self.messageExpirationTimer?.invalidate()
        self.stopTyping(force: false)
        NCRoomsManager.sharedInstance().leaveChat(inRoom: self.room.token)
    }

    func connectionStateHasChanged(notification: Notification) {
        guard let connectionState = notification.userInfo?["connectionState"] as? UInt32 else {
            return
        }

        switch connectionState {
        case kConnectionStateConnected.rawValue:
            if offlineMode {
                offlineMode = false
                startReceivingMessagesAfterJoin = true
                self.removeOfflineFooterView()
                NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
            }
        default:
            break
        }
    }

    // MARK: - User Interface

    func disableRoomControls() {
        self.titleView?.isUserInteractionEnabled = false

        self.videoCallButton.hideIndicator()
        self.videoCallButton.isEnabled = false
        self.voiceCallButton.hideIndicator()
        self.voiceCallButton.isEnabled = false

        self.rightButton.isEnabled = false
        self.leftButton.isEnabled = false
    }

    func checkRoomControlsAvailability() {
        if hasJoinedRoom, !offlineMode {
            // Enable room info and call buttons when we joined a room
            self.titleView?.isUserInteractionEnabled = true
            self.videoCallButton.isEnabled = true
            self.voiceCallButton.isEnabled = true
        }

        // Files/objects can only be send when we're not offline
        self.leftButton.isEnabled = !offlineMode

        // Always allow to start writing a message, even if we didn't join the room (yet)
        self.rightButton.isEnabled = self.canPressRightButton()
        self.textInputbar.isUserInteractionEnabled = true

        if !room.userCanStartCall(), !room.hasCall {
            // Disable call buttons
            self.videoCallButton.isEnabled = false
            self.voiceCallButton.isEnabled = false
        }

        if room.readOnlyState == NCRoomReadOnlyStateReadOnly || self.shouldPresentLobbyView() {
            // Hide text input
            self.setTextInputbarHidden(true, animated: self.isVisible)

            // Disable call buttons
            self.videoCallButton.isEnabled = false
            self.voiceCallButton.isEnabled = false
        } else if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatPermission), (room.permissions & NCPermission.chat.rawValue) == 0 {
            // Hide text input
            self.setTextInputbarHidden(true, animated: isVisible)
        } else if self.isTextInputbarHidden {
            // Show text input if it was hidden in a previous state
            self.setTextInputbarHidden(false, animated: isVisible)

            if self.tableView?.slk_isAtBottom ?? false {
                self.tableView?.slk_scrollToBottom(animated: true)
            }

            // Make sure the textinput has the correct height
            self.setChatMessage(self.textInputbar.textView.text)
        }

        if self.presentedInCall {
            // Create a close button and remove the call buttons
            let barButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), style: .plain, target: nil, action: nil)
            barButtonItem.primaryAction = UIAction(handler: { _ in
                NCRoomsManager.sharedInstance().callViewController?.toggleChatView()
            })
            self.navigationItem.rightBarButtonItems = [barButtonItem]
        }
    }

    func checkLobbyState() {
        if self.shouldPresentLobbyView() {
            self.hasPresentedLobby = true

            var placeholderText = NSLocalizedString("You are currently waiting in the lobby", comment: "")

            // Lobby timer
            if self.room.lobbyTimer > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(self.room.lobbyTimer))
                let meetingStart = NCUtils.readableDateTime(from: date)
                let meetingStartPlaceholder = NSLocalizedString("This meeting is scheduled for", comment: "The meeting start time will be displayed after this text e.g (This meeting is scheduled for tomorrow at 10:00)")
                placeholderText += "\n\n\(meetingStartPlaceholder)\n\(meetingStart)"
            }

            // Room description
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRoomDescription), !self.room.roomDescription.isEmpty {
                placeholderText += "\n\n" + self.room.roomDescription
            }

            // Only set it when text changes to avoid flickering in links
            if chatBackgroundView.placeholderTextView.text != placeholderText {
                chatBackgroundView.placeholderTextView.text = placeholderText
            }

            self.chatBackgroundView.setImage(UIImage(named: "lobby-placeholder"))
            self.chatBackgroundView.placeholderView.isHidden = false
            self.chatBackgroundView.loadingView.stopAnimating()
            self.chatBackgroundView.loadingView.isHidden = true

            // Clear current chat since chat history will be retrieved when lobby is disabled
            self.cleanChat()
        } else {
            self.chatBackgroundView.setImage(UIImage(named: "chat-placeholder"))
            self.chatBackgroundView.placeholderTextView.text = NSLocalizedString("No messages yet, start the conversation!", comment: "")
            self.chatBackgroundView.placeholderView.isHidden = true
            self.chatBackgroundView.loadingView.startAnimating()
            self.chatBackgroundView.loadingView.isHidden = false

            // Stop checking lobby flag
            self.lobbyCheckTimer?.invalidate()

            // Retrieve initial chat history if lobby was enabled and we didn't retrieve it before
            if !hasReceiveInitialHistory, !hasRequestedInitialHistory, hasPresentedLobby {
                self.hasRequestedInitialHistory = true
                self.chatController.getInitialChatHistory()
            }

            self.hasPresentedLobby = false
        }
    }

    func setOfflineFooterView() {
        let isAtBottom = self.shouldScrollOnNewMessages()

        let footerLabel = UILabel(frame: .init(x: 0, y: 0, width: 350, height: 24))
        footerLabel.textAlignment = .center
        footerLabel.textColor = .label
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.backgroundColor = .clear
        footerLabel.text = NSLocalizedString("Offline, only showing downloaded messages", comment: "")

        self.tableView?.tableFooterView = footerLabel
        self.tableView?.tableFooterView?.backgroundColor = .secondarySystemBackground

        if isAtBottom {
            self.tableView?.slk_scrollToBottom(animated: true)
        }
    }

    func removeOfflineFooterView() {
        DispatchQueue.main.async {
            self.tableView?.tableFooterView?.removeFromSuperview()
            self.tableView?.tableFooterView = nil

            // Scrolling after removing the tableFooterView won't scroll all the way to the bottom therefore just keep the current position
            // And don't try to call scrollToBottom
        }
    }

    // MARK: - Message expiration

    func startObservingExpiredMessages() {
        self.messageExpirationTimer?.invalidate()
        self.removeExpiredMessages()
        self.messageExpirationTimer = Timer(timeInterval: 30.0, repeats: true, block: { [weak self] _ in
            self?.removeExpiredMessages()
        })
    }

    func removeExpiredMessages() {
        DispatchQueue.main.async {
            let currentTimestamp = Int(Date().timeIntervalSince1970)

            for sectionIndex in self.dateSections.indices {
                let section = self.dateSections[sectionIndex]

                guard let messages = self.messages[section] else { continue }

                let deleteMessages = messages.filter { message in
                    return message.expirationTimestamp > 0 && message.expirationTimestamp <= currentTimestamp
                }

                if !deleteMessages.isEmpty {
                    self.tableView?.beginUpdates()

                    let filteredMessages = messages.filter { !deleteMessages.contains($0) }
                    self.messages[section] = filteredMessages

                    if !filteredMessages.isEmpty {
                        self.tableView?.reloadSections(IndexSet(integer: sectionIndex), with: .top)
                    } else {
                        self.messages.removeValue(forKey: section)
                        self.sortDateSections()
                        self.tableView?.deleteSections(IndexSet(integer: sectionIndex), with: .top  )
                    }

                    self.tableView?.endUpdates()
                }
            }

            self.chatController.removeExpiredMessages()
        }
    }

    // MARK: - Utils

    func presentJoinError(_ subtitle: String) {
        NotificationPresenter.shared().present(title: NSLocalizedString("Could not join conversation", comment: ""), subtitle: subtitle, includedStyle: .warning)
        NotificationPresenter.shared().dismiss(afterDelay: 8.0)
    }

    // MARK: - Action methods

    override func sendChatMessage(message: String, withParentMessage parentMessage: NCChatMessage?, messageParameters: String, silently: Bool) {
        // Create temporary message
        let temporaryMessage = self.createTemporaryMessage(message: message, replyTo: parentMessage, messageParameters: messageParameters, silently: silently)

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReferenceId) {
            self.appendTemporaryMessage(temporaryMessage: temporaryMessage)
        }

        // Send message
        self.chatController.send(temporaryMessage)
    }

    public override func canPressRightButton() -> Bool {
        let canPress = super.canPressRightButton()

        // If in offline mode, we don't want to show the voice button
        if !offlineMode, !canPress && !presentedInCall && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityVoiceMessage) {
            self.showVoiceMessageRecordButton()
            return true
        }

        self.showSendMessageButton()

        return canPress
    }

    // MARK: - Voice message player
    // Override the default implementation to don't hijack the audio session when presented in a call

    override func playVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.setSpeakerAudioSession()
            self.enableProximitySensor()
        }

        self.startVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.play()
    }

    override func pauseVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.disableProximitySensor()
        }

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.pause()
        self.checkVisibleCellAudioPlayers()
    }

    override func stopVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.disableProximitySensor()
        }

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.stop()
    }

    override func sensorStateChange(notification: Notification) {
        if self.presentedInCall {
            return
        }

        if UIDevice.current.proximityState {
            self.setVoiceChatAudioSession()
        } else {
            self.pauseVoiceMessagePlayer()
            self.setSpeakerAudioSession()
            self.disableProximitySensor()
        }
    }

    // MARK: - UIScrollViewDelegate methods

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        guard scrollView == self.tableView,
              scrollView.contentOffset.y < 0,
              self.couldRetrieveHistory()
        else { return }

        if let firstMessage = self.getFirstRealMessage()?.message,
            self.chatController.hasHistory(fromMessageId: firstMessage.messageId) {

            self.retrievingHistory = true
            self.showLoadingHistoryView()

            if self.offlineMode {
                self.chatController.getHistoryBatchOffline(fromMessagesId: firstMessage.messageId)
            } else {
                self.chatController.getHistoryBatch(fromMessagesId: firstMessage.messageId)
            }
        }
    }

    public func stopChat() {
        self.hasStopped = true
        self.chatController.stop()
        self.cleanChat()
    }

    public func resumeChat() {
        self.hasStopped = false

        if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }
    }

    public func leaveChat() {
        self.lobbyCheckTimer?.invalidate()
        self.messageExpirationTimer?.invalidate()
        self.chatController.stop()

        // In case we're typing when we leave the chat, make sure we notify everyone
        // The 'stopTyping' method makes sure to only send signaling messages when we were typing before
        self.stopTyping(force: false)

        // If this chat view controller is for the same room as the one owned by the rooms manager
        // then we should not try to leave the chat. Since we will leave the chat when the
        // chat view controller owned by rooms manager moves from parent view controller.
        if NCRoomsManager.sharedInstance().chatViewController?.room.token == self.room.token,
           NCRoomsManager.sharedInstance().chatViewController !== self {
            return
        }

        NCRoomsManager.sharedInstance().leaveChat(inRoom: self.room.token)

        // Remove chat view controller pointer if this chat is owned by rooms manager
        // and the chat view is moving from parent view controller
        if NCRoomsManager.sharedInstance().chatViewController === self {
            NCRoomsManager.sharedInstance().chatViewController = nil
        }
    }

    public override func cleanChat() {
        super.cleanChat()

        self.hasReceiveInitialHistory = false
        self.hasRequestedInitialHistory = false
        self.chatController.hasReceivedMessagesFromServer = false
    }

    func saveLastReadMessage() {
        NCRoomsManager.sharedInstance().updateLastReadMessage(self.lastReadMessage, for: self.room)
    }

    // MARK: - Room Manager notifications

    func didUpdateRoom(notification: Notification) {
        guard let room = notification.userInfo?["room"] as? NCRoom else { return }

        if room.token != self.room.token {
            return
        }

        self.room = room
        self.setTitleView()

        if !self.hasStopped {
            self.checkLobbyState()
            self.checkRoomControlsAvailability()
        }
    }

    func didJoinRoom(notification: Notification) {
        guard let token = notification.userInfo?["token"] as? String else { return }

        if token != self.room.token {
            return
        }

        if self.isVisible,
            notification.userInfo?["error"] != nil,
            let errorReason = notification.userInfo?["errorReason"] as? String {

            self.offlineMode = true
            self.setOfflineFooterView()
            self.chatController.stopReceivingNewChatMessages()
            self.presentJoinError(errorReason)
            self.disableRoomControls()
            self.checkRoomControlsAvailability()
            return
        }

        if let room = notification.userInfo?["room"] as? NCRoom {
            self.room = room
        }

        self.hasJoinedRoom = true
        self.checkRoomControlsAvailability()

        if self.hasStopped {
            return
        }

        if self.startReceivingMessagesAfterJoin, self.hasReceiveInitialHistory {
            self.startReceivingMessagesAfterJoin = false
            self.chatController.startReceivingNewChatMessages()
        } else if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [capturedToken = self.room.token] in
            // After we joined a room, check if there are offline messages for this particular room which need to be send
            NCRoomsManager.sharedInstance().resendOfflineMessages(forToken: capturedToken, withCompletionBlock: nil)
        }
    }

    func didLeaveRoom(notification: Notification) {
        self.hasJoinedRoom = false
        self.disableRoomControls()
        self.checkRoomControlsAvailability()
    }

    // MARK: - CallKit Manager notifications

    func didFailRequestingCallTransaction(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String else { return }

        if token != self.room.token {
            return
        }

        DispatchQueue.main.async {
            self.videoCallButton.hideIndicator()
            self.voiceCallButton.hideIndicator()
        }
    }

    // MARK: - Chat Controller notifications

    // swiftlint:disable:next cyclomatic_complexity
    func didReceiveInitialChatHistory(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if self.shouldPresentLobbyView() {
                self.hasRequestedInitialHistory = false
                self.startObservingRoomLobbyFlag()

                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {

                var indexPathUnreadMessageSeparator: IndexPath?
                let lastMessage = messages.reversed().first(where: { !$0.isUpdateMessage() })

                self.appendMessages(messages: messages)

                if let lastMessage, lastMessage.messageId > self.lastReadMessage {
                    // Iterate backwards to find the correct location for the unread message separator
                    for sectionIndex in self.dateSections.indices.reversed() {
                        let dateSection: Date = self.dateSections[sectionIndex]

                        guard var messages = self.messages[dateSection] else { continue }

                        for messageIndex in messages.indices.reversed() {
                            let message = messages[messageIndex]

                            if message.messageId > self.lastReadMessage {
                                continue
                            }

                            messages.insert(self.unreadMessagesSeparator, at: messageIndex + 1)
                            self.messages[dateSection] = messages
                            indexPathUnreadMessageSeparator = IndexPath(row: messageIndex + 1, section: sectionIndex)

                            break
                        }

                        if indexPathUnreadMessageSeparator != nil {
                            break
                        }
                    }

                    self.lastReadMessage = lastMessage.messageId
                }

                let storedTemporaryMessages = self.chatController.getTemporaryMessages()

                if !storedTemporaryMessages.isEmpty {
                    self.insertMessages(messages: storedTemporaryMessages)

                    if indexPathUnreadMessageSeparator != nil {
                        // It is possible that temporary messages are added which add new sections
                        // In this case the indexPath of the unreadMessageSeparator would be invalid and could lead to a crash
                        // Therefore we need to make sure we got the correct indexPath here
                        indexPathUnreadMessageSeparator = self.indexPathForUnreadMessageSeparator()
                    }
                }

                self.tableView?.reloadData()

                if let indexPathUnreadMessageSeparator {
                    self.tableView?.scrollToRow(at: indexPathUnreadMessageSeparator, at: .middle, animated: false)
                } else {
                    self.tableView?.slk_scrollToBottom(animated: false)
                }

                self.updateToolbar(animated: false)
            } else {
                self.chatBackgroundView.placeholderView.isHidden = false
            }

            self.hasReceiveInitialHistory = true

            if notification.userInfo?["error"] == nil {
                self.chatController.startReceivingNewChatMessages()
            } else {
                self.offlineMode = true
                self.chatController.getInitialChatHistoryForOfflineMode()
            }
        }
    }

    func didReceiveInitialChatHistoryOffline(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {
                self.appendMessages(messages: messages)
                self.setOfflineFooterView()
                self.tableView?.reloadData()
                self.tableView?.slk_scrollToBottom(animated: false)
                self.updateToolbar(animated: false)
            } else {
                self.chatBackgroundView.placeholderView.isHidden = false
            }

            let storedTemporaryMessages = self.chatController.getTemporaryMessages()

            if !storedTemporaryMessages.isEmpty {

                self.insertMessages(messages: storedTemporaryMessages)
                self.tableView?.reloadData()
                self.tableView?.slk_scrollToBottom(animated: false)
                self.updateToolbar(animated: false)
            }
        }
    }

    func didReceiveChatHistory(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {

                let shouldAddBlockSeparator = notification.userInfo?["shouldAddBlockSeparator"] as? Bool ?? false

                if let lastHistoryMessageIP = self.prependMessages(historyMessages: messages, addingBlockSeparator: shouldAddBlockSeparator),
                   let tableView = self.tableView {

                    self.tableView?.reloadData()

                    if NCUtils.isValidIndexPath(lastHistoryMessageIP, for: tableView) {
                        self.tableView?.scrollToRow(at: lastHistoryMessageIP, at: .top, animated: false)
                    }
                }
            }

            if notification.userInfo?["noMoreStoredHistory"] as? Bool == true {
                self.hasStoredHistory = false
            }

            self.retrievingHistory = false
            self.hideLoadingHistoryView()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func didReceiveChatMessages(notification: Notification) {
        // If we receive messages in the background, we should make sure that our update here completely run
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "didReceiveChatMessages")

        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController || notification.userInfo?["error"] != nil {
                return
            }

            let firstNewMessagesAfterHistory = notification.userInfo?["firstNewMessagesAfterHistory"] as? Bool ?? false

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], let tableView = self.tableView, !messages.isEmpty {
                // Detect if we should scroll to new messages before we issue a reloadData
                // Otherwise longer messages will prevent scrolling
                let shouldScrollOnNewMessages = self.shouldScrollOnNewMessages()
                let newMessagesContainVisibleMessages = messages.containsVisibleMessages()

                // Use a Set here so we don't have to deal with duplicates
                var insertIndexPaths: Set<IndexPath> = []
                var insertSections: IndexSet = []
                var reloadIndexPaths: Set<IndexPath> = []

                // Check if unread messages separator should be added (only if it's not already shown)
                if firstNewMessagesAfterHistory, self.getLastRealMessage() != nil, self.indexPathForUnreadMessageSeparator() == nil, newMessagesContainVisibleMessages,
                   let lastDateSection = self.dateSections.last, var messagesBeforeUpdate = self.messages[lastDateSection] {

                    messagesBeforeUpdate.append(self.unreadMessagesSeparator)
                    self.messages[lastDateSection] = messagesBeforeUpdate
                    insertIndexPaths.insert(IndexPath(row: messagesBeforeUpdate.count - 1, section: self.dateSections.count - 1))
                }

                self.appendMessages(messages: messages)

                for newMessage in messages {
                    // If we don't get an indexPath here, something is wrong with our appendMessages function
                    let indexPath = self.indexPath(for: newMessage)!

                    if indexPath.section >= tableView.numberOfSections {
                        // New section -> insert the section
                        insertSections.insert(indexPath.section)
                    }

                    if indexPath.section < tableView.numberOfSections, indexPath.row < tableView.numberOfRows(inSection: indexPath.section) {
                        // This is a already known indexPath, so we want to reload the cell
                        reloadIndexPaths.insert(indexPath)
                    } else {
                        // New indexPath -> insert it
                        insertIndexPaths.insert(indexPath)
                    }

                    if newMessage.isUpdateMessage(), let parentMessage = newMessage.parent(), let parentPath = self.indexPath(for: parentMessage) {
                        if parentPath.section < tableView.numberOfSections, parentPath.row < tableView.numberOfRows(inSection: parentPath.section) {
                            // We received an update message to a message which is already part of our current data, therefore we need to reload it
                            reloadIndexPaths.insert(parentPath)
                        }
                    }

                    if let collapsedByMessage = newMessage.collapsedBy, let collapsedPath = self.indexPath(for: collapsedByMessage) {
                        if collapsedPath.section < tableView.numberOfSections, collapsedPath.row < tableView.numberOfRows(inSection: collapsedPath.section) {
                            // The current message is collapsed, so we need to make sure that the collapsedBy message is reloaded
                            reloadIndexPaths.insert(collapsedPath)
                        }
                    }
                }

                tableView.performBatchUpdates {
                    if !insertSections.isEmpty {
                        tableView.insertSections(insertSections, with: .automatic)
                    }

                    if !insertIndexPaths.isEmpty {
                        tableView.insertRows(at: Array(insertIndexPaths), with: .automatic)
                    }

                    if !reloadIndexPaths.isEmpty {
                        tableView.reloadRows(at: Array(reloadIndexPaths), with: .none)
                    }

                } completion: { _ in
                    // Remove unread messages separator when user writes a message
                    if messages.containsUserMessage() {
                        self.removeUnreadMessagesSeparator()
                    }

                    if let indexPathUnreadMessageSeparator = self.indexPathForUnreadMessageSeparator() {
                        tableView.scrollToRow(at: indexPathUnreadMessageSeparator, at: .middle, animated: true)
                    } else if (shouldScrollOnNewMessages || messages.containsUserMessage()), let lastIndexPath = self.getLastRealMessage()?.indexPath {
                        tableView.scrollToRow(at: lastIndexPath, at: .none, animated: true)
                    } else if self.firstUnreadMessage == nil, newMessagesContainVisibleMessages, let firstNewMessage = messages.first {
                        // This check is needed since several calls to receiveMessages API might be needed
                        // (if the number of unread messages is bigger than the "limit" in receiveMessages request)
                        // to receive all the unread messages.
                        if firstNewMessage.timestamp >= Int(self.chatViewPresentedTimestamp) {
                            self.showNewMessagesView(until: firstNewMessage)
                        }
                    }

                    // Set last received message as last read message
                    if let lastReceivedMessage = messages.last {
                        self.lastReadMessage = lastReceivedMessage.messageId
                    }
                }

                if firstNewMessagesAfterHistory {
                    self.chatBackgroundView.loadingView.stopAnimating()
                    self.chatBackgroundView.loadingView.isHidden = true
                }

                if self.highlightMessageId > 0, let indexPath = self.indexPathAndMessage(forMessageId: self.highlightMessageId)?.indexPath {
                    self.highlightMessage(at: indexPath, with: .middle)
                    self.highlightMessageId = 0
                }
            }

            bgTask.stopBackgroundTask()
        }
    }

    func didSendChatMessage(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if notification.userInfo?["error"] == nil {
                return
            }

            guard let message = notification.userInfo?["message"] as? String else { return }

            if let referenceId = notification.userInfo?["referenceId"] as? String {
                // Got a referenceId -> update the corresponding message
                let isOfflineMessage = notification.userInfo?["isOfflineMessage"] as? Bool ?? false

                self.modifyMessageWith(referenceId: referenceId) { message in
                    message.sendingFailed = !isOfflineMessage
                    message.isOfflineMessage = isOfflineMessage
                }

            } else {
                // No referenceId -> show generic error
                self.textView.text = message

                let alert = UIAlertController(title: NSLocalizedString("Could not send the message", comment: ""),
                                              message: NSLocalizedString("An error occurred while sending the message", comment: ""),
                                              preferredStyle: .alert)

                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    func didReceiveChatBlocked(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.startObservingRoomLobbyFlag()
    }

    func didReceiveNewerCommonReadMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let lastCommonReadMessage = notification.userInfo?["lastCommonReadMessage"] as? Int else { return }

        if lastCommonReadMessage > self.room.lastCommonReadMessage {
            self.room.lastCommonReadMessage = lastCommonReadMessage
        }

        self.checkLastCommonReadMessage()
    }

    func didReceiveCallStartedMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.room.hasCall = true
        self.checkRoomControlsAvailability()
    }

    func didReceiveCallEndedMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.room.hasCall = false
        self.checkRoomControlsAvailability()
    }

    func didReceiveUpdateMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let message = notification.userInfo?["updateMessage"] as? NCChatMessage,
              let deleteMessage = message.parent()
        else { return }

        self.updateMessage(withMessageId: deleteMessage.messageId, updatedMessage: deleteMessage)
    }

    func didReceiveHistoryCleared(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let message = notification.userInfo?["historyCleared"] as? NCChatMessage
        else { return }

        if self.chatController.hasOlderStoredMessagesThanMessageId(message.messageId) {
            self.cleanChat()
            self.chatController.clearHistoryAndResetChatController()
            self.hasRequestedInitialHistory = false
            self.chatController.getInitialChatHistory()
        }
    }

    func didReceiveMessagesInBackground(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        print("didReceiveMessagesInBackground")
        self.checkForNewStoredMessages()
    }

    // MARK: - External signaling controller notifications

    func didUpdateParticipants(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String else { return }

        if token != self.room.token {
            return
        }

        let serverSupportsConversationPermissions = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationPermissions) ||
                                                    NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDirectMentionFlag)

        guard serverSupportsConversationPermissions else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Retrieve the information about ourselves
        guard let userDict = notification.userInfo?["users"] as? [[String: String]],
              let appUserDict = userDict.first(where: { $0["userId"] == activeAccount.userId })
        else { return }

        // Check if we still have the same permissions

        if let permissionsString = appUserDict["participantPermissions"],
           let permissions = Int(permissionsString),
           permissions != self.room.permissions {

            // Need to update the room from the api because otherwise "canStartCall" is not updated correctly
            NCRoomsManager.sharedInstance().updateRoom(self.room.token, withCompletionBlock: nil)
        }
    }

    func processTypingNotification(notification: Notification, startedTyping started: Bool) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        // Waiting for https://github.com/nextcloud/spreed/issues/9726 to receive the correct displayname for guests
        let displayName = notification.userInfo?["displayName"] as? String ?? NSLocalizedString("Guest", comment: "")

        // Don't show a typing indicator for ourselves or if typing indicator setting is disabled
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)

        let userId = notification.userInfo?["userId"] as? String

        if userId == activeAccount.userId || serverCapabilities.typingPrivacy {
            return
        }

        // For guests we use the sessionId as an identifier, for users we use the userId
        var userIdentifier = sessionId

        if let userId, !userId.isEmpty {
            userIdentifier = userId
        }

        if started {
            self.addTypingIndicator(withUserIdentifier: userIdentifier, andDisplayName: displayName)
        } else {
            self.removeTypingIndicator(withUserIdentifier: userIdentifier)
        }
    }

    func didReceiveStartedTyping(notification: Notification) {
        self.processTypingNotification(notification: notification, startedTyping: true)
    }

    func didReceiveStoppedTyping(notification: Notification) {
        self.processTypingNotification(notification: notification, startedTyping: false)
    }

    func didReceiveParticipantJoin(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        DispatchQueue.main.async {
            if self.isTyping {
                self.sendStartedTypingMessage(to: sessionId)
            }
        }
    }

    func didReceiveParticipantLeave(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        // For guests we use the sessionId as an identifier, for users we use the userId
        var userIdentifier = sessionId

        if let userId = notification.userInfo?["userId"] as? String, !userId.isEmpty {
            userIdentifier = userId
        }

        self.removeTypingIndicator(withUserIdentifier: userIdentifier)
    }

    // MARK: - Lobby functions

    func startObservingRoomLobbyFlag() {
        self.updateRoomInformation()

        DispatchQueue.main.async {
            self.lobbyCheckTimer?.invalidate()
            self.lobbyCheckTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.updateRoomInformation), userInfo: nil, repeats: true)
        }
    }

    func updateRoomInformation() {
        NCRoomsManager.sharedInstance().updateRoom(self.room.token, withCompletionBlock: nil)
    }

    func shouldPresentLobbyView() -> Bool {
        let serverSupportsConversationPermissions =
        NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationPermissions) ||
        NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDirectMentionFlag)

        if serverSupportsConversationPermissions, (self.room.permissions & NCPermission.canIgnoreLobby.rawValue) != 0 {
            return false
        }

        return self.room.lobbyState == NCRoomLobbyStateModeratorsOnly && self.room.canModerate()
    }

    // MARK: - Chat functions

    func couldRetrieveHistory() -> Bool {
        return self.hasReceiveInitialHistory &&
                !self.retrievingHistory &&
                !self.dateSections.isEmpty
                && self.hasStoredHistory
    }

    func checkLastCommonReadMessage() {
        DispatchQueue.main.async {
            guard let tableView = self.tableView,
                  let indexPathsForVisibleRows = tableView.indexPathsForVisibleRows
            else { return }

            var reloadCells: [IndexPath] = []

            for visibleIndexPath in indexPathsForVisibleRows {
                if let message = self.message(for: visibleIndexPath),
                   message.messageId > 0,
                   message.messageId <= self.room.lastCommonReadMessage {

                    reloadCells.append(visibleIndexPath)
                }
            }

            if !reloadCells.isEmpty {
                self.tableView?.beginUpdates()
                self.tableView?.reloadRows(at: reloadCells, with: .none)
                self.tableView?.endUpdates()
            }
        }
    }

    func checkForNewStoredMessages() {
        // Get the last "real" message. For temporary messages the messageId would be 0
        // which would load all stored messages of the current conversation
        if let lastMessage = self.getLastRealMessage()?.message {
            self.chatController.checkForNewMessages(fromMessageId: lastMessage.messageId)
            self.checkLastCommonReadMessage()
        }
    }

    // MARK: - ChatMessageTableViewCellDelegate delegate

    override public func cellDidSelectedReaction(_ reaction: NCChatReaction!, for message: NCChatMessage!) {
        self.addOrRemoveReaction(reaction: reaction, in: message)
    }

    // MARK: - ContextMenu (Long press on message)

    func isMessageReplyable(message: NCChatMessage) -> Bool {
        return message.isReplyable && !message.isDeleting
    }

    func isMessageReactable(message: NCChatMessage) -> Bool {
        var isReactable = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityReactions)
        isReactable = isReactable && !self.offlineMode
        isReactable = isReactable && self.room.readOnlyState != NCRoomReadOnlyStateReadOnly
        isReactable = isReactable && !message.isDeletedMessage() && !message.isCommandMessage() && !message.sendingFailed && !message.isTemporary

        return isReactable
    }

    func getSetReminderOptions(for message: NCChatMessage) -> [UIMenuElement] {
        var reminderOptions: [UIMenuElement] = []
        let now = Date()

        let sunday = 1
        let monday = 2
        let friday = 6
        let saturday = 7

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        let setReminderCompletion: SetReminderForMessage = { (error: Error?) in
            if error != nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("Error occurred when creating a reminder", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            } else {
                NotificationPresenter.shared().present(text: NSLocalizedString("Reminder was successfully set", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
            }
        }

        // Today
        let laterTodayTime = NCUtils.today(withHour: 18, withMinute: 0, withSecond: 0)
        let laterToday = UIAction(title: NSLocalizedString("Later today", comment: "Remind me later today about that message"), subtitle: NCUtils.getTimeFrom(laterTodayTime)) { _ in
            let timestamp = String(Int(laterTodayTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }

        // Tomorrow
        var tomorrowTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)
        tomorrowTime = Calendar.current.date(byAdding: .day, value: 1, to: tomorrowTime)!
        let tomorrow = UIAction(title: NSLocalizedString("Tomorrow", comment: "Remind me tomrrow about that message")) { _ in
            let timestamp = String(Int(tomorrowTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        tomorrow.subtitle = "\(formatter.string(from: tomorrowTime)), \(NCUtils.getTimeFrom(tomorrowTime))"

        // This weekend
        var weekendTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)
        weekendTime = NCUtils.setWeekday(saturday, with: weekendTime)
        let thisWeekend = UIAction(title: NSLocalizedString("This weekend", comment: "Remind me this weekend about that message")) { _ in
            let timestamp = String(Int(weekendTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        thisWeekend.subtitle = "\(formatter.string(from: weekendTime)), \(NCUtils.getTimeFrom(weekendTime))"

        // Next week
        var nextWeekTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)
        nextWeekTime = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: nextWeekTime)!
        nextWeekTime = NCUtils.setWeekday(monday, with: nextWeekTime)
        let nextWeek = UIAction(title: NSLocalizedString("Next week", comment: "Remind me next week about that message")) { _ in
            let timestamp = String(Int(nextWeekTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        nextWeek.subtitle = "\(formatter.string(from: nextWeekTime)), \(NCUtils.getTimeFrom(nextWeekTime))"

        // Custom reminder
        let customReminderAction = UIAction(title: NSLocalizedString("Pick date & time", comment: ""), image: .init(systemName: "calendar.badge.clock")) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.interactingMessage = message
                self.lastMessageBeforeInteraction = self.tableView?.indexPathsForVisibleRows?.last

                let startingDate = Calendar.current.date(byAdding: .hour, value: 1, to: now)
                let minimumDate = Calendar.current.date(byAdding: .minute, value: 15, to: now)

                self.datePickerTextField.getDate(startingDate: startingDate, minimumDate: minimumDate) { selectedDate in
                    let timestamp = String(Int(selectedDate.timeIntervalSince1970))
                    NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
                }
            }
        }

        let customReminder = UIMenu(options: .displayInline, children: [customReminderAction])

        // Hide "Later today" when it's past 5pm
        if Calendar.current.component(.hour, from: now) < 17 {
            reminderOptions.append(laterToday)
        }

        reminderOptions.append(tomorrow)

        // Only show "This weekend" for Mon-Tue
        let nowWeekday = Calendar.current.component(.weekday, from: now)
        if nowWeekday != friday && nowWeekday != saturday && nowWeekday != sunday {
            reminderOptions.append(thisWeekend)
        }

        // "Next week" should be hidden on sunday
        if nowWeekday != sunday {
            reminderOptions.append(nextWeek)
        }

        reminderOptions.append(customReminder)

        return reminderOptions
    }

    override func getContextMenuAccessoryView(forMessage message: NCChatMessage, forIndexPath indexPath: IndexPath, withCellHeight cellHeight: CGFloat) -> UIView? {
        let hasChatPermissions = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatPermission) || (self.room.permissions & NCPermission.chat.rawValue) != 0

        guard hasChatPermissions && self.isMessageReactable(message: message) else { return nil }

        let reactionViewPadding = 10
        let emojiButtonPadding = 10
        let emojiButtonSize = 48
        let frequentlyUsedEmojis = ["👍", "❤️", "😂", "😅"]

        let totalEmojiButtonWidth = frequentlyUsedEmojis.count * emojiButtonSize
        let totalEmojiButtonPadding = frequentlyUsedEmojis.count * emojiButtonPadding
        let addButtonWidth = emojiButtonSize + emojiButtonPadding

        // We need to add an extra padding to the right so the buttons are correctly padded
        let reactionViewWidth = totalEmojiButtonWidth + totalEmojiButtonPadding + addButtonWidth + emojiButtonPadding
        let reactionView = UIView(frame: .init(x: 0, y: Int(cellHeight) + reactionViewPadding, width: reactionViewWidth, height: emojiButtonSize))

        var positionX = emojiButtonPadding

        for emoji in frequentlyUsedEmojis {
            let emojiShortcutButton = UIButton(type: .system)
            emojiShortcutButton.frame = CGRect(x: positionX, y: 0, width: emojiButtonSize, height: emojiButtonSize)
            emojiShortcutButton.layer.cornerRadius = CGFloat(emojiButtonSize) / 2

            emojiShortcutButton.titleLabel?.font = .systemFont(ofSize: 20)
            emojiShortcutButton.setTitle(emoji, for: .normal)
            emojiShortcutButton.backgroundColor = .systemBackground

            emojiShortcutButton.addAction { [weak self] in
                guard let self else { return }
                self.tableView?.contextMenuInteraction?.dismissMenu()

                self.contextMenuActionBlock = {
                    self.addReaction(reaction: emoji, to: message)
                }
            }

            // Disable shortcuts, if we already reacted with that emoji
            for reaction in message.reactionsArray() {
                if reaction.reaction == emoji && reaction.userReacted {
                    emojiShortcutButton.isEnabled = false
                    emojiShortcutButton.alpha = 0.4
                    break
                }
            }

            reactionView.addSubview(emojiShortcutButton)
            positionX += emojiButtonSize + emojiButtonPadding
        }

        let addReactionButton = UIButton(type: .system)
        addReactionButton.frame = CGRect(x: positionX, y: 0, width: emojiButtonSize, height: emojiButtonSize)
        addReactionButton.layer.cornerRadius = CGFloat(emojiButtonSize) / 2

        addReactionButton.titleLabel?.font = .systemFont(ofSize: 22)
        addReactionButton.setImage(.init(systemName: "plus"), for: .normal)
        addReactionButton.tintColor = .label
        addReactionButton.backgroundColor = .systemBackground
        addReactionButton.addAction { [weak self] in
            guard let self else { return }
            self.tableView?.contextMenuInteraction?.dismissMenu()

            self.contextMenuActionBlock = {
                self.didPressAddReaction(for: message, at: indexPath)
            }
        }

        reactionView.addSubview(addReactionButton)

        // The reactionView will be shown after the animation finishes, otherwise we see the view already when animating and this looks odd
        reactionView.alpha = 0
        reactionView.layer.cornerRadius = CGFloat(emojiButtonSize) / 2
        reactionView.backgroundColor = .systemBackground

        return reactionView
    }

    // swiftlint:disable:next cyclomatic_complexity
    public override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if tableView == self.autoCompletionView {
            return nil
        }

        if let cell = tableView.cellForRow(at: indexPath) as? ChatTableViewCell {
            let pointInCell = tableView.convert(point, to: cell)
            let reactionView = cell.contentView.subviews.first(where: { $0 is ReactionsView && $0.frame.contains(pointInCell) })

            if reactionView != nil {
                self.showReactionsSummary(of: cell.message)
                return nil
            }
        }

        guard let message = self.message(for: indexPath) else { return nil }

        if message.isSystemMessage() || message.isDeletedMessage() || message.messageId == kUnreadMessagesSeparatorIdentifier {
            return nil
        }

        var actions: [UIMenuElement] = []
        let hasChatPermissions = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatPermission) || (self.room.permissions & NCPermission.chat.rawValue) != 0

        // Reply option
        if self.isMessageReplyable(message: message), hasChatPermissions {
            actions.append(UIAction(title: NSLocalizedString("Reply", comment: ""), image: .init(systemName: "arrowshape.turn.up.left")) { _ in
                self.didPressReply(for: message)
            })
        }

        // Reply-privately option (only to other users and not in one-to-one)
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if self.isMessageReplyable(message: message), self.room.type != kNCRoomTypeOneToOne, message.actorType == "users", message.actorId != activeAccount.userId {
            actions.append(UIAction(title: NSLocalizedString("Reply privately", comment: ""), image: .init(systemName: "person")) { _ in
                self.didPressReplyPrivately(for: message)
            })
        }

        // Forward option (only normal messages for now)
        if message.file() == nil && message.poll() == nil && !message.isDeletedMessage() {
            actions.append(UIAction(title: NSLocalizedString("Forward", comment: ""), image: .init(systemName: "arrowshape.turn.up.right")) { _ in
                self.didPressForward(for: message)
            })
        }

        // Remind me later
        if !message.sendingFailed, !message.isOfflineMessage, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRemindMeLater) {
            let deferredMenuElement = UIDeferredMenuElement.uncached { [weak self] completion in
                NCAPIController.sharedInstance().getReminderFor(message) { [weak self] response, error in
                    guard let self else { return }

                    var menuOptions: [UIMenuElement] = []
                    menuOptions.append(contentsOf: self.getSetReminderOptions(for: message))

                    if error == nil,
                       let responseDict = response as? [String: Any],
                       let timestamp = responseDict["timestamp"] as? Int {

                        // There's already an existing reminder set for this message
                        // -> offer a delete option
                        let timestampDate = Date(timeIntervalSince1970: TimeInterval(timestamp))

                        let clearAction = UIAction(title: NSLocalizedString("Clear reminder", comment: ""), image: .init(systemName: "trash")) { _ in
                            NCAPIController.sharedInstance().deleteReminder(for: message) { error in
                                if error == nil {
                                    NotificationPresenter.shared().present(text: NSLocalizedString("Reminder was successfully cleared", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                                } else {
                                    NotificationPresenter.shared().present(text: NSLocalizedString("Failed to clear reminder", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                                }
                            }
                        }
                        clearAction.subtitle = NCUtils.readableDateTime(from: timestampDate)
                        clearAction.attributes = .destructive

                        menuOptions.append(UIMenu(options: .displayInline, children: [clearAction]))
                    }

                    completion(menuOptions)
                }
            }

            actions.append(UIMenu(title: NSLocalizedString("Set reminder", comment: "Remind me later about that message"),
                                  image: .init(systemName: "alarm"),
                                  children: [deferredMenuElement]))
        }

        // Re-send option
        if (message.sendingFailed || message.isOfflineMessage) && hasChatPermissions {
            actions.append(UIAction(title: NSLocalizedString("Resend", comment: ""), image: .init(systemName: "arrow.clockwise")) { _ in
                self.didPressResend(for: message)
            })
        }

        // Copy option
        actions.append(UIAction(title: NSLocalizedString("Copy", comment: ""), image: .init(systemName: "square.on.square")) { _ in
            self.didPressCopy(for: message)
        })

        // Translate
        if !self.offlineMode, !NCSettingsController.sharedInstance().availableTranslations().isEmpty {
            actions.append(UIAction(title: NSLocalizedString("Translate", comment: ""), image: .init(systemName: "character.book.closed")) { _ in
                self.didPressTranslate(for: message)
            })
        }

        // Open in nextcloud option
        if !self.offlineMode, message.file() != nil {
            let openInNextcloudTitle = String(format: NSLocalizedString("Open in %@", comment: ""), filesAppName)
            actions.append(UIAction(title: openInNextcloudTitle, image: .init(named: "logo-action")?.withRenderingMode(.alwaysTemplate)) { _ in
                self.didPressOpenInNextcloud(for: message)
            })
        }

        // Transcribe voice-message
        if message.messageType == kMessageTypeVoiceMessage {
            let transcribeTitle = NSLocalizedString("Transcribe", comment: "TRANSLATORS this is for transcribing a voice message to text")
            actions.append(UIAction(title: transcribeTitle, image: .init(systemName: "text.bubble")) { _ in
                self.didPressTranscribeVoiceMessage(for: message)
            })
        }

        // Delete option
        if message.sendingFailed || message.isOfflineMessage || (message.isDeletable(for: activeAccount, in: self.room) && hasChatPermissions) {
            actions.append(UIAction(title: NSLocalizedString("Delete", comment: ""), image: .init(systemName: "trash"), attributes: .destructive) { _ in
                self.didPressDelete(for: message)
            })
        }

        let menu = UIMenu(children: actions)

        let configuration = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath) {
            return nil
        } actionProvider: { _ in
            return menu
        }

        return configuration
    }

    // MARK: - NCChatTitleViewDelegate

    public override func chatTitleViewTapped(_ titleView: NCChatTitleView!) {
        guard let roomInfoVC = RoomInfoTableViewController(for: self.room, from: self) else { return }
        roomInfoVC.hideDestructiveActions = self.presentedInCall

        if let splitViewController = NCUserInterfaceController.sharedInstance().mainViewController {
            if !splitViewController.isCollapsed {
                roomInfoVC.modalPresentationStyle = .pageSheet
                let navController = UINavigationController(rootViewController: roomInfoVC)
                self.present(navController, animated: true)
            } else {
                self.navigationController?.pushViewController(roomInfoVC, animated: true)
            }
        } else {
            self.navigationController?.pushViewController(roomInfoVC, animated: true)
        }

        // When returning from RoomInfoTableViewController the default keyboard will be shown, so the height might be wrong -> make sure the keyboard is hidden
        self.dismissKeyboard(true)
    }
}

extension Notification.Name {
    static let NCChatViewControllerReplyPrivatelyNotification = Notification.Name(rawValue: "NCChatViewControllerReplyPrivatelyNotification")
    static let NCChatViewControllerForwardNotification = Notification.Name(rawValue: "NCChatViewControllerForwardNotification")
    static let NCChatViewControllerTalkToUserNotification = Notification.Name(rawValue: "NCChatViewControllerTalkToUserNotification")
}

@objc extension NSNotification {
    public static let NCChatViewControllerReplyPrivatelyNotification = Notification.Name.NCChatViewControllerReplyPrivatelyNotification
    public static let NCChatViewControllerForwardNotification = Notification.Name.NCChatViewControllerForwardNotification
    public static let NCChatViewControllerTalkToUserNotification = Notification.Name.NCChatViewControllerTalkToUserNotification
}
